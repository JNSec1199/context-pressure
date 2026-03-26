# Claude Code Context Pressure Widget - Configuration (Windows)
# Edit these values to match your workflow.

# ─── Alert Thresholds (percentage of context window) ───────────
$THRESHOLD_INFO = 40
$THRESHOLD_ADVISORY = 60
$THRESHOLD_WARNING = 75
$THRESHOLD_CRITICAL = 85

# ─── Absolute Planning Threshold (tokens in thousands) ─────────
# When context exceeds this, recommend session rotation.
$PLANNING_THRESHOLD_K = 250

# ─── Monitor Settings ──────────────────────────────────────────
$REFRESH_INTERVAL = 10       # Seconds between dashboard refreshes
$HISTORY_SIZE = 30           # Number of data points for growth tracking

# ─── Notifications ─────────────────────────────────────────────
$DESKTOP_NOTIFY = $true      # Send desktop notifications on threshold crossings
$SOUND_ON_COMPACT = $true    # Play sound when compaction occurs

# ─── Display ───────────────────────────────────────────────────
$BAR_WIDTH = 40              # Width of the pressure bar in characters
$SHOW_GROWTH_RATE = $true    # Show estimated growth rate
$SHOW_TURNS_ESTIMATE = $true # Show estimated turns remaining

# ─── Claude Code Session Path ──────────────────────────────────
# Override if your Claude Code sessions are in a non-standard location.
# Leave empty for auto-detection.
$CLAUDE_SESSIONS_DIR = ""

# Auto-detect session directory
function Get-SessionsDirectory {
    if ($CLAUDE_SESSIONS_DIR) {
        return $CLAUDE_SESSIONS_DIR
    }
    
    # Standard Windows locations
    $candidates = @(
        "$env:APPDATA\claude-code\sessions",
        "$env:USERPROFILE\.claude\sessions",
        "$env:LOCALAPPDATA\claude-code\sessions"
    )
    
    foreach ($dir in $candidates) {
        if (Test-Path $dir) {
            return $dir
        }
    }
    
    return $null
}

$script:SESSIONS_DIR = Get-SessionsDirectory

# Export as global for hooks
$global:SESSIONS_DIR = $script:SESSIONS_DIR
$global:THRESHOLD_INFO = $THRESHOLD_INFO
$global:THRESHOLD_ADVISORY = $THRESHOLD_ADVISORY
$global:THRESHOLD_WARNING = $THRESHOLD_WARNING
$global:THRESHOLD_CRITICAL = $THRESHOLD_CRITICAL
$global:PLANNING_THRESHOLD_K = $PLANNING_THRESHOLD_K
$global:DESKTOP_NOTIFY = $DESKTOP_NOTIFY
$global:SOUND_ON_COMPACT = $SOUND_ON_COMPACT
$global:BAR_WIDTH = $BAR_WIDTH
$global:SHOW_GROWTH_RATE = $SHOW_GROWTH_RATE
$global:SHOW_TURNS_ESTIMATE = $SHOW_TURNS_ESTIMATE
$global:REFRESH_INTERVAL = $REFRESH_INTERVAL
$global:HISTORY_SIZE = $HISTORY_SIZE
