// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// MARK: - Pressure Level

enum PressureLevel: String, CaseIterable, Comparable {
    case nominal = "NOMINAL"
    case info = "INFO"
    case advisory = "ADVISORY"
    case warning = "WARNING"
    case critical = "CRITICAL"
    case emergency = "EMERGENCY"

    var sortOrder: Int {
        switch self {
        case .nominal: return 0
        case .info: return 1
        case .advisory: return 2
        case .warning: return 3
        case .critical: return 4
        case .emergency: return 5
        }
    }

    static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        rawValue
    }

    var sfSymbol: String {
        switch self {
        case .nominal: return "gauge.with.needle.fill"
        case .info: return "gauge.with.needle.fill"
        case .advisory: return "gauge.with.needle.fill"
        case .warning: return "gauge.with.needle.fill"
        case .critical: return "exclamationmark.gauge.fill"
        case .emergency: return "exclamationmark.gauge.fill"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .nominal: return "brain"
        case .info: return "brain"
        case .advisory: return "brain"
        case .warning: return "brain.head.profile"
        case .critical: return "exclamationmark.triangle.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        }
    }

    var icon: String {
        switch self {
        case .nominal: return "🟢"
        case .info: return "🔵"
        case .advisory: return "🟡"
        case .warning: return "🟠"
        case .critical: return "🔴"
        case .emergency: return "🚨"
        }
    }

    var actionHint: String? {
        switch self {
        case .nominal, .info: return nil
        case .advisory: return "Context growing — consider task boundaries"
        case .warning: return "Wrap up current task, then rotate session"
        case .critical:
            return "Save key decisions to CLAUDE.md, commit changes, start fresh (/clear)"
        case .emergency:
            return "STOP complex work. Context is severely degraded.\n1. /commit any changes\n2. Save context to CLAUDE.md\n3. /clear to start fresh"
        }
    }
}

// MARK: - Model Tier

enum ModelTier: String {
    case standard = "200K"   // 200K context window
    case extended = "1M"     // 1M context window

    var warningThreshold: Double {
        switch self {
        case .standard: return 0.65
        case .extended: return 0.75
        }
    }

    var criticalThreshold: Double {
        switch self {
        case .standard: return 0.78
        case .extended: return 0.85
        }
    }

    var advisoryThreshold: Double { 0.60 }
    var infoThreshold: Double { 0.40 }

    var planningThresholdK: Int {
        switch self {
        case .standard: return 120
        case .extended: return 250
        }
    }
}

// MARK: - Model Info

struct ModelInfo: Equatable {
    let id: String
    let displayName: String
    let tier: ModelTier
    let contextWindowSize: Int  // in tokens

    var contextWindowK: Int { contextWindowSize / 1000 }

    static let unknown = ModelInfo(
        id: "unknown",
        displayName: "Unknown",
        tier: .standard,
        contextWindowSize: 200_000
    )

    static func from(id: String, displayName: String? = nil, windowSize: Int? = nil) -> ModelInfo {
        let lc = id.lowercased()
        let (name, tier, defaultWindow): (String, ModelTier, Int) = {
            if lc.contains("opus-4-6") || lc.contains("opus-4.6") {
                return ("Opus 4.6", .extended, 1_000_000)
            } else if lc.contains("opus-4") || lc.contains("opus4") {
                return ("Opus 4", .extended, 1_000_000)
            } else if lc.contains("sonnet-4-6") || lc.contains("sonnet-4.6") {
                return ("Sonnet 4.6", .extended, 1_000_000)
            } else if lc.contains("sonnet-4-5") || lc.contains("sonnet-4.5") {
                return ("Sonnet 4.5", .extended, 1_000_000)
            } else if lc.contains("sonnet-4") || lc.contains("sonnet4") {
                return ("Sonnet 4", .standard, 200_000)
            } else if lc.contains("haiku") {
                return ("Haiku 4.5", .standard, 200_000)
            } else if lc.contains("opus") {
                return ("Opus", .extended, 1_000_000)
            } else if lc.contains("sonnet") {
                return ("Sonnet", .standard, 200_000)
            }
            return ("Unknown", .standard, 200_000)
        }()

        return ModelInfo(
            id: id,
            displayName: displayName ?? name,
            tier: windowSize.map { $0 >= 500_000 ? .extended : .standard } ?? tier,
            contextWindowSize: windowSize ?? defaultWindow
        )
    }
}

// MARK: - Session State

struct SessionState: Equatable {
    let sessionId: String
    let model: ModelInfo
    let currentTokens: Int
    let maxTokens: Int
    let compactions: Int
    let percentage: Double
    let growthRateKPerMin: Double
    let estimatedTurnsRemaining: Int?
    let isWaitingForInput: Bool
    let lastUpdated: Date
    let recentActivity: [ActivityEntry]
    let turnCount: Int
    let tokensPerTurn: Int
    let sessionStartTime: Date?
    let outputTokens: Int
    let filesReadCount: Int
    let filesWrittenCount: Int

