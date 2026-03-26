# Claude Code Context Pressure Widget - Shared library functions (Windows)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\config.ps1"

$StateFile = "$env:TEMP\cc-context-widget-state.json"

# ─── Find active Claude Code session ──────────────────────────
function Find-ActiveSession {
    if (-not $global:SESSIONS_DIR -or -not (Test-Path $global:SESSIONS_DIR)) {
        return $null
    }
    
    # Find the most recently modified .jsonl session file
    $latest = Get-ChildItem -Path $global:SESSIONS_DIR -Filter "*.jsonl" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    
    if ($latest) {
        return $latest.FullName
    }
    return $null
}

# ─── Parse context stats from session file ─────────────────────
function Get-SessionContext {
    param([string]$SessionFile)
    
    if (-not $SessionFile -or -not (Test-Path $SessionFile)) {
        return @{
            current_k = 0
            max_k = 0
            pct = 0
            compactions = 0
            session_id = "unknown"
            error = "no_session"
        }
    }
    
    $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($SessionFile)
    
    # Count compaction events
    $content = Get-Content $SessionFile -Raw -ErrorAction SilentlyContinue
    $compactions = 0
    if ($content) {
        $compactions += ([regex]::Matches($content, '"type":"compact"')).Count
        $compactions += ([regex]::Matches($content, '"type":"compaction"')).Count
        $compactions += ([regex]::Matches($content, '"PostCompact"')).Count
    }
    
    # Extract token usage from recent messages
    $lines = Get-Content $SessionFile -Tail 100 -ErrorAction SilentlyContinue
    $usageData = $lines | Select-String -Pattern '"usage":\{[^}]*\}' | Select-Object -Last 1
    
    $totalInput = 0
    $totalOutput = 0
    $totalCache = 0
    $maxK = 200
    
    if ($usageData) {
        $usage = $usageData.Line
        if ($usage -match '"input":(\d+)') { $totalInput = [int]$matches[1] }
        if ($usage -match '"output":(\d+)') { $totalOutput = [int]$matches[1] }
        if ($usage -match '"cacheRead":(\d+)') { $totalCache = [int]$matches[1] }
    }
    
    # Detect context window size from model
    $modelLine = $lines | Select-String -Pattern '"model":"[^"]*"' | Select-Object -Last 1
    if ($modelLine) {
        $model = $modelLine.Line
        if ($model -match 'opus-4') { $maxK = 1000 }
        elseif ($model -match 'sonnet-4\.[56]') { $maxK = 1000 }
        elseif ($model -match 'sonnet-4') { $maxK = 200 }
        elseif ($model -match 'haiku') { $maxK = 200 }
    }
    
    # Try to extract context from embedded status lines
    $contextLine = $lines | Select-String -Pattern 'Context:\s*~?\d+[Kk]/\d+\.?\d*[Mm]\s*\(\d+%\)' | Select-Object -Last 1
    if ($contextLine) {
        if ($contextLine.Line -match '(\d+)[Kk]/') {
            $currentK = [int]$matches[1]
        }
        if ($contextLine.Line -match '/[\d.]+[Mm]') {
            $contextLine.Line -match '/([\d.]+)[Mm]'
            $maxK = [int]([double]$matches[1] * 1000)
        }
        if ($contextLine.Line -match '\((\d+)%\)') {
            $pct = [int]$matches[1]
        }
    } else {
        # Calculate from tokens
        $currentTokens = $totalInput + $totalCache
        $currentK = [int]($currentTokens / 1000)
        $maxTokens = $maxK * 1000
        $pct = if ($maxTokens -gt 0) { [int](($currentTokens * 100) / $maxTokens) } else { 0 }
    }
    
    return @{
        current_k = $currentK
        max_k = $maxK
        pct = $pct
        compactions = $compactions
        session_id = $sessionId
    }
}

# ─── Determine pressure level ──────────────────────────────────
function Get-PressureLevel {
    param([int]$Pct, [int]$CurrentK)
    
    if ($Pct -ge $global:THRESHOLD_CRITICAL) { return "CRITICAL" }
    if ($Pct -ge $global:THRESHOLD_WARNING) { return "WARNING" }
    if ($CurrentK -ge $global:PLANNING_THRESHOLD_K) { return "PLANNING" }
    if ($Pct -ge $global:THRESHOLD_ADVISORY) { return "ADVISORY" }
    if ($Pct -ge $global:THRESHOLD_INFO) { return "INFO" }
    return "NOMINAL"
}

