# Claude Code Context Pressure Widget - Live Terminal Monitor (Windows)
# Run in a split pane alongside Claude Code for real-time context awareness.
#
# Usage: .\context-monitor.ps1 [-Once]
#   -Once    Print status once and exit (for scripting)

param([switch]$Once)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\lib.ps1"

# ─── Preflight ─────────────────────────────────────────────────
if (-not $global:SESSIONS_DIR) {
    Write-Host "Error: Could not find Claude Code sessions directory." -ForegroundColor Red
    Write-Host "Set `$CLAUDE_SESSIONS_DIR in config.ps1 or ensure Claude Code is installed."
    exit 1
}

# ─── Track alert state for this run ────────────────────────────
$AlertedThresholds = @{}

# ─── Main render function ──────────────────────────────────────
function Show-Dashboard {
    $sessionFile = Find-ActiveSession
    
    if (-not $sessionFile) {
        Write-Host "No active Claude Code session found." -ForegroundColor DarkGray
        Write-Host "Watching $($global:SESSIONS_DIR)..." -ForegroundColor DarkGray
        return
    }
    
    # Parse session
    $stats = Get-SessionContext -SessionFile $sessionFile
    
    $currentK = $stats.current_k
    $maxK = $stats.max_k
    $pct = $stats.pct
    $compactions = $stats.compactions
    $sessionId = $stats.session_id
    
    # Update growth state
    $state = Update-GrowthState -CurrentK $currentK -Pct $pct -SessionId $sessionId
    
    # Calculate growth rate
    $growthRate = 0
    if ($global:SHOW_GROWTH_RATE) {
        $growthRate = Get-GrowthRate -State $state
    }
    
    # Determine pressure level
    $level = Get-PressureLevel -Pct $pct -CurrentK $currentK
    $color = Get-LevelColor -Level $level
    
    # ─── Render ────────────────────────────────────────────────
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor White
    Write-Host "║  🧠 Claude Code Context Pressure Monitor        ║" -ForegroundColor White
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor White
    Write-Host ""
    
    # Pressure bar
    Write-Host "  " -NoNewline
    Show-PressureBar -Pct $pct
    Write-Host ""
    
    # Stats
    Write-Host "  Context:     " -NoNewline -ForegroundColor White
    Write-Host "$currentK`K / $maxK`K"
    Write-Host "  Compactions: " -NoNewline -ForegroundColor White
    Write-Host $compactions
    Write-Host "  Status:      " -NoNewline -ForegroundColor White
    Write-Host $level -ForegroundColor $color
    
    # Growth rate
    if ($global:SHOW_GROWTH_RATE -and $growthRate -gt 0) {
        Write-Host "  Growth:      " -NoNewline -ForegroundColor White
        Write-Host "~$growthRate`K/min"
        
        if ($global:SHOW_TURNS_ESTIMATE -and $growthRate -gt 0) {
            $remainingK = $maxK - $currentK
            $minutesRemaining = [int]($remainingK / $growthRate)
            $estTurns = [int]($minutesRemaining / 2)  # ~2 min per turn average
            if ($estTurns -lt 0) { $estTurns = 0 }
            Write-Host "  Est. turns:  " -NoNewline -ForegroundColor White
            Write-Host "~$estTurns remaining"
        }
    }
    
    # Planning threshold indicator
    if ($currentK -ge $global:PLANNING_THRESHOLD_K) {
        Write-Host ""
        Write-Host "  ⚠ Past $($global:PLANNING_THRESHOLD_K)K planning threshold" -ForegroundColor Yellow
        Write-Host "    Consider rotating session after current task" -ForegroundColor Yellow
    }
    
    # Compaction warnings
    if ($compactions -ge 2) {
        Write-Host ""
        Write-Host "  🚨 EMERGENCY: $compactions compactions" -ForegroundColor Red
        Write-Host "     Context severely degraded. Rotate NOW." -ForegroundColor Red
    } elseif ($compactions -ge 1) {
        Write-Host ""
        Write-Host "  🔴 DANGER: $compactions compaction(s)" -ForegroundColor Red
        Write-Host "     Fidelity loss detected. Plan rotation." -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "  Session: $($sessionId.Substring(0, [Math]::Min(16, $sessionId.Length)))..." -ForegroundColor DarkGray
    Write-Host "  Updated: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor White
    
    # ─── Alerts (desktop notifications) ────────────────────────
    Test-AndAlert -Level $level -Pct $pct -CurrentK $currentK -Compactions $compactions
}

function Test-AndAlert {
    param([string]$Level, [int]$Pct, [int]$CurrentK, [int]$Compactions)
    
    # Only alert once per level per session
    if ($script:AlertedThresholds[$Level]) { return }
    
    switch ($Level) {
        "CRITICAL" {
            Send-Notification -Title "🔴 Context CRITICAL" -Message "Context at $Pct% ($CurrentK`K). Rotate session soon."
            $script:AlertedThresholds[$Level] = $true
        }
        "WARNING" {
            Send-Notification -Title "🟠 Context WARNING" -Message "Context at $Pct% ($CurrentK`K). Compaction approaching."
            $script:AlertedThresholds[$Level] = $true
        }
        "PLANNING" {
            Send-Notification -Title "⚠️ Planning Threshold" -Message "Context at $CurrentK`K. Consider session rotation."
            $script:AlertedThresholds[$Level] = $true
        }
        "ADVISORY" {
            Send-Notification -Title "Context Advisory" -Message "Context at $Pct% ($CurrentK`K)."
            $script:AlertedThresholds[$Level] = $true
        }
    }
    
    if ($Compactions -ge 1 -and -not $script:AlertedThresholds["COMPACT"]) {
        Send-Notification -Title "🔴 Compaction Detected" -Message "Compaction #$Compactions. Context quality degraded."
        Play-AlertSound
        $script:AlertedThresholds["COMPACT"] = $true
    }
}

# ─── Run ───────────────────────────────────────────────────────
if ($Once) {
    Show-Dashboard
    exit 0
}

# Clear screen and run loop
while ($true) {
    Clear-Host
    Show-Dashboard
    Start-Sleep -Seconds $global:REFRESH_INTERVAL
}
