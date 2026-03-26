#!/usr/bin/env bash
# Claude Code Context Pressure Widget - Live Terminal Monitor
# Run in a split pane alongside Claude Code for real-time context awareness.
#
# Usage: ./context-monitor.sh [--once] [--statusline]
#   --once        Print status once and exit (for scripting)
#   --statusline  Output compact single-line for Claude Code status line

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MODE="dashboard"
[[ "${1:-}" == "--once" ]] && MODE="once"
[[ "${1:-}" == "--statusline" ]] && MODE="statusline"

# ─── Preflight ─────────────────────────────────────────────────
if [[ -z "$SESSIONS_DIR" ]]; then
    echo -e "${RED}Error: Could not find Claude Code sessions directory.${RESET}"
    echo "Set CLAUDE_SESSIONS_DIR in config.sh or ensure Claude Code is installed."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Linux)${RESET}"
    exit 1
fi

# ─── Track alert state for this run ────────────────────────────
ALERT_STATE_FILE="/tmp/cc-widget-alert-state-$$"
: > "$ALERT_STATE_FILE"
trap "rm -f '$ALERT_STATE_FILE'" EXIT

# ─── Statusline mode ──────────────────────────────────────────
if [[ "$MODE" == "statusline" ]]; then
    session_file=$(find_active_session)
    if [[ -z "$session_file" ]]; then
        echo "🧠 No active session"
        exit 0
    fi
    stats=$(parse_session_context "$session_file")
    render_statusline "$stats"
    exit 0
fi

# ─── Main render loop ──────────────────────────────────────────
render_dashboard() {
    local session_file
    session_file=$(find_active_session)

    if [[ -z "$session_file" ]]; then
        echo -e "${DIM}No active Claude Code session found.${RESET}"
        echo -e "${DIM}Watching ${SESSIONS_DIR}...${RESET}"
        return
    fi

    # Parse session
    local stats
    stats=$(parse_session_context "$session_file")

    local current_k max_k pct compactions session_id model_display tier
    current_k=$(echo "$stats" | jq '.current_k')
    max_k=$(echo "$stats" | jq '.max_k')
    pct=$(echo "$stats" | jq '.pct')
    compactions=$(echo "$stats" | jq '.compactions')
    session_id=$(echo "$stats" | jq -r '.session_id')
    model_display=$(echo "$stats" | jq -r '.model_display')
    tier=$(echo "$stats" | jq -r '.tier')

    # Update growth state
    local state
    state=$(update_growth_state "$current_k" "$pct" "$session_id")

    # Calculate growth rate
    local growth_rate=0
    if [[ "$SHOW_GROWTH_RATE" == "true" ]]; then
        growth_rate=$(calc_growth_rate "$state")
    fi

    # Determine pressure level (model-aware)
    local level
    level=$(get_pressure_level "$pct" "$current_k" "$tier")
    local color
    color=$(get_level_color "$level")

    # Get effective thresholds for display
    local thresholds eff_warning eff_critical eff_planning_k
    thresholds=$(get_effective_thresholds "$tier")
    eff_warning=$(echo "$thresholds" | cut -d'|' -f1)
    eff_critical=$(echo "$thresholds" | cut -d'|' -f2)
    eff_planning_k=$(echo "$thresholds" | cut -d'|' -f3)

    # Format context sizes
    local ctx_current ctx_max
    ctx_current=$(format_context_size "$current_k")
    ctx_max=$(format_max_context "$max_k")

    # ─── Render ────────────────────────────────────────────────
    echo -e "${BOLD}${WHITE}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${WHITE}║  🧠 Claude Code Context Pressure Monitor        ║${RESET}"
    echo -e "${BOLD}${WHITE}╠══════════════════════════════════════════════════╣${RESET}"
    echo ""

    # Model info
    if [[ "$SHOW_MODEL_NAME" == "true" ]]; then
        local model_color="$CYAN"
        echo -e "  ${WHITE}Model:${RESET}       ${model_color}${model_display}${RESET} ${DIM}(${ctx_max} context)${RESET}"
        echo ""
    fi

    # Pressure bar (smooth gradient)
    echo -n "  "
    render_pressure_bar "$pct"
    echo ""
    echo ""

    # Stats
    echo -e "  ${WHITE}Context:${RESET}     ${ctx_current} / ${ctx_max}"
    echo -e "  ${WHITE}Compactions:${RESET} ${compactions}"
    echo -e "  ${WHITE}Status:${RESET}      ${color}${level}${RESET}"

    # Growth rate
    if [[ "$SHOW_GROWTH_RATE" == "true" && $growth_rate -gt 0 ]]; then
        echo -e "  ${WHITE}Growth:${RESET}      ~${growth_rate}K/min"

        if [[ "$SHOW_TURNS_ESTIMATE" == "true" && $growth_rate -gt 0 ]]; then
            local remaining_k=$(( max_k - current_k ))
            local minutes_remaining=$(( remaining_k / growth_rate ))
            local est_turns=$(( minutes_remaining / 2 ))  # ~2 min per turn average
            [[ $est_turns -lt 0 ]] && est_turns=0
            echo -e "  ${WHITE}Est. turns:${RESET}  ~${est_turns} remaining"
        fi
    fi

    # ─── Contextual warnings ──────────────────────────────────
    if [[ "$level" == "CRITICAL" ]]; then
        echo ""
        echo -e "  ${RED}${BOLD}┌────────────────────────────────────────────┐${RESET}"
        echo -e "  ${RED}${BOLD}│  🔴 CRITICAL: Context at ${pct}%               │${RESET}"
        echo -e "  ${RED}${BOLD}│                                            │${RESET}"
        echo -e "  ${RED}${BOLD}│  Compaction is imminent. To preserve work: │${RESET}"
        echo -e "  ${RED}${BOLD}│  1. Save key decisions to CLAUDE.md        │${RESET}"
        echo -e "  ${RED}${BOLD}│  2. Commit any in-progress changes         │${RESET}"
        echo -e "  ${RED}${BOLD}│  3. Start a fresh session: /clear          │${RESET}"
        echo -e "  ${RED}${BOLD}└────────────────────────────────────────────┘${RESET}"
    elif [[ "$level" == "WARNING" ]]; then
        echo ""
        echo -e "  ${ORANGE}${BOLD}⚠ WARNING: Context at ${pct}% — approaching compaction${RESET}"
        echo -e "  ${ORANGE}  Wrap up current task, then rotate session.${RESET}"
        echo -e "  ${ORANGE}  Tip: Save important context to CLAUDE.md before rotating.${RESET}"
    elif [[ $current_k -ge $eff_planning_k ]]; then
        echo ""
        echo -e "  ${YELLOW}⚠ Past ${eff_planning_k}K planning threshold${RESET}"
        echo -e "  ${YELLOW}  Consider rotating session after current task${RESET}"
    fi

    # Compaction warnings
    if [[ $compactions -ge 2 ]]; then
        echo ""
        echo -e "  ${RED}${BLINK}🚨 EMERGENCY: ${compactions} compactions — context severely degraded${RESET}"
        echo -e "  ${RED}${BOLD}   Stop complex work. Save state and start fresh NOW.${RESET}"
        echo -e "  ${RED}   Steps: 1) /commit  2) Note key context in CLAUDE.md  3) /clear${RESET}"
    elif [[ $compactions -ge 1 ]]; then
        echo ""
        echo -e "  ${RED}🔴 COMPACTED: Fidelity loss detected (${compactions}x)${RESET}"
        echo -e "  ${RED}   Earlier context may be distorted. Plan rotation soon.${RESET}"
    fi

    echo ""
    echo -e "  ${DIM}Session: ${session_id:0:16}...${RESET}"
    echo -e "  ${DIM}Updated: $(date '+%H:%M:%S')${RESET}"
    if [[ "$tier" == "200k" ]]; then
        echo -e "  ${DIM}Thresholds: warn=${eff_warning}% crit=${eff_critical}% plan=${eff_planning_k}K (200K model)${RESET}"
    fi
    echo -e "${BOLD}${WHITE}╚══════════════════════════════════════════════════╝${RESET}"

    # ─── Alerts (desktop notifications) ────────────────────────
    check_and_alert "$level" "$pct" "$current_k" "$compactions"
}

