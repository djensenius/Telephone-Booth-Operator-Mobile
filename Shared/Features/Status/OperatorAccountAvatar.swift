//
//  OperatorAccountAvatar.swift
//  TelephoneBoothOperatorMobile
//

#if !os(watchOS) && !os(tvOS)
import SwiftUI

struct OperatorAccountAvatar: View {
    let profile: OperatorMe?

    private let size: CGFloat = 32

    var body: some View {
        avatarContent
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.Colors.elevatedBackground))
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.Colors.textSecondary.opacity(0.25), lineWidth: 1))
            .contentShape(Circle())
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let profile, let url = profile.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                case .empty:
                    fallbackImage
                case .failure:
                    fallbackImage
                @unknown default:
                    fallbackImage
                }
            }
        } else {
            fallbackImage
        }
    }

    private var fallbackImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.Colors.accent)
            .padding(3)
            .frame(width: size, height: size)
    }
}
#endif
