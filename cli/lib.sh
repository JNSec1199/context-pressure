#!/usr/bin/env bash
# Claude Code Context Pressure Widget - Shared library functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

STATE_FILE="/tmp/cc-context-widget-state.json"

# ─── Color codes ───────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;208m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'
BLINK='\033[5m'

# ─── Model definitions ────────────────────────────────────────
# Maps model pattern → display name, context window K, tier (1m or 200k)
declare -A MODEL_DB 2>/dev/null || true  # bash 3.2 fallback below

get_model_info() {
    local model_str="$1"
    local display_name="Unknown" max_k=200 tier="200k"

    if [[ -z "$model_str" ]]; then
        echo "${display_name}|${max_k}|${tier}"
        return
    fi

    # Normalize: lowercase for matching
    local lc
    lc=$(echo "$model_str" | tr '[:upper:]' '[:lower:]')

    if [[ "$lc" == *"opus-4-6"* || "$lc" == *"opus-4.6"* ]]; then
        display_name="Opus 4.6" max_k=1000 tier="1m"
    elif [[ "$lc" == *"opus-4"* || "$lc" == *"opus4"* ]]; then
        display_name="Opus 4" max_k=1000 tier="1m"
    elif [[ "$lc" == *"sonnet-4-6"* || "$lc" == *"sonnet-4.6"* ]]; then
        display_name="Sonnet 4.6" max_k=1000 tier="1m"
    elif [[ "$lc" == *"sonnet-4-5"* || "$lc" == *"sonnet-4.5"* ]]; then
        display_name="Sonnet 4.5" max_k=1000 tier="1m"
    elif [[ "$lc" == *"sonnet-4"* || "$lc" == *"sonnet4"* ]]; then
        display_name="Sonnet 4" max_k=200 tier="200k"
    elif [[ "$lc" == *"haiku"* ]]; then
        display_name="Haiku 4.5" max_k=200 tier="200k"
    elif [[ "$lc" == *"opus"* ]]; then
        display_name="Opus" max_k=1000 tier="1m"
    elif [[ "$lc" == *"sonnet"* ]]; then
        display_name="Sonnet" max_k=200 tier="200k"
    fi

    echo "${display_name}|${max_k}|${tier}"
}

# ─── Get effective thresholds for a model tier ─────────────────
get_effective_thresholds() {
    local tier="$1"
    if [[ "$tier" == "200k" ]]; then
        echo "${THRESHOLD_WARNING_200K}|${THRESHOLD_CRITICAL_200K}|${PLANNING_THRESHOLD_K_200K}"
    else
        echo "${THRESHOLD_WARNING}|${THRESHOLD_CRITICAL}|${PLANNING_THRESHOLD_K}"
    fi
}

