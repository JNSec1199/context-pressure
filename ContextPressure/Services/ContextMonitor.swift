// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Combine
import SwiftUI

/// Watches Claude Code session files and publishes context pressure state.
/// Uses FSEvents for efficient directory watching — instant updates, no polling.
@MainActor
final class ContextMonitor: ObservableObject {

    // MARK: - Published State

    @Published var state: SessionState = .empty
    @Published var hasActiveSession: Bool = false
    @Published var sessionDirectory: URL?
    @Published var blinkOn: Bool = true  // Toggles for waiting-for-input blink

    // MARK: - Private

    private var sessionsDir: URL?
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var directoryHandle: Int32 = -1
    private var sessionFileWatchSource: DispatchSourceFileSystemObject?
    private var sessionFileHandle: Int32 = -1
    private var watchedSessionPath: String = ""
    private var refreshTimer: Timer?
    private var blinkTimer: Timer?
    private var growthHistory: [GrowthEntry] = []
    private var previousLevel: PressureLevel = .nominal
    private let notificationManager = NotificationManager()
    let alertBanner = AlertBannerManager()

    private let maxHistorySize = 30

    // MARK: - Lifecycle

    init() {
        sessionsDir = SessionParser.findSessionsDirectory()
        sessionDirectory = sessionsDir
        startWatching()
        refresh()
    }

    deinit {
        fileWatchSource?.cancel()
        sessionFileWatchSource?.cancel()
        refreshTimer?.invalidate()
        blinkTimer?.invalidate()
    }

    // MARK: - File Watching

    private func startWatching() {
        guard let dir = sessionsDir else { return }

        // Watch directory for changes using GCD file system source
        directoryHandle = open(dir.path, O_EVTONLY)
        guard directoryHandle >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryHandle,
            eventMask: [.write, .extend, .rename],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        source.setCancelHandler { [weak self] in
            if let handle = self?.directoryHandle, handle >= 0 {
                close(handle)
            }
        }

        source.resume()
        fileWatchSource = source

        // Fast polling as backup — FSEvents on the parent dir misses subdirectory changes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func stopWatching() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Session File Watching

    /// Watch the specific active session JSONL file for instant change detection.
    private func watchSessionFile(_ fileURL: URL) {
        let path = fileURL.path
        guard path != watchedSessionPath else { return }  // Already watching this file

        // Tear down previous file watcher
        sessionFileWatchSource?.cancel()
        if sessionFileHandle >= 0 { close(sessionFileHandle) }

        watchedSessionPath = path
        sessionFileHandle = open(path, O_EVTONLY)
        guard sessionFileHandle >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: sessionFileHandle,
            eventMask: [.write, .extend],
            queue: .global(qos: .userInitiated)  // High priority for fast detection
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        source.setCancelHandler { [weak self] in
            if let handle = self?.sessionFileHandle, handle >= 0 {
                close(handle)
            }
        }

        source.resume()
        sessionFileWatchSource = source
    }

    // MARK: - Refresh

    func refresh() {
        guard let dir = sessionsDir else {
            hasActiveSession = false
            return
        }

        guard let sessionFile = SessionParser.findActiveSession(in: dir) else {
            hasActiveSession = false
            state = .empty
            return
        }

        // Watch the active session file directly for instant change detection
        watchSessionFile(sessionFile)

        guard var newState = SessionParser.parse(sessionFile: sessionFile) else {
            return
        }

        hasActiveSession = true

        // Update growth tracking
        updateGrowthHistory(tokens: newState.currentTokens, sessionId: newState.sessionId)
        let growthRate = calculateGrowthRate()
        let turnsRemaining = estimateTurnsRemaining(
            currentTokens: newState.currentTokens,
            maxTokens: newState.maxTokens,
            growthRateKPerMin: growthRate
        )

        // Create updated state with growth data
        newState = SessionState(
            sessionId: newState.sessionId,
            model: newState.model,
            currentTokens: newState.currentTokens,
            maxTokens: newState.maxTokens,
            compactions: newState.compactions,
            percentage: newState.percentage,
            growthRateKPerMin: growthRate,
            estimatedTurnsRemaining: turnsRemaining,
            isWaitingForInput: newState.isWaitingForInput,
            lastUpdated: Date(),
            recentActivity: newState.recentActivity,
            turnCount: newState.turnCount,
            tokensPerTurn: newState.tokensPerTurn,
            sessionStartTime: newState.sessionStartTime,
            outputTokens: newState.outputTokens,
            filesReadCount: newState.filesReadCount,
            filesWrittenCount: newState.filesWrittenCount
        )

        // Check for threshold crossings and send notifications
        let newLevel = newState.pressureLevel
        if newLevel > previousLevel {
            notificationManager.sendThresholdAlert(level: newLevel, state: newState)
        }

        if newState.isWaitingForInput && !state.isWaitingForInput {
            notificationManager.sendWaitingAlert()
        }

        previousLevel = newLevel
        state = newState

        // Start or stop the blink timer and alert banner based on waiting state
        if newState.isWaitingForInput {
            startBlinkTimer()
            alertBanner.showBanner()
        } else {
            stopBlinkTimer()
            alertBanner.dismissBanner()
        }
    }

    // MARK: - Blink Timer

    private func startBlinkTimer() {
        guard blinkTimer == nil else { return }
        blinkOn = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.blinkOn.toggle()
            }
        }
    }

    private func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkOn = true
    }

    // MARK: - Growth Tracking

    private var lastSessionId: String = ""

    private func updateGrowthHistory(tokens: Int, sessionId: String) {
        // Reset if session changed
        if sessionId != lastSessionId {
            growthHistory.removeAll()
            lastSessionId = sessionId
        }

        growthHistory.append(GrowthEntry(timestamp: Date(), tokens: tokens))

        // Trim to max size
        if growthHistory.count > maxHistorySize {
            growthHistory.removeFirst(growthHistory.count - maxHistorySize)
        }
    }

    private func calculateGrowthRate() -> Double {
        guard growthHistory.count >= 2,
              let first = growthHistory.first,
              let last = growthHistory.last else {
            return 0
        }

        let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDelta > 0 else { return 0 }

        let tokenDelta = last.tokens - first.tokens
        let minutesDelta = timeDelta / 60.0
        guard minutesDelta > 0 else { return 0 }

        return Double(tokenDelta / 1000) / minutesDelta  // K per minute
    }

    private func estimateTurnsRemaining(currentTokens: Int, maxTokens: Int, growthRateKPerMin: Double) -> Int? {
        guard growthRateKPerMin > 0 else { return nil }

        let remainingK = (maxTokens - currentTokens) / 1000
        let minutesRemaining = Double(remainingK) / growthRateKPerMin
        let turns = Int(minutesRemaining / 2)  // ~2 min per turn average
        return max(turns, 0)
    }
}
