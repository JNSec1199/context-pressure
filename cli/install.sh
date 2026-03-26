#!/usr/bin/env bash
# Claude Code Context Pressure Widget - Installer (macOS/Linux)
#
# Usage:
#   ./install.sh              Install the widget
#   ./install.sh --uninstall  Remove the widget cleanly
#   ./install.sh --check      Verify installation
#
# What this does:
#   - Validates your environment (Python 3, Claude Code installed)
#   - Adds a context pressure meter to Claude Code's status bar
#   - Optionally installs hooks for desktop notifications
#   - Backs up your settings before making changes

set -e

# ─── Colors & Formatting ─────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP_FILE="$CLAUDE_DIR/settings.json.bak-context-widget"

# ─── Helpers ──────────────────────────────────────────────────
info()    { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET} $1"; }
err()     { echo -e "  ${RED}✗${RESET} $1"; }
step()    { echo -e "\n${BOLD}${CYAN}$1${RESET}"; }
divider() { echo -e "${DIM}  ──────────────────────────────────────────────${RESET}"; }

# ─── Banner ───────────────────────────────────────────────────
show_banner() {
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}  ║  🧠 Claude Code Context Pressure Widget         ║${RESET}"
    echo -e "${BOLD}  ║     Know when compaction is coming.              ║${RESET}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ─── Preflight Checks ────────────────────────────────────────
preflight() {
    step "Checking your environment..."
    local ok=true

    # Python 3
    if command -v python3 &>/dev/null; then
        local pyver
        pyver=$(python3 --version 2>&1 | awk '{print $2}')
        info "Python 3 found ($pyver)"
    else
        err "Python 3 not found."
        echo ""
        echo "    Python 3 is required and usually comes pre-installed on macOS."
        echo "    If you're on Linux, install it with:"
        echo "      sudo apt install python3   (Debian/Ubuntu)"
        echo "      sudo dnf install python3   (Fedora/RHEL)"
        echo ""
        ok=false
    fi

    # Claude Code
    if command -v claude &>/dev/null; then
        info "Claude Code CLI found"
    elif [[ -d "$CLAUDE_DIR" ]]; then
        info "Claude Code directory found (~/.claude)"
    else
        err "Claude Code doesn't appear to be installed."
        echo ""
        echo "    This widget works with Claude Code (the CLI/desktop app)."
        echo "    Install it from: https://claude.ai/code"
        echo "    Note: This does NOT work with Claude Desktop (the chat app)."
        echo ""
        ok=false
    fi

    # Check if settings.json exists or can be created
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        # Validate it's valid JSON
        if python3 -c "import json; json.load(open('$CLAUDE_SETTINGS'))" 2>/dev/null; then
            info "Settings file is valid JSON"
        else
            err "~/.claude/settings.json exists but contains invalid JSON."
            echo "    Please fix it manually or delete it and re-run this installer."
            ok=false
        fi
    else
        if [[ -d "$CLAUDE_DIR" ]]; then
            info "Settings file will be created"
        else
            info "~/.claude directory will be created"
        fi
    fi

    # Optional: jq (only needed for full dashboard, not statusline)
    if command -v jq &>/dev/null; then
        info "jq found (enables full terminal dashboard)"
    else
        warn "jq not found — status bar will work, but the full terminal"
        echo "       dashboard (context-monitor.sh) won't be available."
        echo "       Install jq later if you want it: brew install jq"
    fi

    if [[ "$ok" == "false" ]]; then
        echo ""
        err "Please fix the issues above and try again."
        exit 1
    fi
}