# ─── Find active Claude Code session ──────────────────────────
find_active_session() {
    if [[ -z "$SESSIONS_DIR" || ! -d "$SESSIONS_DIR" ]]; then
        echo ""
        return
    fi

    # Find the most recently modified .jsonl session file
    local latest
    if [[ "$(uname)" == "Darwin" ]]; then
        latest=$(find "$SESSIONS_DIR" -name "*.jsonl" -type f -exec stat -f '%m %N' {} \; 2>/dev/null \
            | sort -rn | head -1 | awk '{print $2}')
    else
        latest=$(find "$SESSIONS_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -1 | awk '{print $2}')
    fi

    echo "$latest"
}

# ─── Parse context stats from session file ─────────────────────
# Returns JSON with model info included
parse_session_context() {
    local session_file="$1"

    if [[ -z "$session_file" || ! -f "$session_file" ]]; then
        echo '{"current_k":0,"max_k":0,"pct":0,"compactions":0,"session_id":"unknown","model":"unknown","model_display":"Unknown","tier":"200k","error":"no_session"}'
        return
    fi

    local session_id
    session_id=$(basename "$session_file" .jsonl)

    local total_input=0
    local total_output=0
    local total_cache=0
    local compactions=0
    local model_raw="unknown"

    # ── Count compaction events (multiple patterns for resilience) ──
    compactions=$(grep -c '"type":"compact"' "$session_file" 2>/dev/null | tr -d '[:space:]' || echo 0)
    local compact2
    compact2=$(grep -c '"type":"compaction"' "$session_file" 2>/dev/null | tr -d '[:space:]' || echo 0)
    local compact3
    compact3=$(grep -c '"PostCompact"' "$session_file" 2>/dev/null | tr -d '[:space:]' || echo 0)
    local compact4
    compact4=$(grep -c '"summary_type":"compaction"' "$session_file" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [[ -z "$compactions" ]] && compactions=0
    [[ -z "$compact2" ]] && compact2=0
    [[ -z "$compact3" ]] && compact3=0
    [[ -z "$compact4" ]] && compact4=0
    compactions=$(( compactions + compact2 + compact3 + compact4 ))

    # ── Extract model name ──
    # Try jq first (more reliable), fall back to grep
    model_raw=$(tail -100 "$session_file" | grep -o '"model":"[^"]*"' 2>/dev/null | tail -1 | sed 's/"model":"//;s/"//' || echo "unknown")
    [[ -z "$model_raw" ]] && model_raw="unknown"

    # Get model info
    local model_info
    model_info=$(get_model_info "$model_raw")
    local model_display max_k tier
    model_display=$(echo "$model_info" | cut -d'|' -f1)
    max_k=$(echo "$model_info" | cut -d'|' -f2)
    tier=$(echo "$model_info" | cut -d'|' -f3)

    # ── Extract token usage from the most recent assistant message ──
    # Use tail to limit scan scope, then jq for reliable JSON parsing
    local last_assistant
    last_assistant=$(grep '"type":"assistant"' "$session_file" 2>/dev/null | tail -1)

    if [[ -n "$last_assistant" ]]; then
        # Try jq parsing first (reliable)
        if command -v jq &>/dev/null; then
            total_input=$(echo "$last_assistant" | jq '.usage.input_tokens // .message.usage.input_tokens // 0' 2>/dev/null || echo 0)
            total_output=$(echo "$last_assistant" | jq '.usage.output_tokens // .message.usage.output_tokens // 0' 2>/dev/null || echo 0)
            total_cache=$(echo "$last_assistant" | jq '.usage.cache_read_input_tokens // .message.usage.cache_read_input_tokens // 0' 2>/dev/null || echo 0)
            local cache_create
            cache_create=$(echo "$last_assistant" | jq '.usage.cache_creation_input_tokens // .message.usage.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)
            [[ "$total_input" == "null" ]] && total_input=0
            [[ "$total_output" == "null" ]] && total_output=0
            [[ "$total_cache" == "null" ]] && total_cache=0
            [[ "$cache_create" == "null" ]] && cache_create=0
            total_cache=$(( total_cache + cache_create ))
        else
            # Fallback: grep extraction
            total_input=$(echo "$last_assistant" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*' | tail -1)
            total_output=$(echo "$last_assistant" | grep -o '"output_tokens":[0-9]*' | grep -o '[0-9]*' | tail -1)
            total_cache=$(echo "$last_assistant" | grep -o '"cache_read_input_tokens":[0-9]*' | grep -o '[0-9]*' | tail -1)
            local cache_create
            cache_create=$(echo "$last_assistant" | grep -o '"cache_creation_input_tokens":[0-9]*' | grep -o '[0-9]*' | tail -1)
            [[ -z "$total_input" ]] && total_input=0
            [[ -z "$total_output" ]] && total_output=0
            [[ -z "$total_cache" ]] && total_cache=0
            [[ -z "$cache_create" ]] && cache_create=0
            total_cache=$(( total_cache + cache_create ))
        fi
    fi

    # Sanitize for arithmetic
    total_input=${total_input//[^0-9]/}
    total_output=${total_output//[^0-9]/}
    total_cache=${total_cache//[^0-9]/}
    [[ -z "$total_input" ]] && total_input=0
    [[ -z "$total_output" ]] && total_output=0
    [[ -z "$total_cache" ]] && total_cache=0

    # Calculate cumulative context
    local current_tokens=$(( total_input + total_cache ))
    local current_k=$(( current_tokens / 1000 ))
    local max_tokens=$(( max_k * 1000 ))
    local pct=0
    if [[ $max_tokens -gt 0 ]]; then
        pct=$(( current_tokens * 100 / max_tokens ))
    fi

    # Also try to get context from embedded status lines in the transcript
    local context_line
    context_line=$(grep -o 'Context:[^]]*%' "$session_file" 2>/dev/null | tail -1)
    if [[ -n "$context_line" ]]; then
        local parsed_k parsed_max parsed_pct
        parsed_k=$(echo "$context_line" | sed 's/.*[: ~]*\([0-9]*\)[Kk]\/.*/\1/' 2>/dev/null)
        parsed_max=$(echo "$context_line" | sed 's/.*\/\([0-9.]*\)[Mm].*/\1/' 2>/dev/null)
        parsed_pct=$(echo "$context_line" | sed 's/.*(\([0-9]*\)%.*/\1/' 2>/dev/null)
        if [[ -n "$parsed_k" && -n "$parsed_pct" && "$parsed_k" =~ ^[0-9]+$ && "$parsed_pct" =~ ^[0-9]+$ ]]; then
            current_k=$parsed_k
            max_k=$(echo "$parsed_max * 1000" | bc 2>/dev/null | cut -d. -f1)
            [[ -z "$max_k" || "$max_k" == "0" ]] && max_k=1000
            pct=$parsed_pct
        fi
    fi

    echo "{\"current_k\":${current_k},\"max_k\":${max_k},\"pct\":${pct},\"compactions\":${compactions},\"session_id\":\"${session_id}\",\"model\":\"${model_raw}\",\"model_display\":\"${model_display}\",\"tier\":\"${tier}\"}"
}

# ─── Determine pressure level (model-aware) ──────────────────
get_pressure_level() {
    local pct=$1
    local current_k=$2
    local tier="${3:-1m}"

    # Get effective thresholds for this model tier
    local thresholds eff_warning eff_critical eff_planning_k
    thresholds=$(get_effective_thresholds "$tier")
    eff_warning=$(echo "$thresholds" | cut -d'|' -f1)
    eff_critical=$(echo "$thresholds" | cut -d'|' -f2)
    eff_planning_k=$(echo "$thresholds" | cut -d'|' -f3)

    if [[ $pct -ge $eff_critical ]]; then
        echo "CRITICAL"
    elif [[ $pct -ge $eff_warning ]]; then
        echo "WARNING"
    elif [[ $current_k -ge $eff_planning_k ]]; then
        echo "PLANNING"
    elif [[ $pct -ge $THRESHOLD_ADVISORY ]]; then
        echo "ADVISORY"
    elif [[ $pct -ge $THRESHOLD_INFO ]]; then
        echo "INFO"
    else
        echo "NOMINAL"
    fi
}

# ─── Smooth gradient color for a percentage ───────────────────
# Returns an ANSI 256-color escape code that smoothly transitions:
#   0-50%  = green (color 34/82)
#   50-70% = green → yellow
#   70-85% = yellow → orange
#   85%+   = orange → red (with bold/blink at 95%+)
get_gradient_color() {
    local pct=$1
    local start=${COLOR_GRADIENT_START:-50}

    if [[ $pct -lt $start ]]; then
        # Solid green
        printf '\033[38;5;82m'
    elif [[ $pct -lt 65 ]]; then
        # Green → Yellow-green  (82 → 118 → 154 → 190 → 226)
        local range=$(( 65 - start ))
        local pos=$(( pct - start ))
        local step=$(( pos * 4 / range ))
        local colors=(82 118 154 190 226)
        printf '\033[38;5;%dm' "${colors[$step]}"
    elif [[ $pct -lt 75 ]]; then
        # Yellow → Orange (226 → 220 → 214 → 208)
        local pos=$(( pct - 65 ))
        local step=$(( pos * 3 / 10 ))
        local colors=(226 220 214 208)
        printf '\033[38;5;%dm' "${colors[$step]}"
    elif [[ $pct -lt 85 ]]; then
        # Orange → Red-orange (208 → 202 → 196)
        local pos=$(( pct - 75 ))
        local step=$(( pos * 2 / 10 ))
        local colors=(208 202 196)
        printf '\033[38;5;%dm' "${colors[$step]}"
    elif [[ $pct -lt 95 ]]; then
        # Red (196) bold
        printf '\033[1;38;5;196m'
    else
        # Red + blink for emergency
        printf '\033[1;5;38;5;196m'
    fi
}

# ─── Get color for pressure level (legacy, for status text) ───
get_level_color() {
    local level=$1
    case "$level" in
        CRITICAL)  echo "$RED" ;;
        WARNING)   echo "$ORANGE" ;;
        PLANNING)  echo "$YELLOW" ;;
        ADVISORY)  echo "$YELLOW" ;;
        INFO)      echo "$CYAN" ;;
        NOMINAL)   echo "$GREEN" ;;
        *)         echo "$WHITE" ;;
    esac
}

