# Claude Code Context Pressure Widget - Installer (Windows)
#
# This installer will:
# - Check for BurntToast module (optional, offers to install)
# - Merge hooks into Claude Code settings
# - Display usage instructions

param([switch]$Force)

$ErrorActionPreference = "Stop"

Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║  Claude Code Context Pressure Widget - Installer          ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""

# ─── Check for BurntToast (optional) ───────────────────────────
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Host "⚠ BurntToast module not found (optional, for better notifications)" -ForegroundColor Yellow
    Write-Host ""
    $install = Read-Host "Install BurntToast? (Y/n)"
    if ($install -ne "n" -and $install -ne "N") {
        try {
            Write-Host "Installing BurntToast..." -ForegroundColor Cyan
            Install-Module -Name BurntToast -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "✓ BurntToast installed" -ForegroundColor Green
        } catch {
            Write-Host "✗ Failed to install BurntToast. Notifications will use fallback MessageBox." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "✓ BurntToast found" -ForegroundColor Green
}

# ─── Detect install directory ──────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "✓ Widget directory: $ScriptDir" -ForegroundColor Green

# ─── Setup hooks in Claude settings ────────────────────────────
# Claude Code on Windows stores settings in AppData
$claudeSettings = "$env:APPDATA\claude-code\settings.json"
$claudeDir = Split-Path -Parent $claudeSettings

# Create Claude directory if it doesn't exist
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    Write-Host "⚠ Created $claudeDir" -ForegroundColor Yellow
}

# Create or update settings.json
if (-not (Test-Path $claudeSettings)) {
    '{}' | Set-Content $claudeSettings
    Write-Host "⚠ Created $claudeSettings" -ForegroundColor Yellow
}

# Read current settings
$currentSettings = Get-Content $claudeSettings -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
if (-not $currentSettings) {
    $currentSettings = @{}
}

# Ensure hooks object exists
if (-not $currentSettings.hooks) {
    $currentSettings.hooks = @{}
}

# Set hook paths (Windows PowerShell paths)
$currentSettings.hooks.PreCompact = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\windows\hooks\pre-compact.ps1`""
$currentSettings.hooks.PostCompact = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\windows\hooks\post-compact.ps1`""
$currentSettings.hooks.Stop = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\windows\hooks\stop-context-check.ps1`""

# Write back
$currentSettings | ConvertTo-Json -Depth 10 | Set-Content $claudeSettings
Write-Host "✓ Hooks installed to $claudeSettings" -ForegroundColor Green

# ─── Success ───────────────────────────────────────────────────
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                   Installation Complete! 🎉                ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Usage:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Run the live monitor in a split terminal pane:" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\windows\context-monitor.ps1`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Hooks will now fire automatically during Claude Code sessions:" -ForegroundColor White
Write-Host "     • PreCompact:  Notification before compaction" -ForegroundColor White
Write-Host "     • PostCompact: Notification after compaction" -ForegroundColor White
Write-Host "     • Stop:        Alert on threshold crossings" -ForegroundColor White
Write-Host ""
Write-Host "  3. Customize thresholds in:" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "$ScriptDir\windows\config.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Happy coding! 🧠" -ForegroundColor White
Write-Host ""