    var currentK: Int { currentTokens / 1000 }
    var maxK: Int { maxTokens / 1000 }
    var percentageInt: Int { min(Int(percentage * 100), 100) }

    var estimatedTotalTurns: Int? {
        guard tokensPerTurn > 0 else { return nil }
        return maxTokens / tokensPerTurn
    }

    /// Session duration formatted as "Xh Ym" or "Ym"
    var sessionDuration: String? {
        guard let start = sessionStartTime else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let minutes = Int(elapsed) / 60
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    /// Rough cost estimate based on model pricing (input + output tokens)
    var estimatedCost: Double {
        let (inputPricePer1M, outputPricePer1M): (Double, Double) = {
            let id = model.id.lowercased()
            if id.contains("opus") {
                return (15.0, 75.0)      // Opus: $15/1M in, $75/1M out
            } else if id.contains("sonnet") {
                return (3.0, 15.0)       // Sonnet: $3/1M in, $15/1M out
            } else if id.contains("haiku") {
                return (0.25, 1.25)      // Haiku: $0.25/1M in, $1.25/1M out
            }
            return (3.0, 15.0)           // Default to Sonnet pricing
        }()
        let inputCost = Double(currentTokens) / 1_000_000.0 * inputPricePer1M
        let outputCost = Double(outputTokens) / 1_000_000.0 * outputPricePer1M
        return inputCost + outputCost
    }

    var formattedCost: String {
        let cost = estimatedCost
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }

    var pressureLevel: PressureLevel {
        let pct = percentage
        let tier = model.tier

        if compactions >= 2 { return .emergency }
        if pct >= tier.criticalThreshold { return .critical }
        if pct >= tier.warningThreshold { return .warning }
        if currentK >= tier.planningThresholdK { return .advisory }
        if pct >= tier.advisoryThreshold { return .advisory }
        if pct >= tier.infoThreshold { return .info }
        return .nominal
    }

    var formattedCurrentSize: String {
        formatTokenCount(currentTokens)
    }

    var formattedMaxSize: String {
        formatTokenCount(maxTokens)
    }

    static let empty = SessionState(
        sessionId: "",
        model: .unknown,
        currentTokens: 0,
        maxTokens: 200_000,
        compactions: 0,
        percentage: 0,
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

    static var hasActiveSession: Bool { true }
}

// MARK: - Activity Entry

struct ActivityEntry: Identifiable, Equatable {
    let id: String
    let toolName: String
    let detail: String      // file path, command snippet, etc.
    let timestamp: Date
    let icon: String         // SF Symbol name

    static func from(toolName: String, input: [String: Any], timestamp: Date) -> ActivityEntry {
        let (detail, icon) = parseToolDetail(toolName: toolName, input: input)
        return ActivityEntry(
            id: "\(toolName)_\(timestamp.timeIntervalSince1970)",
            toolName: formatToolName(toolName),
            detail: detail,
            timestamp: timestamp,
            icon: icon
        )
    }

    private static func formatToolName(_ name: String) -> String {
        switch name.lowercased() {
        case "read": return "Reading"
        case "write": return "Writing"
        case "edit": return "Editing"
        case "bash": return "Running"
        case "glob": return "Searching"
        case "grep": return "Searching"
        case "agent": return "Agent"
        default: return name
        }
    }

    private static func parseToolDetail(toolName: String, input: [String: Any]) -> (String, String) {
        let name = toolName.lowercased()
        if name == "read" {
            let path = input["file_path"] as? String ?? ""
            return (shortenPath(path), "doc.text.magnifyingglass")
        } else if name == "write" {
            let path = input["file_path"] as? String ?? ""
            return (shortenPath(path), "doc.badge.plus")
        } else if name == "edit" {
            let path = input["file_path"] as? String ?? ""
            return (shortenPath(path), "pencil.line")
        } else if name == "bash" {
            let cmd = input["command"] as? String ?? input["description"] as? String ?? ""
            let shortCmd = String(cmd.prefix(60))
            return (shortCmd, "terminal")
        } else if name == "glob" {
            let pattern = input["pattern"] as? String ?? ""
            return (pattern, "magnifyingglass")
        } else if name == "grep" {
            let pattern = input["pattern"] as? String ?? ""
            return (pattern, "text.magnifyingglass")
        } else if name == "agent" {
            let desc = input["description"] as? String ?? input["prompt"] as? String ?? ""
            return (String(desc.prefix(50)), "person.2")
        }
        return (toolName, "wrench")
    }

    private static func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../" + components.suffix(3).joined(separator: "/")
        }
        return path
    }
}

// MARK: - Growth History Entry

struct GrowthEntry {
    let timestamp: Date
    let tokens: Int
}

// MARK: - Helpers

func formatTokenCount(_ tokens: Int) -> String {
    let k = tokens / 1000
    if k >= 1000 {
        let m = k / 1000
        let remainder = (k % 1000) / 100
        return remainder > 0 ? "\(m).\(remainder)M" : "\(m)M"
    }
    return "\(k)K"
}
