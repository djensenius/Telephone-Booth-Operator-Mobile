//
//  WidgetComponents.swift
//  TBOperatorMobileWidgets
//
//  Small shared building blocks reused across every widget: family
//  helpers, container backgrounds, freshness/stale chrome, an empty
//  state, and the compact stat block. Keeping these in one place lets
//  the individual widget files stay focused on layout.
//

import SwiftUI
import WidgetKit

enum WidgetLayoutSize: Equatable {
    case accessory
    case small
    case medium
    case large
    case extraLarge
}

extension WidgetFamily {
    /// Lock Screen / accessory families are only offered on iOS/iPadOS in
    /// this app, so the predicate is guarded to compile everywhere.
    var isAccessory: Bool {
        #if os(iOS)
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }

    var operatorLayoutSize: WidgetLayoutSize {
        #if os(iOS)
        if isAccessory {
            return .accessory
        }
        #endif

        switch self {
        case .systemMedium:
            return .medium
        case .systemLarge:
            return .large
        #if os(iOS) || os(macOS)
        case .systemExtraLarge:
            return .extraLarge
        #endif
        default:
            return .small
        }
    }
}

private struct WidgetContainerBackground: ViewModifier {
    let family: WidgetFamily

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            #if os(iOS)
            if family.isAccessory {
                AccessoryWidgetBackground()
            } else {
                Rectangle().fill(.fill.tertiary)
            }
            #else
            Rectangle().fill(.fill.tertiary)
            #endif
        }
    }
}

extension View {
    /// Applies the correct widget container background for the family:
    /// a translucent accessory backdrop for Lock Screen families and the
    /// standard tertiary fill for system families.
    func widgetContainerBackground(_ family: WidgetFamily) -> some View {
        modifier(WidgetContainerBackground(family: family))
    }
}

extension WidgetSnapshot.HealthSeverity {
    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .nominal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .nominal: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        case .critical: return Theme.Colors.error
        case .unknown: return .secondary
        }
    }
}

/// Compact "updated N ago" footer that switches to a warning treatment
/// once the underlying section is stale.
struct WidgetUpdatedFooter: View {
    let date: Date
    var stale: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: stale ? "clock.badge.exclamationmark" : "clock")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(date, style: .relative)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.caption2)
        .foregroundStyle(stale ? AnyShapeStyle(Theme.Colors.warning) : AnyShapeStyle(.tertiary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        if stale {
            Text("Data is stale. Updated \(date, style: .relative)")
        } else {
            Text("Updated \(date, style: .relative)")
        }
    }
}

/// Inline "Stale" pill used in headers and rectangular accessories.
struct WidgetStaleBadge: View {
    var asOf: Date?
    @Environment(\.widgetFamily) private var family

    init(asOf: Date? = nil) {
        self.asOf = asOf
    }

    var body: some View {
        Group {
            if family.operatorLayoutSize == .small {
                Image(systemName: "clock.badge.exclamationmark")
            } else {
                Label("Stale", systemImage: "clock.badge.exclamationmark")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.Colors.warning)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        if let asOf {
            Text("Data is stale. Updated \(asOf, style: .relative)")
        } else {
            Text("Data is stale")
        }
    }
}

struct WidgetHeaderTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            .layoutPriority(1)
    }
}

/// Shared empty state for `noSnapshot` / `missingSection`, adapting to
/// accessory families where a full label would not fit.
struct WidgetUnavailableView: View {
    let title: String
    let systemImage: String
    let message: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        #if os(iOS)
        switch family {
        case .accessoryInline:
            Label(title, systemImage: systemImage)
        case .accessoryCircular:
            Image(systemName: systemImage)
                .font(.title3)
                .widgetAccentable()
                .accessibilityLabel(message)
        case .accessoryRectangular:
            Label(message, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            standard
        }
        #else
        standard
        #endif
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Small labelled figure used inside the medium/large system layouts.
struct StatBlock: View {
    let label: String
    let value: String
    var privacySensitive: Bool = true
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(compact ? .callout.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .privacySensitive(privacySensitive)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct WidgetMetricValue: Identifiable {
    let label: String
    let value: String
    var privacySensitive: Bool = true

    var id: String { label }
}

struct WidgetMetricGrid: View {
    let metrics: [WidgetMetricValue]
    let columns: Int
    var compact: Bool = false
    var staleAsOf: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: staleAsOf == nil ? 0 : 3) {
            if let staleAsOf {
                WidgetStaleBadge(asOf: staleAsOf)
            }
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                ForEach(metrics) { metric in
                    StatBlock(
                        label: metric.label,
                        value: metric.value,
                        privacySensitive: metric.privacySensitive,
                        compact: compact
                    )
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading),
            count: max(1, columns)
        )
    }
}

struct WidgetStatusBlock: View {
    let label: String
    let value: String
    let systemImage: String
    var tint: Color = .secondary
    var detail: Text?
    var privacySensitive: Bool = true
    var staleAsOf: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Label(label.uppercased(), systemImage: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if staleAsOf != nil {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.Colors.warning)
                        .accessibilityHidden(true)
                }
            }
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let staleAsOf {
                Text("Updated \(staleAsOf, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.warning)
                    .lineLimit(1)
            } else if let detail {
                detail
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive(privacySensitive)
        .accessibilityElement(children: .combine)
        .accessibilityValue(staleAsOf == nil ? "" : "Data is stale")
    }
}