# ─── Render pressure bar with smooth gradient ─────────────────
render_pressure_bar() {
    local pct=$1
    local width=${BAR_WIDTH:-40}
    local filled=$(( pct * width / 100 ))
    [[ $filled -gt $width ]] && filled=$width
    local empty=$(( width - filled ))

    printf "["
    # Each filled segment gets its own color based on what % it represents
    for ((i=0; i<filled; i++)); do
        local seg_pct=$(( i * 100 / width ))
        printf "$(get_gradient_color "$seg_pct")█"
    done
    printf "${RESET}"
    for ((i=0; i<empty; i++)); do printf "░"; done

    # The percentage label gets the color of the current level
    local label_color
    label_color=$(get_gradient_color "$pct")
    printf " ${label_color}%3d%%${RESET}" "$pct"
}

# ─── Format context size for display ──────────────────────────
format_context_size() {
    local k=$1
    if [[ $k -ge 1000 ]]; then
        local m=$(( k / 1000 ))
        local remainder=$(( (k % 1000) / 100 ))
        if [[ $remainder -gt 0 ]]; then
            echo "${m}.${remainder}M"
        else
            echo "${m}M"
        fi
    else
        echo "${k}K"
    fi
}

format_max_context() {
    local k=$1
    if [[ $k -ge 1000 ]]; then
        echo "$(( k / 1000 ))M"
    else
        echo "${k}K"
    fi
}