check_and_alert() {
    local level=$1 pct=$2 current_k=$3 compactions=$4

    if grep -q "^${level}$" "$ALERT_STATE_FILE" 2>/dev/null; then
        return
    fi

    case "$level" in
        CRITICAL)
            send_notification "🔴 Context CRITICAL (${pct}%)" "Compaction imminent at ${current_k}K. Save work and rotate session."
            play_alert_sound
            echo "$level" >> "$ALERT_STATE_FILE"
            ;;
        WARNING)
            send_notification "🟠 Context WARNING (${pct}%)" "Context at ${current_k}K. Compaction approaching — plan rotation."
            echo "$level" >> "$ALERT_STATE_FILE"
            ;;
        PLANNING)
            send_notification "⚠️ Planning Threshold" "Context at ${current_k}K. Consider session rotation."
            echo "$level" >> "$ALERT_STATE_FILE"
            ;;
        ADVISORY)
            send_notification "Context Advisory (${pct}%)" "Context at ${current_k}K."
            echo "$level" >> "$ALERT_STATE_FILE"
            ;;
    esac

    if [[ $compactions -ge 1 ]] && ! grep -q "^COMPACT$" "$ALERT_STATE_FILE" 2>/dev/null; then
        send_notification "🚨 Compaction Detected" "Compaction #${compactions}. Context quality degraded. Save important context and consider rotating."
        play_alert_sound
        echo "COMPACT" >> "$ALERT_STATE_FILE"
    fi
}

# ─── Run ───────────────────────────────────────────────────────
if [[ "$MODE" == "once" ]]; then
    render_dashboard
    exit 0
fi

# Clear screen and run loop
while true; do
    clear
    render_dashboard
    sleep "$REFRESH_INTERVAL"
done
