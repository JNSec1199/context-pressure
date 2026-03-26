// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import UserNotifications

/// Manages native macOS notifications for context pressure alerts.
final class NotificationManager {

    private var sentAlerts: Set<String> = []
    private var lastSessionId: String = ""

    init() {
        requestPermission()
    }

    // MARK: - Permission

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Threshold Alerts

    func sendThresholdAlert(level: PressureLevel, state: SessionState) {
        // Reset alerts if session changed
        if state.sessionId != lastSessionId {
            sentAlerts.removeAll()
            lastSessionId = state.sessionId
        }

        // Don't re-alert at the same level
        let alertKey = "\(level.rawValue)_\(state.sessionId)"
        guard !sentAlerts.contains(alertKey) else { return }
        sentAlerts.insert(alertKey)

        let pct = state.percentageInt
        let ctx = "\(state.formattedCurrentSize)/\(state.formattedMaxSize)"

        let (title, body, sound): (String, String, UNNotificationSound) = {
            switch level {
            case .emergency:
                return (
                    "\(level.icon) EMERGENCY — \(pct)% Context",
                    "\(state.model.displayName): \(ctx). Context severely degraded (\(state.compactions) compactions). Save work and rotate NOW.",
                    .defaultCritical
                )
            case .critical:
                return (
                    "\(level.icon) CRITICAL — \(pct)% Context",
                    "\(state.model.displayName): \(ctx). Compaction imminent. Save decisions to CLAUDE.md, commit changes, /clear.",
                    .defaultCritical
                )
            case .warning:
                return (
                    "\(level.icon) WARNING — \(pct)% Context",
                    "\(state.model.displayName): \(ctx). Compaction approaching. Wrap up current task, then rotate.",
                    .default
                )
            case .advisory:
                return (
                    "\(level.icon) Advisory — \(pct)% Context",
                    "\(state.model.displayName): \(ctx). Consider task boundaries for session rotation.",
                    .default
                )
            default:
                return (
                    "\(level.icon) Context at \(pct)%",
                    "\(state.model.displayName): \(ctx).",
                    .default
                )
            }
        }()

        send(
            id: alertKey,
            title: title,
            body: body,
            sound: sound,
            categoryId: level >= .warning ? "PRESSURE_CRITICAL" : "PRESSURE_INFO"
        )
    }

    // MARK: - Waiting Alert

    func sendWaitingAlert() {
        send(
            id: "waiting_\(Date().timeIntervalSince1970)",
            title: "Claude Code is waiting",
            body: "Claude needs your input to continue. Switch to the terminal.",
            sound: .default,
            categoryId: "WAITING"
        )
    }

    // MARK: - Compaction Alert

    func sendCompactionAlert(count: Int, sessionId: String) {
        let alertKey = "compact_\(count)_\(sessionId)"
        guard !sentAlerts.contains(alertKey) else { return }
        sentAlerts.insert(alertKey)

        let severity = count >= 2 ? "EMERGENCY" : "Warning"
        let body = count >= 2
            ? "Context severely degraded after \(count) compactions. Stop complex work. Save state and start fresh."
            : "Compaction #\(count) detected. Context quality reduced. Consider rotating for accuracy-sensitive work."

        send(
            id: alertKey,
            title: "\(count >= 2 ? "🚨" : "🔴") Compaction \(severity)",
            body: body,
            sound: .defaultCritical,
            categoryId: "COMPACTION"
        )
    }

    // MARK: - Private

    private func send(id: String, title: String, body: String, sound: UNNotificationSound, categoryId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.categoryIdentifier = categoryId

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
}
