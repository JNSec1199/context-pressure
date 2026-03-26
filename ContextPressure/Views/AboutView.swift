// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

/// About view showing version, attribution, and the security rationale behind the tool.
struct AboutView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showSecurityInfo = false

    var body: some View {
        VStack(spacing: 12) {
            // App identity
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Context Pressure")
                        .font(.system(size: 16, weight: .bold))
                    Text(AppVersion.displayString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // Attribution
            VStack(alignment: .leading, spacing: 6) {
                Text("Created by")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Jason Nichols")
                            .font(.system(size: 13, weight: .semibold))
                        Text("VP, Head of Information Security")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Why this tool exists
            Button(action: { showSecurityInfo.toggle() }) {
                HStack {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.orange)
                    Text("Why monitor context pressure?")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: showSecurityInfo ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showSecurityInfo {
                VStack(alignment: .leading, spacing: 6) {
                    securityPoint(
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        text: "High context pressure increases the risk of mathematical compromise in LLM outputs."
                    )
                    securityPoint(
                        icon: "arrow.triangle.2.circlepath",
                        color: .orange,
                        text: "Multiple compactions cause \"lost in the middle\" — the model loses track of earlier context and instructions."
                    )
                    securityPoint(
                        icon: "lock.open.fill",
                        color: .yellow,
                        text: "Pattern lock can occur when the model fixates on recent patterns, ignoring contradicting earlier context."
                    )
                    securityPoint(
                        icon: "checkmark.shield.fill",
                        color: .green,
                        text: "Rotating sessions at healthy thresholds maintains output accuracy and reduces security risk."
                    )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
            }

            Divider()

            // Update check
            HStack {
                if updateChecker.isChecking {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Checking...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else if let latest = updateChecker.latestVersion {
                    if latest != AppVersion.current {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("Update available: v\(latest)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Up to date")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else if let error = updateChecker.errorMessage {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { updateChecker.checkForUpdates() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Check for Updates")
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
                .disabled(updateChecker.isChecking)
            }

            // Download button if update available
            if let latest = updateChecker.latestVersion, latest != AppVersion.current,
               let url = updateChecker.downloadURL {
                Button(action: {
                    NSWorkspace.shared.open(url)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Download v\(latest)")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }

            // License
            HStack {
                Text("MIT License")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("github.com/JNSec1199/context-pressure")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    private func securityPoint(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
