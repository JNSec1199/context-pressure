// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

/// Shows recent tool activity — what Claude is doing right now.
struct ActivityFeedView: View {
    let activities: [ActivityEntry]
    let turnCount: Int
    let tokensPerTurn: Int
    let estimatedTotalTurns: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Turn progress bar
            if turnCount > 0 {
                turnProgressView
            }

            // Recent activity list
            if !activities.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Recent Activity")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    ForEach(activities.prefix(5)) { entry in
                        activityRow(entry)
                    }
                }
            }
        }
    }

    // MARK: - Turn Progress

    private var turnProgressView: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "arrow.turn.right.up")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Turn \(turnCount)")
                    .font(.system(size: 12, weight: .semibold))

                if let total = estimatedTotalTurns, total > turnCount {
                    Text("of ~\(total)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if tokensPerTurn > 0 {
                    Text("~\(tokensPerTurn / 1000)K/turn")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Visual turn progress bar
            if let total = estimatedTotalTurns, total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(turnBarColor)
                            .frame(
                                width: max(geo.size.width * CGFloat(turnCount) / CGFloat(total), 4),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
        )
    }

    private var turnBarColor: LinearGradient {
        guard let total = estimatedTotalTurns, total > 0 else {
            return LinearGradient(colors: [.green], startPoint: .leading, endPoint: .trailing)
        }
        let pct = Double(turnCount) / Double(total)
        let color: Color = pct < 0.5 ? .green : pct < 0.75 ? .yellow : .orange
        return LinearGradient(colors: [color.opacity(0.8), color], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Activity Row

    private func activityRow(_ entry: ActivityEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry.icon)
                .font(.system(size: 9))
                .foregroundColor(.accentColor)
                .frame(width: 14)

            Text(entry.toolName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 55, alignment: .leading)

            Text(entry.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}
