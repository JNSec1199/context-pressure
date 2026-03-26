// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// Parses Claude Code JSONL session files to extract context pressure data.
final class SessionParser {

    // MARK: - Session Directory Discovery

    static func findSessionsDirectory() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude-code/sessions"),
            home.appendingPathComponent("Library/Application Support/claude-code/sessions"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Find Active Session

    /// Returns the most recently modified .jsonl file that belongs to an active (non-exited) session.
    /// A session is considered inactive if its last user message was /exit, or if the file
    /// hasn't been modified in the last 2 minutes (no active Claude process writing to it).
    static func findActiveSession(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(url: URL, date: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            // Skip subagent files
            guard !fileURL.path.contains("/subagents/") else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            candidates.append((fileURL, modified))
        }

        // Sort newest first
        candidates.sort { $0.date > $1.date }

        // Check candidates in order — return the first one that's still active
        for candidate in candidates {
            // Skip files not modified in the last 2 minutes (no active session writing)
            if Date().timeIntervalSince(candidate.date) > 120 {
                break  // All remaining are older, stop checking
            }

            // Check if the session ended with /exit
            if isSessionExited(candidate.url) {
                continue
            }

            return candidate.url
        }

        return nil
    }

    /// Check if a session's last meaningful entry is an /exit command.
    private static func isSessionExited(_ fileURL: URL) -> Bool {
        // Read the last ~4KB of the file to check for /exit
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 4096)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.availableData
        guard let tail = String(data: data, encoding: .utf8) else {
            return false
        }

        // Look at the last few lines for /exit command
        let lines = tail.components(separatedBy: .newlines)
        for line in lines.reversed() {
            guard !line.isEmpty else { continue }
            if line.contains("/exit") || line.contains("\"exit\"") {
                return true
            }
            // If we find a user prompt or assistant response after any exit, session is active
            if line.contains("\"promptId\"") {
                return false
            }
            break
        }
        return false
    }

    // MARK: - Parse Session File

