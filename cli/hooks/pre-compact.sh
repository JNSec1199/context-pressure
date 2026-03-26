#!/usr/bin/env bash
# Claude Code Hook: PreCompact
# Fires before context compaction. Logs the event, sends desktop notification,
# and plays alert sound. This is your early warning that context is being compressed.
#
# Install: Add to ~/.claude/settings.json under hooks.PreCompact
# Input: JSON on stdin with session context

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# Read hook input from stdin
INPUT=$(cat)

# Extract session info
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Log compaction event
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
echo "[$TIMESTAMP] PRE_COMPACT session=$SESSION_ID" >> "$LOG_DIR/compaction.log"

# Count previous compactions in this session
PREV_COUNT=$(grep -c "session=$SESSION_ID" "$LOG_DIR/compaction.log" 2>/dev/null || echo 0)

# Send notification
if [[ "$DESKTOP_NOTIFY" == "true" ]]; then
    MSG="Compaction #${PREV_COUNT} starting. Context is being compressed. Fidelity will decrease."
    
    if command -v osascript &>/dev/null; then
        osascript -e "display notification \"$MSG\" with title \"🔴 Claude Code Compacting\"" 2>/dev/null
    elif command -v notify-send &>/dev/null; then
        notify-send "🔴 Claude Code Compacting" "$MSG" --urgency=critical 2>/dev/null
    fi
fi

# Play alert sound
if [[ "$SOUND_ON_COMPACT" == "true" ]]; then
    if command -v afplay &>/dev/null; then
        afplay /System/Library/Sounds/Sosumi.aiff &>/dev/null &
    elif command -v paplay &>/dev/null; then
        paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga &>/dev/null &
    fi
fi

# Exit 0 to allow compaction to proceed
exit 0
