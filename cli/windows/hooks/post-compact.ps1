# Claude Code Hook: PostCompact (Windows)
# Fires after context compaction completes. Logs the event, updates state,
# and sends a notification with the compaction count.
#
# Install: Add to Claude Code settings under hooks.PostCompact
# Input: JSON on stdin with session context and compaction details

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$ScriptDir\config.ps1"

# Read hook input from stdin
$input = $Input | Out-String | ConvertFrom-Json

$sessionId = if ($input.session_id) { $input.session_id } else { "unknown" }
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Log
$logDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$logFile = Join-Path $logDir "compaction.log"
Add-Content -Path $logFile -Value "[$timestamp] POST_COMPACT session=$sessionId"

# Count total compactions for this session
$compactCount = 0
if (Test-Path $logFile) {
    $compactCount = (Select-String -Path $logFile -Pattern "session=$sessionId.*PRE_COMPACT" -AllMatches).Matches.Count
}

# Severity-based notification
if ($global:DESKTOP_NOTIFY) {
    if ($compactCount -ge 2) {
        $msg = "🚨 EMERGENCY: $compactCount compactions. Context severely degraded. Rotate session NOW."
        $urgency = "critical"
    } else {
        $msg = "Compaction complete (total: $compactCount). Context quality reduced. Consider rotation for accuracy-sensitive work."
        $urgency = "normal"
    }
    
    # Try BurntToast
    if (Get-Module -ListAvailable -Name BurntToast) {
        Import-Module BurntToast -ErrorAction SilentlyContinue
        New-BurntToastNotification -Text "Claude Code Compacted", $msg -ErrorAction SilentlyContinue
    } else {
        # Fallback to MessageBox
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $icon = if ($urgency -eq "critical") { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
            [System.Windows.Forms.MessageBox]::Show($msg, "Claude Code Compacted", 0, $icon) | Out-Null
        } catch {
            # Silent fail
        }
    }
}

# Write compaction count to state file for the monitor to pick up
$stateFile = "$env:TEMP\cc-context-widget-state.json"
if (Test-Path $stateFile) {
    try {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json -AsHashtable
        $state.compactions = $compactCount
        $state | ConvertTo-Json -Depth 10 | Set-Content $stateFile
    } catch {
        # Silent fail
    }
}

exit 0
