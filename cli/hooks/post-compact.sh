#!/usr/bin/env bash
# Claude Code Hook: PostCompact
# Fires after context compaction completes. Logs the event, updates state,
# and sends a notification with the compaction count.
#
# Install: Add to ~/.claude/settings.json under hooks.PostCompact
# Input: JSON on stdin with session context and compaction details

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# Read hook input from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Log
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
echo "[$TIMESTAMP] POST_COMPACT session=$SESSION_ID" >> "$LOG_DIR/compaction.log"

# Count total compactions for this session
COMPACT_COUNT=$(grep "session=$SESSION_ID" "$LOG_DIR/compaction.log" 2>/dev/null | grep -c "PRE_COMPACT" || echo 0)

# Severity-based notification
if [[ "$DESKTOP_NOTIFY" == "true" ]]; then
    if [[ $COMPACT_COUNT -ge 2 ]]; then
        MSG="🚨 EMERGENCY: ${COMPACT_COUNT} compactions. Context severely degraded. Rotate session NOW."
        URGENCY="critical"
    else
        MSG="Compaction complete (total: ${COMPACT_COUNT}). Context quality reduced. Consider rotation for accuracy-sensitive work."
        URGENCY="normal"
    fi
    
    if command -v osascript &>/dev/null; then
        osascript -e "display notification \"$MSG\" with title \"Claude Code Compacted\"" 2>/dev/null
    elif command -v notify-send &>/dev/null; then
        notify-send "Claude Code Compacted" "$MSG" --urgency=$URGENCY 2>/dev/null
    fi
fi

# Write compaction count to state file for the monitor to pick up
STATE_FILE="/tmp/cc-context-widget-state.json"
if [[ -f "$STATE_FILE" ]] && command -v jq &>/dev/null; then
    jq --argjson count "$COMPACT_COUNT" '.compactions = $count' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

exit 0
