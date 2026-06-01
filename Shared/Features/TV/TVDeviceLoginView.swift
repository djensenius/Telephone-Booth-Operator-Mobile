//
//  TVDeviceLoginView.swift
//  TelephoneBoothOperatorMobile
//
//  Device Authorization Grant sign-in for tvOS. Displays the
//  user_code and verification URL while polling the token endpoint.
//

#if os(tvOS)

import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct TVDeviceLoginView: View {
    @State private var authorization: DeviceAuthorization?
    @State private var errorMessage: String?
    @State private var isStarting = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            VStack(spacing: 48) {
                Image(systemName: "phone.connection")
                    .font(.system(size: 96))
                    .foregroundStyle(Theme.Colors.accent)
                Text("Sign in to the booth")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let authorization {
                    instructions(authorization)
                } else if isStarting {
                    ProgressView()
                        .scaleEffect(2)
                } else {
                    Button {
                        Task { await start() }
                    } label: {
                        Text("Begin sign-in")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 40)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func instructions(_ auth: DeviceAuthorization) -> some View {
        HStack(alignment: .center, spacing: 64) {
            if let qrCode = Self.qrImage(for: auth.verificationURIComplete ?? auth.verificationURI) {
                VStack(spacing: 20) {
                    qrCode
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 320, height: 320)
                        .padding(24)
                        .background {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.white)
                        }
                    Text("Scan to sign in")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            VStack(spacing: 32) {
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
                    .font(.system(size: 96, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 24)
                    .background {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Theme.Colors.accent.opacity(0.18))
                    }
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for sign-in…")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
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
