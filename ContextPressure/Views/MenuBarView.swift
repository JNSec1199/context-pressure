// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

/// The main dropdown view when clicking the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var monitor: ContextMonitor
    @ObservedObject var panelManager: FloatingPanelManager
    @ObservedObject var updateChecker: UpdateChecker
    @State private var refreshFlash = false
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            if monitor.hasActiveSession {
                activeSessionView
            } else {
                noSessionView
            }
        }
        .frame(width: 300)
    }

    // MARK: - Active Session

    private var activeSessionView: some View {
        let state = monitor.state
        let level = state.pressureLevel

        return VStack(spacing: 12) {
            // Header: Model name
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
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Gauge
            PressureGaugeView(
                percentage: state.percentage,
                level: level
            )
            .padding(.vertical, 4)

            // Context size
            HStack {
                Text(state.formattedCurrentSize)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("/ \(state.formattedMaxSize)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal, 16)

            // Stats grid
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
            .padding(.horizontal, 16)

            // Action hint for high pressure
            if let hint = level.actionHint {
                Divider()
                    .padding(.horizontal, 16)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: level >= .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundColor(level >= .critical ? .red : .orange)
                        .font(.system(size: 14))

                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundColor(level >= .critical ? .red : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(level >= .critical ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                )
                .padding(.horizontal, 12)
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
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.15))
                )
                .padding(.horizontal, 12)
            }

            // Activity feed
            if !state.recentActivity.isEmpty || state.turnCount > 0 {
                Divider()
                    .padding(.horizontal, 16)

                ActivityFeedView(
                    activities: state.recentActivity,
                    turnCount: state.turnCount,
                    tokensPerTurn: state.tokensPerTurn,
                    estimatedTotalTurns: state.estimatedTotalTurns
                )
                .padding(.horizontal, 16)
            }

            Divider()
                .padding(.horizontal, 16)

            // Footer with last-updated timestamp
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
            .padding(.horizontal, 16)

            // Bottom buttons
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

                Button(action: {
                    panelManager.pin()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: panelManager.isPinned ? "pin.fill" : "pin")
                        Text(panelManager.isPinned ? "Pinned" : "Pin")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(panelManager.isPinned ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.1))
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
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // About section (expandable)
            if showAbout {
                Divider()
                    .padding(.horizontal, 16)
                AboutView(updateChecker: updateChecker)
                    .padding(.bottom, 8)
            } else {
                // Version footer
                Text("Context Pressure \(AppVersion.displayString)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - No Session

    private var noSessionView: some View {
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

            if let dir = monitor.sessionDirectory {
                Text("Watching: \(dir.path)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 12) {
                Button(action: { monitor.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
    }

    // MARK: - Helpers

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