    /// Parse a JSONL session file and return the current session state.
    static func parse(sessionFile: URL) -> SessionState? {
        guard let data = try? Data(contentsOf: sessionFile),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        let sessionId = sessionFile.deletingPathExtension().lastPathComponent

        // Parse from the end for efficiency (most recent data is what we need)
        var modelId = "unknown"
        let modelDisplayName: String? = nil
        let contextWindowSize: Int? = nil
        var totalInput = 0
        // totalOutput tracked for future use (cost estimation)
        var cacheRead = 0
        var cacheCreation = 0
        var compactions = 0
        var isWaitingForInput = false
        var checkedWaiting = false
        var recentActivity: [ActivityEntry] = []
        var turnCount = 0
        var totalOutput = 0
        var sessionStartTime: Date?
        var filesRead = Set<String>()
        var filesWritten = Set<String>()
        let maxActivity = 8

        // Count compactions, turns, and file access (scan all lines)
        for line in lines {
            if line.contains("\"type\":\"compact\"") ||
               line.contains("\"type\":\"compaction\"") ||
               line.contains("\"PostCompact\"") ||
               line.contains("\"summary_type\":\"compaction\"") {
                compactions += 1
            }
            if line.contains("\"type\":\"user\"") && line.contains("\"promptId\"") {
                turnCount += 1
            }
            // Grab session start from first timestamp
            if sessionStartTime == nil, line.contains("\"timestamp\"") {
                if let tsRange = line.range(of: #""timestamp":"([^"]+)""#, options: .regularExpression),
                   let valRange = line.range(of: #"(?<="timestamp":")[^"]+"#, options: .regularExpression) {
                    let _ = tsRange  // suppress unused warning
                    sessionStartTime = parseISO8601(String(line[valRange]))
                }
            }
            // Track unique files read/written via tool_use blocks
            if line.contains("\"name\":\"Read\"") || line.contains("\"name\":\"read\"") {
                if let path = extractFilePath(from: line) { filesRead.insert(path) }
            }
            if line.contains("\"name\":\"Write\"") || line.contains("\"name\":\"write\"") ||
               line.contains("\"name\":\"Edit\"") || line.contains("\"name\":\"edit\"") {
                if let path = extractFilePath(from: line) { filesWritten.insert(path) }
            }
        }

        // Parse from the end for latest state and recent activity
        var activityCollected = 0
        for line in lines.reversed() {
            guard !line.isEmpty else { continue }

            // Try to parse as JSON
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // Extract model info (keep looking until we find it)
            if modelId == "unknown" {
                if let model = json["model"] as? String {
                    modelId = model
                }
                // Also check nested message.model
                if let message = json["message"] as? [String: Any],
                   let model = message["model"] as? String {
                    modelId = model
                }
            }

            // Extract token usage from assistant messages
            if totalInput == 0 {
                if let type = json["type"] as? String, type == "assistant" {
                    // Try multiple nesting patterns
                    let usage = json["usage"] as? [String: Any]
                        ?? (json["message"] as? [String: Any])?["usage"] as? [String: Any]

                    if let usage = usage {
                        totalInput = usage["input_tokens"] as? Int ?? 0
                        totalOutput = usage["output_tokens"] as? Int ?? 0
                        cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                        cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
                    }
                }
            }

            // Collect recent tool_use activity from assistant messages
            if activityCollected < maxActivity {
                if let type = json["type"] as? String, type == "assistant" {
                    let message = json["message"] as? [String: Any]
                    let content = message?["content"] as? [[String: Any]] ?? []
                    let ts = json["timestamp"] as? String
                    let date = ts.flatMap { parseISO8601($0) } ?? Date()

                    for block in content {
                        guard block["type"] as? String == "tool_use",
                              let toolName = block["name"] as? String,
                              activityCollected < maxActivity else { continue }
                        let input = block["input"] as? [String: Any] ?? [:]
                        let entry = ActivityEntry.from(toolName: toolName, input: input, timestamp: date)
                        recentActivity.append(entry)
                        activityCollected += 1
                    }
                }
            }

            // Detect "waiting for input" state by checking the most recent entries.
            if !checkedWaiting {
                checkedWaiting = true
                if let type = json["type"] as? String {
                    if type == "assistant" {
                        let message = json["message"] as? [String: Any]
                        let stopReason = message?["stop_reason"] as? String
                        if stopReason == "tool_use" {
                            isWaitingForInput = true
                        }
                    }
                }
            }

            // Stop scanning once we have what we need
            if modelId != "unknown" && totalInput > 0 && activityCollected >= maxActivity {
                break
            }
        }

        // Reverse activity so newest is first
        recentActivity.reverse()

        let model = ModelInfo.from(
            id: modelId,
            displayName: modelDisplayName,
            windowSize: contextWindowSize
        )

        let currentTokens = totalInput + cacheRead + cacheCreation
        let maxTokens = model.contextWindowSize
        let percentage = (currentTokens > 0 && maxTokens > 0) ? Double(currentTokens) / Double(maxTokens) : 0
        let tokensPerTurn = turnCount > 0 ? currentTokens / turnCount : 0

        return SessionState(
            sessionId: sessionId,
            model: model,
            currentTokens: currentTokens,
            maxTokens: maxTokens,
            compactions: compactions,
            percentage: percentage,
            growthRateKPerMin: 0,
            estimatedTurnsRemaining: nil,
            isWaitingForInput: isWaitingForInput,
            lastUpdated: Date(),
            recentActivity: recentActivity,
            turnCount: turnCount,
            tokensPerTurn: tokensPerTurn,
            sessionStartTime: sessionStartTime,
            outputTokens: totalOutput,
            filesReadCount: filesRead.count,
            filesWrittenCount: filesWritten.count
        )
    }

    // MARK: - Parse Status Line JSON

    /// Parse the JSON that Claude Code sends to statusLine scripts via stdin.
    static func parseStatusLineJSON(_ jsonString: String) -> SessionState? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let modelDict = json["model"] as? [String: Any] ?? [:]
        let modelId = modelDict["id"] as? String ?? "unknown"
        let modelName = modelDict["display_name"] as? String

        let ctx = json["context_window"] as? [String: Any] ?? [:]
        let pct = ctx["used_percentage"] as? Double ?? 0
        let windowSize = ctx["context_window_size"] as? Int ?? 200_000
        let totalInput = ctx["total_input_tokens"] as? Int ?? 0

        let sessionId = json["session_id"] as? String ?? "unknown"

        let model = ModelInfo.from(id: modelId, displayName: modelName, windowSize: windowSize)

        return SessionState(
            sessionId: sessionId,
            model: model,
            currentTokens: totalInput,
            maxTokens: windowSize,
            compactions: 0,
            percentage: pct / 100.0,
            growthRateKPerMin: 0,
            estimatedTurnsRemaining: nil,
            isWaitingForInput: false,
            lastUpdated: Date(),
            recentActivity: [],
            turnCount: 0,
            tokensPerTurn: 0,
            sessionStartTime: nil,
            outputTokens: 0,
            filesReadCount: 0,
            filesWrittenCount: 0
        )
    }

    // MARK: - Helpers

    /// Extract file_path from a tool_use JSON line via simple string search.
    private static func extractFilePath(from line: String) -> String? {
        guard let range = line.range(of: #"(?<="file_path":")[^"]+"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range])
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseISO8601(_ string: String) -> Date? {
        iso8601Formatter.date(from: string)
    }
}
