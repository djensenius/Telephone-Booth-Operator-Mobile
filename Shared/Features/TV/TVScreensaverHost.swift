//
//  TVScreensaverHost.swift
//  TelephoneBoothOperatorMobile
//
//  Wires the ambient tvOS screensaver into the signed-in shell:
//  - Disables Apple's system screensaver while the dashboard is foreground
//    (`isIdleTimerDisabled`) so the wall never gets taken over.
//  - Watches for *any* remote input via window-level gesture recognizers and,
//    after `idleSeconds` of inactivity, fades in `TVScreensaverView`.
//  - Dismisses on the very next remote input.
//
//  The headless simulator can't inject idle/input, so `-uiScreensaverPreview`
//  forces the overlay on immediately for screenshot automation.
//

#if os(tvOS)

import SwiftUI
import UIKit

extension View {
    /// Adds the ambient screensaver overlay + idle monitoring to a tvOS screen.
    func tvScreensaver(
        enabled: Bool,
        idleSeconds: Int,
        client: OperatorClient,
        liveStore: BoothStatusLiveStore? = nil
    ) -> some View {
        modifier(
            TVScreensaverHostModifier(
                enabled: enabled,
                idleSeconds: idleSeconds,
                client: client,
                liveStore: liveStore
            )
        )
    }
}

private struct MonitorKey: Equatable {
    let enabled: Bool
    let idleSeconds: Int
}

private struct TVScreensaverHostModifier: ViewModifier {
    let enabled: Bool
    let idleSeconds: Int
    let client: OperatorClient
    let liveStore: BoothStatusLiveStore?

    @State private var lastInput = Date()
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .background(
                IdleInputMonitor { registerInput() }
                    .allowsHitTesting(false)
            )
            .overlay {
                if showing {
                    TVScreensaverView(client: client, liveStore: liveStore)
                        .transition(.opacity)
                        .zIndex(1000)
                        .onExitCommand { wake() }
                        .onTapGesture { wake() }
                }
            }
            .onAppear { applyIdleTimer() }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: enabled) { _, _ in applyIdleTimer() }
            .task(id: MonitorKey(enabled: enabled, idleSeconds: idleSeconds)) { await monitorIdle() }
    }

    private func applyIdleTimer() {
        // Suppress Apple's system screensaver whenever ours is enabled so the
        // two never fight; restore the default otherwise.
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    private func registerInput() {
        lastInput = Date()
        if showing { wake() }
    }

    private func wake() {
        guard showing else { return }
        withAnimation(.easeInOut(duration: 0.5)) { showing = false }
        lastInput = Date()
    }

    private func monitorIdle() async {
        guard enabled else {
            showing = false
            return
        }
        if LaunchEnv.screensaverPreview {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.6)) { showing = true }
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard enabled, !showing else { continue }
            if Date().timeIntervalSince(lastInput) >= Double(idleSeconds) {
                withAnimation(.easeInOut(duration: 0.8)) { showing = true }
            }
        }
    }
}

/// A transparent view that installs window-level gesture recognizers whose
/// only job is to notify us that the operator touched the remote. Using the
/// delegate's `shouldReceive` hooks lets us observe *every* press and touch
/// type (arrows, select, menu, play/pause, swipes) without ever consuming
/// them, so navigation is completely unaffected.
private struct IdleInputMonitor: UIViewRepresentable {
    let onInput: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onInput: onInput) }

    func makeUIView(context: Context) -> UIView {
        let view = MonitorView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? MonitorView)?.coordinator = context.coordinator
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        (uiView as? MonitorView)?.detachRecognizer()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onInput: () -> Void

        init(onInput: @escaping () -> Void) { self.onInput = onInput }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive press: UIPress
        ) -> Bool {
            onInput()
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            onInput()
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    private final class MonitorView: UIView {
        weak var coordinator: Coordinator?
        private weak var installedWindow: UIWindow?
        private var recognizer: UIGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                // Left the hierarchy (logout, theme rebuild, shell recreation):
                // tear the recognizer down so window-level recognizers don't
                // pile up over the app's lifetime.
                detachRecognizer()
            } else {
                attachRecognizer()
            }
        }

        private func attachRecognizer() {
            guard recognizer == nil, let window, let coordinator else { return }
            let recognizer = UITapGestureRecognizer(target: nil, action: nil)
            recognizer.delegate = coordinator
            recognizer.cancelsTouchesInView = false
            recognizer.allowedPressTypes = [
                NSNumber(value: UIPress.PressType.select.rawValue),
                NSNumber(value: UIPress.PressType.menu.rawValue),
                NSNumber(value: UIPress.PressType.playPause.rawValue),
                NSNumber(value: UIPress.PressType.upArrow.rawValue),
                NSNumber(value: UIPress.PressType.downArrow.rawValue),
                NSNumber(value: UIPress.PressType.leftArrow.rawValue),
                NSNumber(value: UIPress.PressType.rightArrow.rawValue)
            ]
            recognizer.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.indirect.rawValue),
                NSNumber(value: UITouch.TouchType.direct.rawValue)
            ]
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            installedWindow = window
        }

        func detachRecognizer() {
            if let recognizer, let installedWindow {
                installedWindow.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }
    }
}

#endif
