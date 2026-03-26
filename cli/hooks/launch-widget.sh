#!/usr/bin/env bash
# Claude Code Hook: Launch Context Pressure widget
# Fires when Claude Code starts. Checks if the menu bar app is running;
# if not, launches it.
#
# Install: Add to ~/.claude/settings.json under hooks.Start

APP_PATH="/Applications/Context Pressure.app"

# Only launch if not already running
if ! pgrep -x "ContextPressure" &>/dev/null; then
    if [[ -d "$APP_PATH" ]]; then
        open "$APP_PATH" &>/dev/null &
    fi
fi

exit 0