# ─── Send desktop notification ─────────────────────────────────
send_notification() {
    local title="$1"
    local message="$2"

    [[ "$DESKTOP_NOTIFY" != "true" ]] && return

    if command -v osascript &>/dev/null; then
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null
    elif command -v notify-send &>/dev/null; then
        notify-send "$title" "$message" 2>/dev/null
    fi
}

# ─── Play alert sound ─────────────────────────────────────────
play_alert_sound() {
    [[ "$SOUND_ON_COMPACT" != "true" ]] && return

    if command -v afplay &>/dev/null; then
        afplay /System/Library/Sounds/Sosumi.aiff &>/dev/null &
    elif command -v paplay &>/dev/null; then
        paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga &>/dev/null &
    elif command -v aplay &>/dev/null; then
        ( speaker-test -t sine -f 880 -l 1 &>/dev/null & sleep 0.3; kill $! ) &>/dev/null &
    fi
}

# ─── Update growth tracking state ─────────────────────────────
update_growth_state() {
    local current_k=$1
    local pct=$2
    local session_id=$3
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local state='{}'
    [[ -f "$STATE_FILE" ]] && state=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')

    local prev_session
    prev_session=$(echo "$state" | jq -r '.session_id // "none"' 2>/dev/null)

    if [[ "$prev_session" != "$session_id" ]]; then
        state=$(jq -n --arg sid "$session_id" --arg ts "$now" --argjson k "$current_k" --argjson p "$pct" '{
            session_id: $sid,
            history: [{ts: $ts, k: ($k|tonumber), pct: ($p|tonumber)}],
            alerts_sent: {},
            started: $ts
        }')
    else
        state=$(echo "$state" | jq --arg ts "$now" --argjson k "$current_k" --argjson p "$pct" --argjson max "$HISTORY_SIZE" '
            .history += [{ts: $ts, k: ($k|tonumber), pct: ($p|tonumber)}] | .history = .history[-($max|tonumber):]
        ')
    fi

    echo "$state" > "$STATE_FILE"
    echo "$state"
}

# ─── Calculate growth rate (K per minute) ─────────────────────
calc_growth_rate() {
    local state="$1"

    local count
    count=$(echo "$state" | jq '.history | length' 2>/dev/null)
    [[ -z "$count" || "$count" -lt 2 ]] && echo "0" && return

    local first_k last_k first_ts last_ts
    first_k=$(echo "$state" | jq '.history[0].k' 2>/dev/null)
    last_k=$(echo "$state" | jq '.history[-1].k' 2>/dev/null)
    first_ts=$(echo "$state" | jq -r '.history[0].ts' 2>/dev/null)
    last_ts=$(echo "$state" | jq -r '.history[-1].ts' 2>/dev/null)

    local first_epoch last_epoch
    first_epoch=$(date -d "$first_ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$first_ts" +%s 2>/dev/null || echo 0)
    last_epoch=$(date -d "$last_ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_ts" +%s 2>/dev/null || echo 0)

    local delta_sec=$(( last_epoch - first_epoch ))
    [[ $delta_sec -le 0 ]] && echo "0" && return

    local delta_k=$(( last_k - first_k ))
    local delta_min=$(( delta_sec / 60 ))
    [[ $delta_min -le 0 ]] && delta_min=1

    echo $(( delta_k / delta_min ))
}

# ─── Generate statusline output ───────────────────────────────
# Compact single-line output for Claude Code's status line feature.
# Format: "Model | ███░░ 62% | ~8 turns left"
render_statusline() {
    local stats="$1"
    local current_k max_k pct compactions model_display tier
    current_k=$(echo "$stats" | jq '.current_k')
    max_k=$(echo "$stats" | jq '.max_k')
    pct=$(echo "$stats" | jq '.pct')
    compactions=$(echo "$stats" | jq '.compactions')
    model_display=$(echo "$stats" | jq -r '.model_display')
    tier=$(echo "$stats" | jq -r '.tier')

    # Mini bar (10 chars wide)
    local width=10
    local filled=$(( pct * width / 100 ))
    [[ $filled -gt $width ]] && filled=$width
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Status icon
    local icon="🟢"
    local level
    level=$(get_pressure_level "$pct" "$current_k" "$tier")
    case "$level" in
        CRITICAL)  icon="🔴" ;;
        WARNING)   icon="🟠" ;;
        PLANNING)  icon="🟡" ;;
        ADVISORY)  icon="🟡" ;;
        INFO)      icon="🔵" ;;
        NOMINAL)   icon="🟢" ;;
    esac

    local ctx_display
    ctx_display="$(format_context_size "$current_k")/$(format_max_context "$max_k")"

    local compact_str=""
    if [[ $compactions -ge 1 ]]; then
        compact_str=" | ⚠${compactions}x compacted"
    fi

    echo "${icon} ${model_display} | ${bar} ${pct}% (${ctx_display})${compact_str}"
}
