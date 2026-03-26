#!/usr/bin/env bash
# Claude Code Context Pressure Widget - Configuration
# Edit these values to match your workflow.

# ─── Alert Thresholds (percentage of context window) ───────────
# These are the DEFAULT thresholds. Model-specific overrides below.
THRESHOLD_INFO=40
THRESHOLD_ADVISORY=60
THRESHOLD_WARNING=75
THRESHOLD_CRITICAL=85

# ─── Color Gradient Inflection Point ──────────────────────────
# The pressure bar starts changing from green at this percentage.
# Below this = solid green. Above this = gradient toward red.
COLOR_GRADIENT_START=50

# ─── Absolute Planning Threshold (tokens in thousands) ─────────
# When context exceeds this, recommend session rotation.
PLANNING_THRESHOLD_K=250

# ─── Model-Specific Overrides ─────────────────────────────────
# 200K models hit compaction much faster — warn earlier.
# These override the defaults above when a 200K model is detected.
THRESHOLD_WARNING_200K=65
THRESHOLD_CRITICAL_200K=78
PLANNING_THRESHOLD_K_200K=120

# ─── Monitor Settings ──────────────────────────────────────────
REFRESH_INTERVAL=10       # Seconds between dashboard refreshes
HISTORY_SIZE=30           # Number of data points for growth tracking

# ─── Notifications ─────────────────────────────────────────────
DESKTOP_NOTIFY=true       # Send desktop notifications on threshold crossings
SOUND_ON_COMPACT=true     # Play sound when compaction occurs

# ─── Display ───────────────────────────────────────────────────
BAR_WIDTH=40              # Width of the pressure bar in characters
SHOW_GROWTH_RATE=true     # Show estimated growth rate
SHOW_TURNS_ESTIMATE=true  # Show estimated turns remaining
SHOW_MODEL_NAME=true      # Show detected model name in dashboard

# ─── Claude Code Session Path ──────────────────────────────────
# Override if your Claude Code sessions are in a non-standard location.
# Leave empty for auto-detection.
CLAUDE_SESSIONS_DIR=""

# Auto-detect session directory
_detect_sessions_dir() {
    if [[ -n "$CLAUDE_SESSIONS_DIR" ]]; then
        echo "$CLAUDE_SESSIONS_DIR"
        return
    fi

    # Standard locations
    local candidates=(
        "$HOME/.claude/projects"
        "$HOME/.config/claude-code/sessions"
        "$HOME/Library/Application Support/claude-code/sessions"
    )

    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return
        fi
    done

    echo ""
}

SESSIONS_DIR="$(_detect_sessions_dir)"
