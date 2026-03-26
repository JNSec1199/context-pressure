#!/usr/bin/env bash
# Claude Code Context Pressure Widget - Status Line Script
# Reads session data from stdin (provided by Claude Code's statusLine feature)
# and outputs a compact context pressure indicator.
#
# Install: Add to ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "/path/to/statusline.sh" }
#
# Or use the installer: ./install.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Read JSON from stdin (Claude Code provides this automatically)
INPUT=$(cat)

# ─── Extract data from Claude Code's native status line JSON ───
MODEL_NAME=$(echo "$INPUT" | jq -r '.model.display_name // "Unknown"' 2>/dev/null)
MODEL_ID=$(echo "$INPUT" | jq -r '.model.id // ""' 2>/dev/null)
PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
WINDOW_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)
TOTAL_INPUT=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
TOTAL_OUTPUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)

# Sanitize
[[ -z "$PCT" || "$PCT" == "null" ]] && PCT=0
[[ -z "$WINDOW_SIZE" || "$WINDOW_SIZE" == "null" ]] && WINDOW_SIZE=200000

# ─── Determine model tier ─────────────────────────────────────
TIER="200k"
MAX_K=$(( WINDOW_SIZE / 1000 ))
if [[ $WINDOW_SIZE -ge 500000 ]]; then
    TIER="1m"
fi

CURRENT_K=$(( TOTAL_INPUT / 1000 ))

# ─── Get effective thresholds ─────────────────────────────────
if [[ "$TIER" == "200k" ]]; then
    EFF_WARNING=$THRESHOLD_WARNING_200K
    EFF_CRITICAL=$THRESHOLD_CRITICAL_200K
else
    EFF_WARNING=$THRESHOLD_WARNING
    EFF_CRITICAL=$THRESHOLD_CRITICAL
fi

# ─── Build mini pressure bar (10 chars) ───────────────────────
BAR_W=10
FILLED=$(( PCT * BAR_W / 100 ))
[[ $FILLED -gt $BAR_W ]] && FILLED=$BAR_W
EMPTY=$(( BAR_W - FILLED ))

BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

# ─── Status icon based on pressure level ──────────────────────
ICON="🟢"
STATUS=""
if [[ $PCT -ge $EFF_CRITICAL ]]; then
    ICON="🔴"
    STATUS=" SAVE+ROTATE"
elif [[ $PCT -ge $EFF_WARNING ]]; then
    ICON="🟠"
    STATUS=" wrap up"
elif [[ $PCT -ge $THRESHOLD_ADVISORY ]]; then
    ICON="🟡"
elif [[ $PCT -ge $THRESHOLD_INFO ]]; then
    ICON="🔵"
fi

# ─── Format context size ──────────────────────────────────────
if [[ $CURRENT_K -ge 1000 ]]; then
    CTX_DISPLAY="$(( CURRENT_K / 1000 )).$(( (CURRENT_K % 1000) / 100 ))M"
else
    CTX_DISPLAY="${CURRENT_K}K"
fi

if [[ $MAX_K -ge 1000 ]]; then
    MAX_DISPLAY="$(( MAX_K / 1000 ))M"
else
    MAX_DISPLAY="${MAX_K}K"
fi

# ─── Output ───────────────────────────────────────────────────
echo "${ICON} ${MODEL_NAME} ${BAR} ${PCT}% (${CTX_DISPLAY}/${MAX_DISPLAY})${STATUS}"
