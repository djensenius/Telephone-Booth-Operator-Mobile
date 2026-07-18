//
//  TVScreensaverView.swift
//  TelephoneBoothOperatorMobile
//
//  Ambient, burn-in-safe screensaver for the tvOS operator wall. Instead of
//  Apple's system screensaver, it spotlights live booth stats and graphs that
//  fade/scale in, hold, then fade out on a pure-black background — each one
//  roaming to a fresh position so no pixels are lit continuously.
//
//  Data is live: it reads the shared `BoothStatusLiveStore` (WebSocket with a
//  five-second REST polling fallback) for status and summary counts, and polls
//  `/v1/stats/overview` on a slow cadence for the graph. No message content is
//  ever displayed here.
//

#if os(tvOS)

import SwiftUI

struct TVScreensaverView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let client: OperatorClient
    @State private var liveStore: BoothStatusLiveStore
    @State private var overview: StatsOverview?

    @State private var current: TVSpotlight?
    @State private var driftX: CGFloat = 0
    @State private var driftY: CGFloat = 0
    @State private var driftStarted = false
    @State private var appeared = false
    /// Set when the booth transitions into (or between) active states so the
    /// rotation can interrupt itself and surface the live status immediately.
    @State private var activationPending = false

    private let dwell: Duration = .seconds(9)
    private let fadeOut: Duration = .milliseconds(1100)
    private let gap: Duration = .seconds(1)

    // Amplitude of the gentle centered float, in points. The two axes use
    // different periods so the path traces a slow Lissajous orbit rather than a
    // straight line — enough motion to avoid burn-in without ever jumping.
    private let driftAmplitudeX: CGFloat = 90
    private let driftAmplitudeY: CGFloat = 56

    init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        self.client = client
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let current {
                TVSpotlightCard(spotlight: current)
                    .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.9))
                    .opacity(appeared ? 1 : 0)
                    .id(current.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: driftX, y: driftY)
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .boothStatusLive(liveStore)
        .onAppear {
            startDrift()
            // Surface activity right away if the booth is already busy.
            if let state = liveStore.status?.state, TVScreensaverPlaylist.isHappening(state) {
                activationPending = true
            }
        }
        .onChange(of: liveStore.status?.state) { _, newState in
            guard let newState, TVScreensaverPlaylist.isHappening(newState) else { return }
            activationPending = true
        }
        .task { await runPlaylist() }
        .task { await pollOverview() }
    }

    // MARK: - Centered float

    /// Kick off two independent, slow, auto-reversing animations (once) so the
    /// whole centered stage keeps floating continuously — the fade in/out of
    /// individual cards rides on top of this without resetting the motion.
    private func startDrift() {
        guard !driftStarted, !reduceMotion else { return }
        driftStarted = true
        withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
            driftX = driftAmplitudeX
        }
        withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
            driftY = driftAmplitudeY
        }
    }

    // MARK: - Playlist loop

    private func runPlaylist() async {
        // Give the live store a moment to seed before the first card.
        try? await Task.sleep(for: .milliseconds(400))
        while !Task.isCancelled {
            if consumeActivation() {
                await presentActivityInterrupt()
                continue
            }
            let items = TVScreensaverPlaylist.build(
                status: liveStore.status,
                stats: liveStore.stats,
                overview: overview
            )
            guard !items.isEmpty else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            for item in items.shuffled() {
                if Task.isCancelled { return }
                if consumeActivation() {
                    await presentActivityInterrupt()
                    break
                }
                await present(item)
                if Task.isCancelled { return }
                let interrupted = await hold(dwell)
                await dismissCurrent()
                if interrupted { break }
                try? await Task.sleep(for: gap)
            }
        }
    }

    /// Immediately fade in the live booth-status card when activity begins,
    /// hold it, then let the normal rotation resume.
    @MainActor
    private func presentActivityInterrupt() async {
        guard let state = liveStore.status?.state,
              let item = TVScreensaverPlaylist.statusSpotlight(for: state) else { return }
        if current != nil { await dismissCurrent() }
        await present(item)
        _ = await hold(dwell)
        await dismissCurrent()
        try? await Task.sleep(for: gap)
    }

    /// Hold for `duration`, but bail out early (returning `true`) the moment a
    /// new activation is requested so status changes surface without waiting.
    private func hold(_ duration: Duration) async -> Bool {
        let slice: Duration = .milliseconds(150)
        var elapsed: Duration = .zero
        while elapsed < duration {
            if Task.isCancelled { return false }
            if activationPending { return true }
            try? await Task.sleep(for: slice)
            elapsed += slice
        }
        return false
    }

    @MainActor
    private func consumeActivation() -> Bool {
        guard activationPending else { return false }
        activationPending = false
        return true
    }

    @MainActor
    private func present(_ item: TVSpotlight) async {
        appeared = false
        current = item
        let intro: Animation = reduceMotion ? .easeInOut(duration: 0.8) : .easeOut(duration: 1.2)
        withAnimation(intro) { appeared = true }
    }

    @MainActor
    private func dismissCurrent() async {
        withAnimation(.easeInOut(duration: fadeOutSeconds)) { appeared = false }
        try? await Task.sleep(for: fadeOut)
        current = nil
    }

    private var fadeOutSeconds: Double {
        Double(fadeOut.components.seconds) + Double(fadeOut.components.attoseconds) / 1e18
    }

    // MARK: - Overview polling (graph backup to the live status socket)

    private func pollOverview() async {
        while !Task.isCancelled {
            if let fresh = try? await client.fetchStatsOverview(window: .last7d) {
                overview = fresh
            }
            try? await Task.sleep(for: .seconds(20))
        }
    }
}

#Preview {
    TVScreensaverView(client: .demo, liveStore: .demo)
}

#endif
