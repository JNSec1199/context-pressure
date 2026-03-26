#!/usr/bin/env bash
# Claude Code Hook: Stop
# Fires when Claude finishes a turn. Checks context pressure and notifies
# if approaching thresholds. Lightweight: exits quickly when everything is nominal.
#
# Install: Add to ~/.claude/settings.json under hooks.Stop
# Input: JSON on stdin with session context

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# Find and parse the active session
SESSION_FILE=$(find_active_session)
if [[ -z "$SESSION_FILE" ]]; then
    exit 0
fi

STATS=$(parse_session_context "$SESSION_FILE")
CURRENT_K=$(echo "$STATS" | jq '.current_k')
MAX_K=$(echo "$STATS" | jq '.max_k')
PCT=$(echo "$STATS" | jq '.pct')
COMPACTIONS=$(echo "$STATS" | jq '.compactions')
TIER=$(echo "$STATS" | jq -r '.tier')
MODEL_DISPLAY=$(echo "$STATS" | jq -r '.model_display')

# Get effective thresholds for this model
THRESHOLDS=$(get_effective_thresholds "$TIER")
EFF_PLANNING_K=$(echo "$THRESHOLDS" | cut -d'|' -f3)

# Quick exit if nominal
if [[ $PCT -lt $THRESHOLD_INFO && $CURRENT_K -lt $EFF_PLANNING_K ]]; then
    exit 0
fi

LEVEL=$(get_pressure_level "$PCT" "$CURRENT_K" "$TIER")

# Check if we already alerted at this level (avoid spam)
ALERT_STATE_FILE="/tmp/cc-stop-alert-state"
LAST_ALERT=$(cat "$ALERT_STATE_FILE" 2>/dev/null || echo "NONE")

if [[ "$LAST_ALERT" == "${LEVEL}_${SESSION_ID}" ]]; then
    exit 0
fi

# Send notification for WARNING and above
case "$LEVEL" in
    CRITICAL)
        send_notification "🔴 Context CRITICAL (${PCT}%)" "${MODEL_DISPLAY}: ${CURRENT_K}K/${MAX_K}K. Save work to CLAUDE.md and rotate session."
        play_alert_sound
        echo "${LEVEL}_${SESSION_ID}" > "$ALERT_STATE_FILE"
        ;;
    WARNING)
        send_notification "🟠 Context WARNING (${PCT}%)" "${MODEL_DISPLAY}: ${CURRENT_K}K/${MAX_K}K. Compaction approaching — plan rotation."
        echo "${LEVEL}_${SESSION_ID}" > "$ALERT_STATE_FILE"
        ;;
    PLANNING)
        send_notification "⚠️ Planning Threshold" "${MODEL_DISPLAY}: Context at ${CURRENT_K}K. Consider session rotation."
        echo "${LEVEL}_${SESSION_ID}" > "$ALERT_STATE_FILE"
        ;;
    ADVISORY)
        send_notification "Context Advisory (${PCT}%)" "${MODEL_DISPLAY}: ${CURRENT_K}K/${MAX_K}K."
        echo "${LEVEL}_${SESSION_ID}" > "$ALERT_STATE_FILE"
        ;;
esac

exit 0
