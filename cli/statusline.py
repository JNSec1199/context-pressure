#!/usr/bin/env python3
"""
Claude Code Context Pressure Widget - Status Line
Reads session data from stdin (provided by Claude Code's statusLine feature)
and outputs a compact context pressure indicator.

Install: Add to ~/.claude/settings.json:
  "statusLine": { "type": "command", "command": "/path/to/statusline.py" }

No external dependencies - uses only Python stdlib.
"""

import json
import sys
import os

# ─── Configuration ─────────────────────────────────────────────
# Thresholds (percentage of context window)
THRESHOLD_INFO = 40
THRESHOLD_ADVISORY = 60
THRESHOLD_WARNING = 75
THRESHOLD_CRITICAL = 85

# 200K models get tighter thresholds (they compact sooner)
THRESHOLD_WARNING_200K = 65
THRESHOLD_CRITICAL_200K = 78

# Color gradient starts shifting from green at this percentage
COLOR_GRADIENT_START = 50

# Allow overrides via a config file next to this script
_config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.conf")
if os.path.exists(_config_path):
    with open(_config_path) as _f:
        for _line in _f:
            _line = _line.strip()
            if _line and not _line.startswith("#") and "=" in _line:
                _key, _val = _line.split("=", 1)
                _key, _val = _key.strip(), _val.strip()
                if _key in globals() and _val.isdigit():
                    globals()[_key] = int(_val)


def get_tier(window_size: int) -> str:
    """Determine model tier from context window size."""
    return "1m" if window_size >= 500_000 else "200k"


def get_thresholds(tier: str) -> tuple:
    """Return (warning_pct, critical_pct) for the given tier."""
    if tier == "200k":
        return THRESHOLD_WARNING_200K, THRESHOLD_CRITICAL_200K
    return THRESHOLD_WARNING, THRESHOLD_CRITICAL


def get_icon(pct: int, tier: str) -> str:
    """Return a status icon based on context pressure."""
    warn, crit = get_thresholds(tier)
    if pct >= crit:
        return "\U0001f534"   # red circle
    elif pct >= warn:
        return "\U0001f7e0"   # orange circle
    elif pct >= THRESHOLD_ADVISORY:
        return "\U0001f7e1"   # yellow circle
    elif pct >= THRESHOLD_INFO:
        return "\U0001f535"   # blue circle
    return "\U0001f7e2"       # green circle


def get_action(pct: int, tier: str) -> str:
    """Return a short action hint for high-pressure states."""
    warn, crit = get_thresholds(tier)
    if pct >= crit:
        return " SAVE+ROTATE"
    elif pct >= warn:
        return " wrap up"
    return ""


def make_bar(pct: int, width: int = 10) -> str:
    """Build a mini progress bar."""
    filled = min(pct * width // 100, width)
    empty = width - filled
    return "\u2588" * filled + "\u2591" * empty


def format_size(tokens: int) -> str:
    """Format a token count as human-readable K or M."""
    k = tokens // 1000
    if k >= 1000:
        m = k // 1000
        remainder = (k % 1000) // 100
        return f"{m}.{remainder}M" if remainder else f"{m}M"
    return f"{k}K"


def format_max(window_size: int) -> str:
    """Format the max window size."""
    k = window_size // 1000
    return f"{k // 1000}M" if k >= 1000 else f"{k}K"


def main():
    # Read JSON from stdin (Claude Code sends this automatically)
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            print("\U0001f9e0 No session data")
            return
        data = json.loads(raw)
    except (json.JSONDecodeError, IOError):
        print("\U0001f9e0 Waiting for session...")
        return

    # Extract fields with safe defaults
    model = data.get("model", {})
    model_name = model.get("display_name", "Unknown")

    ctx = data.get("context_window", {})
    pct = int(ctx.get("used_percentage", 0) or 0)
    window_size = int(ctx.get("context_window_size", 200_000) or 200_000)
    total_input = int(ctx.get("total_input_tokens", 0) or 0)

    tier = get_tier(window_size)
    icon = get_icon(pct, tier)
    action = get_action(pct, tier)
    bar = make_bar(pct)

    ctx_display = format_size(total_input)
    max_display = format_max(window_size)

    # Check for compaction info if available
    # (not all versions provide this, so default gracefully)
    compact_str = ""
    compactions = data.get("compactions", 0)
    if compactions and int(compactions) >= 1:
        compact_str = f" | \u26a0{compactions}x compacted"

    print(f"{icon} {model_name} {bar} {pct}% ({ctx_display}/{max_display}){action}{compact_str}")


if __name__ == "__main__":
    main()