# ─── Install ─────────────────────────────────────────────────
do_install() {
    show_banner
    preflight

    step "Installing..."

    # Make scripts executable
    chmod +x "$SCRIPT_DIR/statusline.py"
    chmod +x "$SCRIPT_DIR/context-monitor.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/config.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/lib.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/statusline.sh" 2>/dev/null || true
    for hook in "$SCRIPT_DIR"/hooks/*.sh; do
        [[ -f "$hook" ]] && chmod +x "$hook"
    done
    info "Scripts are executable"

    # Create Claude directory if needed
    if [[ ! -d "$CLAUDE_DIR" ]]; then
        mkdir -p "$CLAUDE_DIR"
        info "Created ~/.claude"
    fi

    # Create settings.json if needed
    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        echo '{}' > "$CLAUDE_SETTINGS"
        info "Created ~/.claude/settings.json"
    fi

    # Backup existing settings
    cp "$CLAUDE_SETTINGS" "$BACKUP_FILE"
    info "Backed up settings to settings.json.bak-context-widget"

    # Merge our config into settings.json using Python (no jq needed)
    python3 - "$CLAUDE_SETTINGS" "$SCRIPT_DIR" <<'PYINSTALL'
import json
import sys
import os

settings_path = sys.argv[1]
widget_dir = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

# Add statusLine (the main feature - no extra terminal needed)
settings["statusLine"] = {
    "type": "command",
    "command": os.path.join(widget_dir, "statusline.py")
}

# Add hooks for desktop notifications
if "hooks" not in settings:
    settings["hooks"] = {}

hook_dir = os.path.join(widget_dir, "hooks")

settings["hooks"]["PreCompact"] = [{
    "matcher": "",
    "hooks": [{"type": "command", "command": os.path.join(hook_dir, "pre-compact.sh")}]
}]

settings["hooks"]["PostCompact"] = [{
    "matcher": "",
    "hooks": [{"type": "command", "command": os.path.join(hook_dir, "post-compact.sh")}]
}]

settings["hooks"]["Stop"] = [{
    "matcher": "",
    "hooks": [{"type": "command", "command": os.path.join(hook_dir, "stop-context-check.sh")}]
}]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYINSTALL

    info "Status line and hooks added to settings.json"

    # ─── Success ──────────────────────────────────────────────
    echo ""
    echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}  ║              Installation Complete!              ║${RESET}"
    echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}What happens now:${RESET}"
    echo ""
    echo -e "  Open Claude Code and you'll see a context pressure meter"
    echo -e "  in the bottom status bar. It looks like this:"
    echo ""
    echo -e "    ${GREEN}🟢 Opus 4.6 ██░░░░░░░░ 20% (200K/1M)${RESET}"
    echo -e "    ${YELLOW}🟡 Opus 4.6 ███████░░░ 72% (720K/1M)${RESET}"
    echo -e "    ${RED}🔴 Sonnet 4 ████████░░ 80% (160K/200K) SAVE+ROTATE${RESET}"
    echo ""
    echo -e "  As context fills up, the icon changes:"
    echo -e "    🟢 All good  →  🔵 Warming up  →  🟡 Getting full"
    echo -e "    →  🟠 Wrap up  →  🔴 Save your work and rotate!"
    echo ""
    echo -e "  You'll also get ${BOLD}desktop notifications${RESET} when approaching"
    echo -e "  compaction and when compaction actually happens."
    echo ""
    divider
    echo ""
    echo -e "  ${DIM}To customize thresholds: edit $SCRIPT_DIR/config.sh${RESET}"
    echo -e "  ${DIM}To uninstall:            $SCRIPT_DIR/install.sh --uninstall${RESET}"
    if command -v jq &>/dev/null; then
        echo -e "  ${DIM}Full dashboard (optional): $SCRIPT_DIR/context-monitor.sh${RESET}"
    fi
    echo ""
}

# ─── Uninstall ────────────────────────────────────────────────
do_uninstall() {
    show_banner
    step "Uninstalling..."

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        warn "No settings.json found — nothing to uninstall."
        exit 0
    fi

    # Remove our entries from settings.json using Python
    python3 - "$CLAUDE_SETTINGS" "$SCRIPT_DIR" <<'PYUNINSTALL'
import json
import sys
import os

settings_path = sys.argv[1]
widget_dir = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

# Remove statusLine if it points to our script
sl = settings.get("statusLine", {})
if isinstance(sl, dict) and widget_dir in sl.get("command", ""):
    del settings["statusLine"]

# Remove our hooks (only if they point to our directory)
hooks = settings.get("hooks", {})
for hook_name in ["PreCompact", "PostCompact", "Stop"]:
    if hook_name in hooks:
        hook_list = hooks[hook_name]
        if isinstance(hook_list, list):
            filtered = []
            for entry in hook_list:
                if isinstance(entry, dict):
                    inner = entry.get("hooks", [])
                    inner = [h for h in inner if widget_dir not in h.get("command", "")]
                    if inner:
                        entry["hooks"] = inner
                        filtered.append(entry)
                else:
                    if widget_dir not in str(entry):
                        filtered.append(entry)
            if filtered:
                hooks[hook_name] = filtered
            else:
                del hooks[hook_name]
        elif isinstance(hook_list, str) and widget_dir in hook_list:
            del hooks[hook_name]

# Clean up empty hooks object
if not hooks:
    settings.pop("hooks", None)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYUNINSTALL

    info "Removed status line and hooks from settings.json"

    # Clean up state files
    rm -f /tmp/cc-context-widget-state.json 2>/dev/null
    rm -f /tmp/cc-stop-alert-state 2>/dev/null
    info "Cleaned up temp files"

    # Note about backup
    if [[ -f "$BACKUP_FILE" ]]; then
        info "Your original settings backup is at:"
        echo "       $BACKUP_FILE"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}  Uninstall complete.${RESET}"
    echo -e "  The status bar and notifications have been removed."
    echo -e "  Restart Claude Code for changes to take effect."
    echo ""
    echo -e "  ${DIM}To reinstall: $SCRIPT_DIR/install.sh${RESET}"
    echo ""
}

# ─── Check ────────────────────────────────────────────────────
do_check() {
    show_banner
    step "Checking installation..."

    local ok=true

    # Check statusline script exists and is executable
    if [[ -x "$SCRIPT_DIR/statusline.py" ]]; then
        info "statusline.py is executable"
    else
        err "statusline.py not found or not executable"
        ok=false
    fi

    # Check settings.json references our script
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        if python3 -c "
import json, sys
s = json.load(open('$CLAUDE_SETTINGS'))
sl = s.get('statusLine', {})
if isinstance(sl, dict) and '$SCRIPT_DIR' in sl.get('command', ''):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
            info "Status line is configured in settings.json"
        else
            err "Status line not found in settings.json"
            ok=false
        fi

        # Check hooks
        local hooks_found=0
        for hook_name in PreCompact PostCompact Stop; do
            if python3 -c "
import json, sys
s = json.load(open('$CLAUDE_SETTINGS'))
hooks = s.get('hooks', {}).get('$hook_name', [])
for h in hooks if isinstance(hooks, list) else []:
    for inner in h.get('hooks', []) if isinstance(h, dict) else []:
        if '$SCRIPT_DIR' in inner.get('command', ''):
            sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
                hooks_found=$((hooks_found + 1))
            fi
        done

        if [[ $hooks_found -eq 3 ]]; then
            info "All 3 hooks are configured"
        elif [[ $hooks_found -gt 0 ]]; then
            warn "Only $hooks_found of 3 hooks found — re-run installer to fix"
        else
            err "No hooks found in settings.json"
            ok=false
        fi
    else
        err "settings.json not found"
        ok=false
    fi

    # Test statusline with mock data
    local test_output
    test_output=$(echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":50,"context_window_size":200000,"total_input_tokens":100000}}' | python3 "$SCRIPT_DIR/statusline.py" 2>&1)
    if [[ $? -eq 0 && -n "$test_output" ]]; then
        info "Status line test passed: $test_output"
    else
        err "Status line test failed"
        ok=false
    fi

    echo ""
    if [[ "$ok" == "true" ]]; then
        echo -e "  ${GREEN}${BOLD}Everything looks good!${RESET} Open Claude Code to see it in action."
    else
        echo -e "  ${RED}${BOLD}Issues found.${RESET} Run ${BLUE}./install.sh${RESET} to fix."
    fi
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────
case "${1:-}" in
    --uninstall|-u)
        do_uninstall
        ;;
    --check|-c)
        do_check
        ;;
    --help|-h)
        echo "Usage: ./install.sh [option]"
        echo ""
        echo "  (no args)     Install the context pressure widget"
        echo "  --uninstall   Remove the widget and restore settings"
        echo "  --check       Verify the installation is working"
        echo "  --help        Show this help"
        echo ""
        ;;
    "")
        do_install
        ;;
    *)
        err "Unknown option: $1"
        echo "Run ./install.sh --help for usage."
        exit 1
        ;;
esac
