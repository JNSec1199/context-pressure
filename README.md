# Context Pressure

**A macOS menu bar app that monitors your AI context window in real time.**

Know when you're approaching compaction before it happens. Monitor context growth, get alerts at configurable thresholds, and make informed decisions about session rotation.

---

## Why This Exists

AI coding assistants (Claude Code, Cursor, Copilot) operate within a finite context window. When that window fills up, the model performs **compaction**: summarizing earlier conversation to make room. Each compaction is lossy. Details degrade, earlier decisions get distorted, and the model can start operating on assumptions that no longer match reality.

This is more than a performance issue. It's a quality and safety issue:

- **Context rot**: After compaction, the model fills in gaps with plausible-sounding but incorrect information. It doesn't know it's wrong.
- **Lost in the middle**: Research shows LLMs pay less attention to information in the middle of long contexts. Critical details buried in earlier exchanges get overlooked.
- **Pattern lock**: As context pressure builds, the model becomes increasingly rigid, repeating patterns from earlier in the session instead of adapting to new information.
- **Silent degradation**: There's no built-in warning. The model doesn't tell you it's about to compact or that its output quality is degrading. One turn you're getting precise, context-aware responses. The next turn, you're getting confabulations.

Context Pressure makes these invisible risks visible. It sits in your menu bar, watches your active session, and tells you exactly where you stand so you can make informed decisions about when to rotate sessions, save state, or push through.

---

## What It Does

### Menu Bar Presence

A persistent indicator in your macOS menu bar shows:
- **Brain icon** with color-coded pressure level (green through red)
- **Percentage** of context window consumed
- **Blinking hand icon** when the AI is waiting for your input (so you never leave a session idle by accident)

### Pressure Levels

| Level | Threshold | What It Means |
|-------|-----------|---------------|
| 🟢 Nominal | <40% | Full fidelity. Work freely. |
| 🔵 Info | 40-60% | Context growing. Be aware. |
| 🟡 Advisory | 60-75% | Consider wrapping up complex tasks at natural breakpoints. |
| 🟠 Warning | 75-85% | Finish your current task, then rotate to a new session. |
| 🔴 Critical | 85-95% | Stop complex work. Save state. Rotate now. |
| 🚨 Emergency | >95% | Compaction imminent or already occurring. |

### Floating Dashboard

Click the menu bar icon to see the full dashboard:

- **Pressure gauge** with real-time fill indicator
- **Token counts**: current usage vs. window size
- **Compaction counter**: how many compactions have occurred this session
- **Growth rate**: tokens per minute, so you can estimate how many turns you have left
- **Model info**: which model is active and its context window tier (200K vs 1M)
- **Activity feed**: recent session events and state changes

### Alerts and Notifications

- **Native macOS notifications** at each pressure threshold crossing
- **Compaction alerts** when compaction actually occurs
- **Floating banner** when the AI is waiting for your input (large, prominent, impossible to miss)
- Alerts are per-session and per-level: you won't get spammed with duplicates

### Auto-Update

The app checks GitHub Releases for newer versions and notifies you when an update is available.

---

## Install

### Option 1: Download the Release (Recommended)

1. Go to [Releases](https://github.com/JNSec1199/context-pressure/releases)
2. Download `Context.Pressure.zip` from the latest release
3. Unzip and drag `Context Pressure.app` to `/Applications`
4. Launch it. It appears in your menu bar.

> **Note:** On first launch, macOS may show a Gatekeeper warning since the app isn't notarized. Right-click the app, select Open, then click Open in the dialog.

### Option 2: Build from Source

Requires Xcode Command Line Tools:

```bash
xcode-select --install
```

Then:

```bash
git clone https://github.com/JNSec1199/context-pressure.git
cd context-pressure
./build.sh --install
```

This builds a universal binary (Apple Silicon + Intel) and copies it to `/Applications`.

Other build commands:

```bash
./build.sh              # Build only (output in build/)
./build.sh --run        # Build and launch
./build.sh --clean      # Remove build artifacts
```

### Option 3: Open in Xcode

Open `ContextPressure.xcodeproj` in Xcode, select your signing team, and build/run.

---

## How It Works

The app watches Claude Code's session directory (`~/.claude/projects/`) using macOS FSEvents for efficient, instant change detection. When a session file updates, it:

1. Parses the active session's JSONL transcript
2. Extracts token usage from assistant message metadata
3. Calculates context pressure as a percentage of the model's context window
4. Determines the pressure level and updates the menu bar indicator
5. Fires notifications when thresholds are crossed

There is no polling loop burning CPU. FSEvents triggers on file changes, with a lightweight backup timer to catch edge cases.

### What It Reads

- Claude Code session files (JSONL transcripts in `~/.claude/projects/`)
- That's it. No network calls except the optional GitHub update check.

### What It Doesn't Do

- No data leaves your machine (except the GitHub API check for updates, which sends no session data)
- No telemetry, analytics, or tracking
- No modification of your sessions or Claude Code configuration
- No access to your code, files, or clipboard

---

## System Requirements

- macOS 13.0 (Ventura) or later
- Claude Code installed (the app monitors Claude Code session files)
- Apple Silicon or Intel Mac (universal binary)

---

## Architecture

```
ContextPressure/
├── App/
│   ├── ContextPressureApp.swift    # Entry point, menu bar scene
│   └── AppVersion.swift            # Version constants, GitHub repo config
├── Models/
│   └── Models.swift                # PressureLevel, SessionState, ModelTier
├── Services/
│   ├── ContextMonitor.swift        # FSEvents watcher, session state publisher
│   ├── SessionParser.swift         # JSONL parsing, token extraction
│   ├── NotificationManager.swift   # Native macOS notification delivery
│   ├── AlertBannerManager.swift    # Floating "waiting for input" banner
│   ├── FloatingPanelManager.swift  # Dashboard panel management
│   └── UpdateChecker.swift         # GitHub Releases version check
├── Views/
│   ├── MenuBarView.swift           # Main dropdown view
│   ├── PressureGaugeView.swift     # Visual pressure gauge
│   ├── ActivityFeedView.swift      # Session event log
│   └── AboutView.swift             # About panel
├── Resources/
│   ├── Info.plist
│   └── ContextPressure.entitlements
└── Assets.xcassets/
```

---

## Configuration

Pressure thresholds are defined in `Models.swift`. The defaults align with practical experience from high-accuracy AI work:

- **250K tokens** is the planning threshold for session rotation on complex work
- **Zero compactions** is the goal for architecture, security, and precision tasks
- **First compaction** means save state and rotate at the next natural breakpoint
- **Second compaction** means stop immediately, checkpoint everything, start a fresh session

To adjust thresholds, edit the `PressureLevel` threshold values in `Models.swift` and rebuild.

---

## CI/CD

The repo includes a GitHub Actions workflow (`.github/workflows/build-and-release.yml`) that automatically:

1. Triggers on any `v*` tag push
2. Builds a universal binary (arm64 + x86_64) on macOS 14
3. Creates a signed `.app` bundle
4. Zips it and attaches it to a GitHub Release

To cut a new release:

```bash
# After merging changes to main:
git tag v1.1.0
git push origin v1.1.0
# GitHub Action builds and publishes the release automatically
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
