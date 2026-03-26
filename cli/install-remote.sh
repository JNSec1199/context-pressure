#!/usr/bin/env bash
# Claude Code Context Pressure Widget - Remote Installer
#
# One-liner install (update the URL to your repo):
#   curl -sL https://raw.githubusercontent.com/YOUR_USER/claude-code-context-widget/main/install-remote.sh | bash
#
# What this does:
#   1. Downloads the widget to ~/.claude/context-widget/
#   2. Runs the installer
#   3. You're done — open Claude Code and look at the status bar

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

INSTALL_DIR="$HOME/.claude/context-widget"

# ─── UPDATE THIS to your actual GitHub repo ───────────────────
REPO_URL="https://github.com/YOUR_USER/claude-code-context-widget"
ARCHIVE_URL="$REPO_URL/archive/refs/heads/main.tar.gz"

echo ""
echo -e "${BOLD}  🧠 Claude Code Context Pressure Widget${RESET}"
echo -e "  ${YELLOW}One-liner installer${RESET}"
echo ""

# ─── Check prerequisites ─────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}✗ Python 3 is required but not installed.${RESET}"
    echo "  macOS: Python 3 should be pre-installed. Try: xcode-select --install"
    echo "  Linux: sudo apt install python3"
    exit 1
fi

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    echo -e "${RED}✗ curl or wget is required to download.${RESET}"
    exit 1
fi

# ─── Download ─────────────────────────────────────────────────
echo -e "  Downloading to ${INSTALL_DIR}..."

# Clean previous install
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "  ${YELLOW}Updating existing installation...${RESET}"
    rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"

# Download and extract
TMPDIR_DL=$(mktemp -d)
trap "rm -rf '$TMPDIR_DL'" EXIT

if command -v curl &>/dev/null; then
    curl -sL "$ARCHIVE_URL" -o "$TMPDIR_DL/widget.tar.gz"
else
    wget -q "$ARCHIVE_URL" -O "$TMPDIR_DL/widget.tar.gz"
fi

tar -xzf "$TMPDIR_DL/widget.tar.gz" -C "$TMPDIR_DL"

# Move contents (strip the top-level directory from the archive)
EXTRACTED=$(find "$TMPDIR_DL" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -n "$EXTRACTED" ]]; then
    cp -r "$EXTRACTED"/* "$INSTALL_DIR/"
else
    echo -e "${RED}✗ Download failed — archive was empty.${RESET}"
    exit 1
fi

echo -e "  ${GREEN}✓ Downloaded${RESET}"

# ─── Install ─────────────────────────────────────────────────
chmod +x "$INSTALL_DIR/install.sh"
"$INSTALL_DIR/install.sh"
