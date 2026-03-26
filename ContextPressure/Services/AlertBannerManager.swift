// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import AppKit
import SwiftUI

/// Shows a large, impossible-to-miss floating banner when Claude is waiting for input.
/// Pulses red to grab attention. User can toggle pulsing off (falls back to solid red).
@MainActor
final class AlertBannerManager: ObservableObject {
    private var bannerWindow: NSPanel?
    private var pulseTimer: Timer?
    @Published var isShowing: Bool = false
    @Published var pulseEnabled: Bool = true  // User can toggle this off

    func showBanner() {
        guard !isShowing else { return }
        isShowing = true

        let bannerView = AlertBannerView(
            dismiss: { [weak self] in self?.dismissBanner() },
            togglePulse: { [weak self] in self?.pulseEnabled.toggle() },
            pulseEnabled: pulseEnabled
        )
        let hostingView = NSHostingView(rootView: bannerView)

        let bannerWidth: CGFloat = 420
        let bannerHeight: CGFloat = 90

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        // Position: top-center of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - bannerWidth / 2
            let y = screenFrame.maxY - bannerHeight - 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        startPulse(panel: panel)
        self.bannerWindow = panel
    }

    func dismissBanner() {
        guard isShowing else { return }
        isShowing = false
        pulseTimer?.invalidate()
        pulseTimer = nil

        if let panel = bannerWindow {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.close()
                Task { @MainActor [weak self] in
                    self?.bannerWindow = nil
                }
            })
        }
    }

    private func startPulse(panel: NSPanel) {
        pulseTimer?.invalidate()
        guard pulseEnabled else {
            panel.alphaValue = 1.0
            return
        }

        // Deep, slow pulse between 0.55 and 1.0 — very noticeable but not strobing
        var pulseUp = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak panel, weak self] _ in
            guard let panel = panel, self?.pulseEnabled == true else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.9
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = pulseUp ? 1.0 : 0.55
            }
            pulseUp.toggle()
        }
    }

    /// Called when user toggles pulse on/off
    func updatePulse() {
        guard let panel = bannerWindow else { return }
        if pulseEnabled {
            startPulse(panel: panel)
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 1.0
            }
        }
        // Rebuild the banner view with updated toggle state
        let bannerView = AlertBannerView(
            dismiss: { [weak self] in self?.dismissBanner() },
            togglePulse: { [weak self] in
                self?.pulseEnabled.toggle()
                self?.updatePulse()
            },
            pulseEnabled: pulseEnabled
        )
        panel.contentView = NSHostingView(rootView: bannerView)
    }
}

/// The banner view — bold red with pulsing glow and a toggle to disable pulse.
struct AlertBannerView: View {
    let dismiss: () -> Void
    let togglePulse: () -> Void
    let pulseEnabled: Bool
    @State private var iconBlink = true

    var body: some View {
        HStack(spacing: 14) {
            // Animated attention icon — red circle with alternating symbols
            ZStack {
                Circle()
                    .fill(Color.red.opacity(iconBlink ? 0.5 : 0.25))
                    .frame(width: 52, height: 52)

                Circle()
                    .stroke(Color.red.opacity(0.6), lineWidth: 2)
                    .frame(width: 52, height: 52)

                Image(systemName: iconBlink ? "hand.raised.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Claude needs your input")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)

                Text("A permission prompt is waiting")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }

            Spacer()

            VStack(spacing: 6) {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                // Pulse toggle
                Button(action: togglePulse) {
                    HStack(spacing: 3) {
                        Image(systemName: pulseEnabled ? "waveform.circle.fill" : "waveform.circle")
                            .font(.system(size: 10))
                        Text(pulseEnabled ? "Pulse" : "Static")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.05, blue: 0.05),
                            Color(red: 0.35, green: 0.02, blue: 0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.7), lineWidth: 2)
                )
                .shadow(color: .red.opacity(0.5), radius: 25, y: 4)
        )
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
                DispatchQueue.main.async { iconBlink.toggle() }
            }
        }
    }
}