# ─── Get color for pressure level ──────────────────────────────
function Get-LevelColor {
    param([string]$Level)
    
    switch ($Level) {
        "CRITICAL" { return "Red" }
        "WARNING"  { return "DarkYellow" }
        "PLANNING" { return "Yellow" }
        "ADVISORY" { return "Yellow" }
        "INFO"     { return "Cyan" }
        "NOMINAL"  { return "Green" }
        default    { return "White" }
    }
}

# ─── Render pressure bar ──────────────────────────────────────
function Show-PressureBar {
    param([int]$Pct)
    
    $width = $global:BAR_WIDTH
    $filled = [int](($Pct * $width) / 100)
    if ($filled -gt $width) { $filled = $width }
    $empty = $width - $filled
    
    $level = Get-PressureLevel -Pct $Pct -CurrentK 0
    $color = Get-LevelColor -Level $level
    
    Write-Host "[" -NoNewline -ForegroundColor $color
    Write-Host ("█" * $filled) -NoNewline -ForegroundColor $color
    Write-Host ("░" * $empty) -NoNewline -ForegroundColor DarkGray
    Write-Host ("] {0,3}%" -f $Pct) -ForegroundColor $color
}

# ─── Send desktop notification ─────────────────────────────────
function Send-Notification {
    param([string]$Title, [string]$Message)
    
    if (-not $global:DESKTOP_NOTIFY) { return }
    
    # Try BurntToast first (best Windows notification)
    if (Get-Module -ListAvailable -Name BurntToast) {
        Import-Module BurntToast -ErrorAction SilentlyContinue
        New-BurntToastNotification -Text $Title, $Message -ErrorAction SilentlyContinue
        return
    }
    
    # Fallback to MessageBox
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show($Message, $Title, 0, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        # Silent fail
    }
}

# ─── Play alert sound ─────────────────────────────────────────
function Play-AlertSound {
    if (-not $global:SOUND_ON_COMPACT) { return }
    
    try {
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {
        # Silent fail
    }
}

# ─── Update growth tracking state ─────────────────────────────
function Update-GrowthState {
    param([int]$CurrentK, [int]$Pct, [string]$SessionId)
    
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $state = @{}
    if (Test-Path $StateFile) {
        $state = Get-Content $StateFile -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
        if (-not $state) { $state = @{} }
    }
    
    $prevSession = $state.session_id
    
    if ($prevSession -ne $SessionId) {
        # New session, reset state
        $state = @{
            session_id = $SessionId
            history = @(@{ ts = $now; k = $CurrentK; pct = $Pct })
            alerts_sent = @{}
            started = $now
        }
    } else {
        # Append to history, keep last N entries
        if (-not $state.history) { $state.history = @() }
        $state.history += @{ ts = $now; k = $CurrentK; pct = $Pct }
        if ($state.history.Count -gt $global:HISTORY_SIZE) {
            $state.history = $state.history[-$global:HISTORY_SIZE..-1]
        }
    }
    
    $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile
    return $state
}

# ─── Calculate growth rate ─────────────────────────────────────
function Get-GrowthRate {
    param($State)
    
    if (-not $State.history -or $State.history.Count -lt 2) {
        return 0
    }
    
    $first = $State.history[0]
    $last = $State.history[-1]
    
    $firstEpoch = [DateTimeOffset]::Parse($first.ts).ToUnixTimeSeconds()
    $lastEpoch = [DateTimeOffset]::Parse($last.ts).ToUnixTimeSeconds()
    
    $deltaSec = $lastEpoch - $firstEpoch
    if ($deltaSec -le 0) { return 0 }
    
    $deltaK = $last.k - $first.k
    $deltaMin = [int]($deltaSec / 60)
    if ($deltaMin -le 0) { $deltaMin = 1 }
    
    return [int]($deltaK / $deltaMin)
}
