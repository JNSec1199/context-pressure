# Claude Code Hook: PreCompact (Windows)
# Fires before context compaction. Logs the event, sends desktop notification,
# and plays alert sound. This is your early warning that context is being compressed.
#
# Install: Add to Claude Code settings under hooks.PreCompact
# Input: JSON on stdin with session context

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$ScriptDir\config.ps1"

# Read hook input from stdin
$input = $Input | Out-String | ConvertFrom-Json

# Extract session info
$sessionId = if ($input.session_id) { $input.session_id } else { "unknown" }
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Log compaction event
$logDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$logFile = Join-Path $logDir "compaction.log"
Add-Content -Path $logFile -Value "[$timestamp] PRE_COMPACT session=$sessionId"

# Count previous compactions in this session
$prevCount = 0
if (Test-Path $logFile) {
    $prevCount = (Select-String -Path $logFile -Pattern "session=$sessionId" -AllMatches).Matches.Count
}

# Send notification
if ($global:DESKTOP_NOTIFY) {
    $msg = "Compaction #$prevCount starting. Context is being compressed. Fidelity will decrease."
    
    # Try BurntToast
    if (Get-Module -ListAvailable -Name BurntToast) {
        Import-Module BurntToast -ErrorAction SilentlyContinue
        New-BurntToastNotification -Text "🔴 Claude Code Compacting", $msg -ErrorAction SilentlyContinue
    } else {
        # Fallback to MessageBox
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show($msg, "🔴 Claude Code Compacting", 0, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } catch {
            # Silent fail
        }
    }
}

# Play alert sound
if ($global:SOUND_ON_COMPACT) {
    try {
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {
        # Silent fail
    }
}

# Exit 0 to allow compaction to proceed
exit 0
