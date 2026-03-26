// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

@main
struct ContextPressureApp: App {
    @StateObject private var monitor = ContextMonitor()
    @StateObject private var panelManager: FloatingPanelManager
    @StateObject private var updateChecker = UpdateChecker()

    init() {
        let mon = ContextMonitor()
        let pm = FloatingPanelManager(monitor: mon)
        _monitor = StateObject(wrappedValue: mon)
        _panelManager = StateObject(wrappedValue: pm)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor, panelManager: panelManager, updateChecker: updateChecker)
                .onAppear {
                    // Share the update checker with the panel manager
                    panelManager.updateChecker = updateChecker
                }
        } label: {
            MenuBarLabel(
                state: monitor.state,
                hasSession: monitor.hasActiveSession,
                isWaiting: monitor.state.isWaitingForInput,
                blinkOn: monitor.blinkOn
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label (the icon in the menu bar)

struct MenuBarLabel: View {
    let state: SessionState
    let hasSession: Bool
    let isWaiting: Bool
    let blinkOn: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isWaiting {
                Image(systemName: blinkOn ? "hand.raised.fill" : "brain")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(blinkOn ? .yellow : iconColor, .secondary)
            } else {
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColor, .secondary)
            }

            if hasSession && state.percentageInt > 0 {
                Text(isWaiting && blinkOn ? "⏳" : "\(state.percentageInt)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        guard hasSession else { return "brain" }
        let level = state.pressureLevel
        switch level {
        case .nominal, .info:
            return "brain"
        case .advisory:
            return "brain"
        case .warning:
            return "brain.head.profile"
        case .critical, .emergency:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        guard hasSession else { return .secondary }
        let level = state.pressureLevel
        switch level {
        case .nominal: return .green
        case .info: return .cyan
        case .advisory: return .yellow
        case .warning: return .orange
        case .critical, .emergency: return .red
        }
    }
}
