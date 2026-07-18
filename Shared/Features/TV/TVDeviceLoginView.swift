//
//  TVDeviceLoginView.swift
//  TelephoneBoothOperatorMobile
//
//  Device Authorization Grant sign-in for tvOS. This is the *complete*
//  sign-in screen on the big screen (the shared `LoginView` defers to it
//  wholesale) so it also carries the demo-mode and settings affordances.
//  It displays the user_code and a scannable QR code while polling the
//  token endpoint, all on the themed booth background.
//

#if os(tvOS)

import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct TVDeviceLoginView: View {
    @State private var config = AppConfig.shared
    @State private var authorization: DeviceAuthorization?
    @State private var errorMessage: String?
    @State private var isStarting = false
    @State private var showingSettings = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            TVBackground()

            VStack(spacing: 52) {
                header
                Group {
                    if let authorization {
                        instructions(authorization)
                    } else if isStarting {
                        ProgressView()
                            .scaleEffect(2.4)
                            .frame(height: 200)
                    } else {
                        signInPrompt
                    }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                }
            }
            .frame(maxWidth: 1500)
            .padding(.horizontal, 90)
            .padding(.vertical, 70)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 24) {
            Image(systemName: "phone.connection")
                .font(.system(size: 88, weight: .regular))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 176, height: 176)
                .background {
                    Circle().fill(Theme.Colors.elevatedBackground)
                }
                .overlay {
                    Circle().strokeBorder(Theme.Colors.accent.opacity(0.35), lineWidth: 3)
                }
            Text("Telephone-Booth Operator")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Sign in to monitor and moderate the booth on the big screen.")
                .font(.title2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Idle prompt (start + secondary actions)

    private var signInPrompt: some View {
        VStack(spacing: 34) {
            Button {
                Task { await start() }
            } label: {
                Label("Begin sign-in", systemImage: "person.badge.key")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 44)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)

            HStack(spacing: 28) {
                Button {
                    config.enableDemoMode()
                } label: {
                    Label("Try Demo Mode", systemImage: "sparkles")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Active device-flow instructions

    private func instructions(_ auth: DeviceAuthorization) -> some View {
        HStack(alignment: .center, spacing: 72) {
            if let qrCode = Self.qrImage(for: auth.verificationURIComplete ?? auth.verificationURI) {
                VStack(spacing: 20) {
                    qrCode
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 340, height: 340)
                        .padding(26)
                        .background {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.white)
                        }
                    Text("Scan to sign in")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 26) {
                Text("On your phone or computer, visit:")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(auth.verificationURI.absoluteString)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("and enter the code:")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(auth.userCode)
                    .font(.system(size: 88, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 22)
                    .background {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Theme.Colors.accent.opacity(0.18))
                    }
                HStack(spacing: 14) {
                    ProgressView()
                    Text("Waiting for sign-in…")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(44)
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Theme.Colors.elevatedBackground.opacity(0.6))
        }
    }

    /// Renders a URL as a QR code so the user can scan it with a phone
    /// instead of typing the verification URL and code by hand.
    private static func qrImage(for url: URL) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }

    private func start() async {
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            let auth = try await AuthManager.shared.beginDeviceAuthorization()
            authorization = auth
            pollTask?.cancel()
            pollTask = Task {
                do {
                    try await AuthManager.shared.pollForDeviceToken(
                        deviceCode: auth.deviceCode,
                        interval: auth.interval,
                        expiresIn: auth.expiresIn
                    )
                } catch is CancellationError {
                    return
                } catch AuthError.cancelled {
                    return
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        authorization = nil
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif
