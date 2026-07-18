//
//  TVDashboardKit.swift
//  TelephoneBoothOperatorMobile
//
//  Purpose-built design system for the tvOS "big screen" dashboards
//  (booth wall, Stats, System). The shared iOS layouts don't translate
//  to a 10-foot experience: text is too small, rows stretch edge to
//  edge, and — most importantly — a plain `ScrollView` full of static
//  `Text` can't be scrolled on tvOS because nothing is focusable.
//
//  This kit fixes all three:
//    * `TVScreen`      — a scrollable scaffold that keeps content inside
//                        the title-safe area, adds a large screen header,
//                        and centres a fixed-width column.
//    * `TVFocusCard`   — a focusable card so the remote can move through
//                        the content (which is what makes the scroll view
//                        actually scroll) with an elegant focus treatment
//                        that lifts and rings the card *without* washing
//                        out the text underneath.
//    * `TVStatTile` /  — big, high-contrast metric primitives sized for
//    `TVKeyValueRow`     the couch.
//
//  Everything here is compiled only for tvOS.
//

#if os(tvOS)

import SwiftUI

// MARK: - Metrics

/// Design tokens tuned for a 1920×1080 point tvOS canvas viewed from a
/// couch. Kept local to the kit so bumping big-screen sizes never
/// disturbs the phone / watch / Mac layouts.
enum TVMetrics {
    static let screenPaddingH: CGFloat = 90
    static let screenPaddingTop: CGFloat = 60
    static let screenPaddingBottom: CGFloat = 100
    static let contentMaxWidth: CGFloat = 1600
    static let cardCornerRadius: CGFloat = 28
    static let cardPadding: CGFloat = 34
    static let cardSpacing: CGFloat = 34
    static let sectionSpacing: CGFloat = 44

    enum Font {
        static let screenTitle = SwiftUI.Font.system(size: 72, weight: .bold)
        static let cardTitle = SwiftUI.Font.system(size: 33, weight: .semibold)
        static let statValue = SwiftUI.Font.system(size: 58, weight: .bold).monospacedDigit()
        static let statValueSmall = SwiftUI.Font.system(size: 42, weight: .bold).monospacedDigit()
        static let label = SwiftUI.Font.system(size: 25, weight: .medium)
        static let rowKey = SwiftUI.Font.system(size: 29, weight: .regular)
        static let rowValue = SwiftUI.Font.system(size: 29, weight: .semibold).monospacedDigit()
        static let caption = SwiftUI.Font.system(size: 23, weight: .regular)
        static let body = SwiftUI.Font.system(size: 27, weight: .regular)
    }
}

// MARK: - Screen scaffold

/// Standard scrollable dashboard scaffold. Renders a subtle background
/// gradient, a large left-aligned screen title with an optional trailing
/// accessory, and a centred, width-limited content column. The whole
/// thing is a `ScrollView`, and because callers fill it with
/// `TVFocusCard`s the remote can drive the scroll.
struct TVScreen<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                header
                content()
            }
            .frame(maxWidth: TVMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, TVMetrics.screenPaddingH)
            .padding(.top, TVMetrics.screenPaddingTop)
            .padding(.bottom, TVMetrics.screenPaddingBottom)
        }
        .scrollClipDisabled()
        .background(TVBackground())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 22) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            Text(title)
                .font(TVMetrics.Font.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 24)
            accessory()
        }
        .padding(.bottom, 8)
    }
}

/// Shared dark gradient wash behind every tvOS dashboard.
struct TVBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Theme.Colors.background,
                Theme.Colors.secondaryBackground
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Theme.Colors.accent.opacity(0.12))
                .frame(width: 700, height: 700)
                .blur(radius: 220)
                .offset(x: -180, y: -260)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Focusable card

/// A focusable surface. Being focusable is what lets the tvOS remote move
/// through the dashboard and, as a side effect, drive the enclosing
/// `ScrollView`. The focus treatment lifts and rings the card while
/// keeping the existing (readable) text colours, so highlighting never
/// washes the content out.
struct TVFocusCard<Content: View>: View {
    var focusable: Bool = true
    @ViewBuilder var content: () -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TVMetrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: TVMetrics.cardCornerRadius, style: .continuous)
                    .fill(Theme.Colors.elevatedBackground.opacity(isFocused ? 1 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: TVMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.Colors.accent.opacity(isFocused ? 0.9 : 0.0),
                        lineWidth: 4
                    )
            )
            .shadow(
                color: Color.black.opacity(isFocused ? 0.55 : 0.25),
                radius: isFocused ? 34 : 12,
                x: 0,
                y: isFocused ? 20 : 8
            )
            .scaleEffect(isFocused ? 1.015 : 1)
            .focusable(focusable)
            .focused($isFocused)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

/// Card section heading (icon + title).
struct TVCardHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Text(title)
                .font(TVMetrics.Font.cardTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Metric primitives

/// Large label-over-value tile used in the vitals / KPI grids.
struct TVStatTile: View {
    let label: String
    let value: String
    var tint: Color = Theme.Colors.textPrimary
    var caption: String?
    var emphasize: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(TVMetrics.Font.label)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(TVMetrics.Font.statValue)
                .foregroundStyle(emphasize ? Theme.Colors.accent : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let caption {
                Text(caption)
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .padding(.horizontal, 26)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Colors.background.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    (emphasize ? Theme.Colors.accent : tint).opacity(0.28),
                    lineWidth: 1.5
                )
        )
    }
}

/// Key / value row with a readable gap (not stretched edge-to-edge).
struct TVKeyValueRow: View {
    let key: String
    let value: String
    var valueTint: Color = Theme.Colors.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(key)
                .font(TVMetrics.Font.rowKey)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .font(TVMetrics.Font.rowValue)
                .foregroundStyle(valueTint)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

/// Horizontal proportion bar with a trailing count, sized for TV.
struct TVBarRow: View {
    let label: String
    let value: Int
    let max: Int
    var tint: Color = Theme.Colors.accent

    var body: some View {
        HStack(spacing: 22) {
            Text(label)
                .font(TVMetrics.Font.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 360, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                let ratio = max > 0 ? Double(value) / Double(max) : 0
                let width = Swift.max(6, proxy.size.width * ratio)
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule().fill(tint).frame(width: width)
                }
            }
            .frame(height: 14)
            Text("\(value)")
                .font(TVMetrics.Font.rowValue)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 90, alignment: .trailing)
        }
    }
}

// MARK: - Adaptive grid

/// Two-column grid of equal-width cards that fills the content column.
struct TVCardGrid<Content: View>: View {
    var columns: Int = 2
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: TVMetrics.cardSpacing, alignment: .top),
                count: columns
            ),
            alignment: .leading,
            spacing: TVMetrics.cardSpacing
        ) {
            content()
        }
    }
}

#endif
