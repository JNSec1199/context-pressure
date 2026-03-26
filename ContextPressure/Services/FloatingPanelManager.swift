// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import AppKit
import SwiftUI

/// Manages a floating always-on-top panel that shows the context pressure widget.
/// When pinned, this panel stays visible even when the user clicks elsewhere.
@MainActor
final class FloatingPanelManager: ObservableObject {
    @Published var isPinned: Bool = false

    private var panel: NSPanel?
    private var panelDelegate: NSWindowDelegate?
    private weak var monitor: ContextMonitor?
    var updateChecker: UpdateChecker?

    init(monitor: ContextMonitor) {
        self.monitor = monitor
    }

    func toggle() {
        if isPinned {
            unpin()
        } else {
            pin()
        }
    }

    func pin() {
        guard let monitor = monitor else { return }

        // Close existing panel if any
        panel?.close()

        let panelView = FloatingPanelContentView(monitor: monitor, panelManager: self, updateChecker: updateChecker ?? UpdateChecker())
        let hostingView = NSHostingView(rootView: panelView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 400)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        newPanel.title = "Context Pressure"
        newPanel.contentView = hostingView
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true
        newPanel.hidesOnDeactivate = false
        newPanel.becomesKeyOnlyIfNeeded = true

        // Auto-size to content
        newPanel.contentView?.setFrameSize(hostingView.fittingSize)
        let contentSize = hostingView.fittingSize
        newPanel.setContentSize(NSSize(
            width: max(contentSize.width, 320),
            height: max(contentSize.height, 200)
        ))

        newPanel.minSize = NSSize(width: 320, height: 200)

        // Position near top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = newPanel.frame
            let x = screenFrame.maxX - panelFrame.width - 20
            let y = screenFrame.maxY - panelFrame.height - 20
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let delegate = PanelDelegate(manager: self)
        self.panelDelegate = delegate
        newPanel.delegate = delegate
        newPanel.orderFront(nil)

        self.panel = newPanel
        self.isPinned = true
    }

    func unpin() {
        panel?.close()
        panel = nil
        panelDelegate = nil
        isPinned = false
    }
}

// Detect when user closes the panel via the X button
private class PanelDelegate: NSObject, NSWindowDelegate {
    let manager: FloatingPanelManager

    init(manager: FloatingPanelManager) {
        self.manager = manager
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.manager.isPinned = false
        }
    }
}

/// The content view hosted inside the floating panel.
/// Same data as MenuBarView but optimized for a standalone window.
struct FloatingPanelContentView: View {
    @ObservedObject var monitor: ContextMonitor
    @ObservedObject var panelManager: FloatingPanelManager
    @ObservedObject var updateChecker: UpdateChecker
    @State private var refreshFlash = false
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            if monitor.hasActiveSession {
                panelActiveView
            } else {
                panelNoSessionView
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity)
        .padding(8)
    }

    private var panelActiveView: some View {
        let state = monitor.state
        let level = state.pressureLevel

        return VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.secondary)
                Text(state.model.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(state.model.tier.rawValue + " context")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Gauge
            PressureGaugeView(percentage: state.percentage, level: level)

            // Context size
            HStack {
                Text(state.formattedCurrentSize)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("/ \(state.formattedMaxSize)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Stats
            VStack(spacing: 8) {
                if let duration = state.sessionDuration {
                    statRow(icon: "clock", label: "Session", value: duration, color: .secondary)
                }

                statRow(icon: "dollarsign.circle", label: "Est. Cost", value: state.formattedCost, color: .secondary)

                statRow(icon: "doc.text", label: "Files", value: "\(state.filesReadCount) read · \(state.filesWrittenCount) written", color: .secondary)

                statRow(icon: "arrow.triangle.2.circlepath", label: "Compactions", value: "\(state.compactions)", color: state.compactions > 0 ? .red : .secondary)

                if state.growthRateKPerMin > 0 {
                    statRow(icon: "chart.line.uptrend.xyaxis", label: "Growth", value: "~\(Int(state.growthRateKPerMin))K/min", color: .secondary)
                }
            }

            // Waiting for input alert
            if state.isWaitingForInput {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.red)
                    Text("Claude is waiting for your input")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.15))
                )
            }

            // Activity feed
            if !state.recentActivity.isEmpty || state.turnCount > 0 {
                Divider()

                ActivityFeedView(
                    activities: state.recentActivity,
                    turnCount: state.turnCount,
                    tokensPerTurn: state.tokensPerTurn,
                    estimatedTotalTurns: state.estimatedTotalTurns
                )
            }

            Divider()

            // Footer
            HStack {
                Text("Session: \(String(state.sessionId.prefix(8)))...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 2) {
                    if refreshFlash {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    }
                    Text("Updated \(state.lastUpdated, style: .time)")
                        .font(.system(size: 10))
                        .foregroundColor(refreshFlash ? .green : .secondary)
                }
            }

            // Buttons — same as menu bar
            HStack(spacing: 8) {
                Button(action: {
                    monitor.refresh()
                    refreshFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        refreshFlash = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)

                Button(action: { panelManager.unpin() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.slash")
                        Text("Unpin")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)

                Button(action: { showAbout.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("About")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }

            // About section (expandable)
            if showAbout {
                Divider()
                AboutView(updateChecker: updateChecker)
            } else {
                Text("Context Pressure \(AppVersion.displayString)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var panelNoSessionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Active Session")
                .font(.system(size: 14, weight: .semibold))
            Text("Start Claude Code to see\ncontext pressure here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func statRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
    }

    private func colorForLevel(_ level: PressureLevel) -> Color {
        switch level {
        case .nominal: return .green
        case .info: return .cyan
        case .advisory: return .yellow
        case .warning: return .orange
        case .critical, .emergency: return .red
        }
    }
}
