//
//  SignedInRootView.swift
//  TelephoneBoothOperatorMobile
//
//  Placeholder dashboard shown after successful sign-in. PR 3 replaces
//  this with the real status / sessions / messages dashboard. For now it
//  proves end-to-end auth + REST round-trips against the operator API.
//

import SwiftUI

public struct SignedInRootView: View {
    @State private var auth = AuthManager.shared
    @State private var profile: OperatorMe?
    @State private var stats: StatsSummary?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    operatorCard
                    statsCard
                    placeholderNotice
                }
                .padding(Theme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Operator")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
                #if !os(watchOS)
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh")
                }
                #endif
            }
            #endif
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var operatorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            sectionHeader("Signed in as")
            if let profile {
                Text(profile.name)
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(profile.email)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if !profile.groups.isEmpty {
                    Text(profile.groups.joined(separator: " · "))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            sectionHeader("Booth")
            if let stats {
                statRow(label: "State", value: stats.booth.state.rawValue.capitalized)
                statRow(label: "Calls today", value: "\(stats.calls.today)")
                statRow(label: "In progress", value: "\(stats.calls.inProgress)")
                statRow(label: "Messages pending", value: "\(stats.messages.pending)")
                statRow(label: "Messages today", value: "\(stats.messages.receivedToday)")
                statRow(label: "Live web clients", value: "\(stats.realtime.wsClients)")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    private var placeholderNotice: some View {
        Text("Sessions, messages, moderation, events, and widgets arrive in upcoming releases.")
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.leading)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.Fonts.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Theme.Colors.error)
            .font(Theme.Fonts.bodySmall)
            .padding(Theme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardBackground()
    }

    private func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        async let meTask: OperatorMe? = (try? await OperatorClient.shared.fetchMe())
        async let statsTask: StatsSummary? = (try? await OperatorClient.shared.fetchStatsSummary())
        let (fetchedMe, fetchedStats) = await (meTask, statsTask)
        profile = fetchedMe ?? profile
        stats = fetchedStats ?? stats
        if fetchedMe == nil && fetchedStats == nil {
            errorMessage = "Couldn't reach the operator. Check your network or server URL in Settings."
        }
    }
}

private extension View {
    @ViewBuilder
    func glassCardBackground() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.Colors.elevatedBackground)
            )
            .modifier(GlassOverlayModifier())
    }
}

private struct GlassOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(visionOS)
        content
            .glassBackgroundEffect(in: .rect(cornerRadius: Theme.cornerRadius))
        #else
        content
        #endif
    }
}

#Preview {
    SignedInRootView()
}
