# Claude Code Hook: Stop (Windows)
# Fires when Claude finishes a turn. Checks context pressure and notifies
# if approaching thresholds. Lightweight: exits quickly when everything is nominal.
#
# Install: Add to Claude Code settings under hooks.Stop
# Input: JSON on stdin with session context

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$ScriptDir\lib.ps1"

# Read hook input from stdin
$input = $Input | Out-String | ConvertFrom-Json

$sessionId = if ($input.session_id) { $input.session_id } else { "unknown" }

# Find and parse the active session
$sessionFile = Find-ActiveSession
if (-not $sessionFile) {
    exit 0
}

$stats = Get-SessionContext -SessionFile $sessionFile
$currentK = $stats.current_k
$maxK = $stats.max_k
$pct = $stats.pct
$compactions = $stats.compactions

# Quick exit if nominal
if ($pct -lt $global:THRESHOLD_INFO -and $currentK -lt $global:PLANNING_THRESHOLD_K) {
    exit 0
}

$level = Get-PressureLevel -Pct $pct -CurrentK $currentK

# Check if we already alerted at this level (avoid spam)
$alertStateFile = "$env:TEMP\cc-stop-alert-state"
$lastAlert = if (Test-Path $alertStateFile) { Get-Content $alertStateFile -Raw } else { "NONE" }

if ($lastAlert -eq "${level}_${sessionId}") {
    exit 0
}

# Send notification for WARNING and above
switch ($level) {
    "CRITICAL" {
        Send-Notification -Title "🔴 Context CRITICAL ($pct%)" -Message "At $currentK`K/$maxK`K. Rotate session soon."
        Set-Content -Path $alertStateFile -Value "${level}_${sessionId}"
    }
    "WARNING" {
        Send-Notification -Title "🟠 Context WARNING ($pct%)" -Message "At $currentK`K/$maxK`K. Compaction approaching."
        Set-Content -Path $alertStateFile -Value "${level}_${sessionId}"
    }
    "PLANNING" {
        Send-Notification -Title "⚠️ Planning Threshold" -Message "Context at $currentK`K. Consider session rotation."
        Set-Content -Path $alertStateFile -Value "${level}_${sessionId}"
    }
    "ADVISORY" {
        Send-Notification -Title "Context Advisory ($pct%)" -Message "At $currentK`K/$maxK`K."
        Set-Content -Path $alertStateFile -Value "${level}_${sessionId}"
    }
}

exit 0
