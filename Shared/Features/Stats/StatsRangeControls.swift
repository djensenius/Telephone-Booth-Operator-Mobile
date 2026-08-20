//
//  StatsRangeControls.swift
//  TelephoneBoothOperatorMobile
//
//  Range selector for the Stats screen: preset windows (24h/7d/30d/all), a
//  custom start/end range with an "end = now" toggle, and saved named filters
//  the operator can apply or delete. Extracted from `StatsView` to keep that
//  file focused on rendering the aggregates.
//

import SwiftUI

struct StatsRangeControls: View {
    @Binding var selection: StatsRangeSelection
    let filters: [MetricFilter]
    let onSave: (String) -> Void
    let onDelete: (MetricFilter) -> Void

    @State private var customStart: Date = Date().addingTimeInterval(-7 * 24 * 60 * 60)
    @State private var customEnd: Date = Date()
    @State private var endIsNow: Bool = true
    @State private var isPresentingSave = false
    @State private var newFilterName = ""

    private var selectedPreset: StatsWindow? {
        if case .window(let window) = selection { return window }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Range")
            presetPicker
            #if !os(tvOS)
            customRangeControls
            #endif
            savedFiltersRow
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
        .onAppear(perform: syncCustomFields)
        #if !os(tvOS)
        .alert("Save filter", isPresented: $isPresentingSave) {
            TextField("Name", text: $newFilterName)
            Button("Cancel", role: .cancel) { newFilterName = "" }
            Button("Save") {
                onSave(newFilterName)
                newFilterName = ""
            }
        } message: {
            Text("Save the current range as a named filter you can reapply later.")
        }
        #endif
    }

    private var presetPicker: some View {
        HStack(spacing: Theme.Spacing.small) {
            ForEach(StatsWindow.knownCases, id: \.rawValue) { option in
                StatsRangePresetButton(
                    option: option,
                    isSelected: selectedPreset == option,
                    action: { selection = .window(option) }
                )
            }
        }
    }

    #if !os(tvOS)
    private var customRangeControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            DatePicker(
                "Start",
                selection: $customStart,
                in: ...customEnd,
                displayedComponents: [.date, .hourAndMinute]
            )
            Toggle("End = now", isOn: $endIsNow)
            if !endIsNow {
                DatePicker(
                    "End",
                    selection: $customEnd,
                    in: customStart...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            HStack {
                Button {
                    applyCustomRange()
                } label: {
                    Label("Apply custom range", systemImage: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.background)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.textPrimary)
                Spacer()
                if selection.isCustom {
                    Button("Save…") { isPresentingSave = true }
                        .buttonStyle(.bordered)
                }
            }
            .font(Theme.Fonts.bodySmall)
        }
        .font(Theme.Fonts.bodySmall)
        .foregroundStyle(Theme.Colors.textPrimary)
    }
    #endif

    @ViewBuilder
    private var savedFiltersRow: some View {
        if !filters.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Saved filters")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                ForEach(filters) { filter in
                    HStack {
                        Button {
                            apply(filter: filter)
                        } label: {
                            Label(filter.name, systemImage: "bookmark")
                                .font(Theme.Fonts.bodySmall)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        #if !os(tvOS)
                        Button(role: .destructive) {
                            onDelete(filter)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(filter.name)")
                        #endif
                    }
                }
            }
        }
    }

    private func applyCustomRange() {
        selection = .custom(
            start: customStart,
            endIsNow: endIsNow,
            end: endIsNow ? nil : customEnd
        )
    }

    private func apply(filter: MetricFilter) {
        selection = filter.selection
        syncCustomFields()
    }

    private func syncCustomFields() {
        if case .custom(let start, let isNow, let end) = selection {
            if let start { customStart = start }
            endIsNow = isNow
            if let end { customEnd = end }
        }
    }
}

private struct StatsRangePresetButton: View {
    let option: StatsWindow
    let isSelected: Bool
    let action: () -> Void

    #if os(visionOS)
    @State private var isHovered = false
    #endif

    var body: some View {
        Button(action: action) {
            Text(option.shortLabel)
                .font(Theme.Fonts.bodySmall)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.small)
        }
        #if os(visionOS)
        .buttonStyle(StatsRangePresetButtonStyle(isSelected: isSelected, isHovered: isHovered))
        #else
        .buttonStyle(StatsRangePresetButtonStyle(isSelected: isSelected))
        #endif
        .contentShape(Capsule())
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        #if os(visionOS)
        .hoverEffect(.highlight)
        .onHover { isHovered = $0 }
        #endif
    }
}

private struct StatsRangePresetButtonStyle: ButtonStyle {
    let isSelected: Bool

    #if os(visionOS)
    let isHovered: Bool
    #endif

    #if os(visionOS)
    func makeBody(configuration: Configuration) -> some View {
        PresetBody(
            configuration: configuration,
            isSelected: isSelected,
            isHovered: isHovered
        )
    }
    #else
    func makeBody(configuration: Configuration) -> some View {
        PresetBody(configuration: configuration, isSelected: isSelected)
    }
    #endif

    private struct PresetBody: View {
        let configuration: Configuration
        let isSelected: Bool

    #if os(visionOS)
        let isHovered: Bool
        @Environment(\.colorSchemeContrast) private var colorSchemeContrast
        @Environment(\.isFocused) private var isFocused
    #endif

        var body: some View {
            configuration.label
                .foregroundStyle(buttonForeground)
                .background(buttonFill, in: Capsule())
                .overlay {
                    buttonBorder
                }
                #if os(visionOS)
                .scaleEffect(isHighlighted ? 1.02 : 1)
                .animation(.easeOut(duration: 0.16), value: isHighlighted)
                .animation(.easeOut(duration: 0.16), value: isSelected)
                #endif
        }

        private var buttonForeground: Color {
            isSelected ? Theme.Colors.background : Theme.Colors.textPrimary
        }

        private var buttonFill: Color {
            #if os(visionOS)
            if isSelected {
                return Theme.Colors.textPrimary
            }
            if isHighlighted {
                return Theme.Colors.secondaryBackground
            }
            let opacity = colorSchemeContrast == .increased ? 1.0 : 0.92
            return Theme.Colors.elevatedBackground.opacity(opacity)
            #else
            return isSelected
                ? Theme.Colors.textPrimary
                : Theme.Colors.textSecondary.opacity(0.08)
            #endif
        }

        @ViewBuilder
        private var buttonBorder: some View {
            #if os(visionOS)
            Capsule()
                .strokeBorder(borderColor, lineWidth: borderWidth)
            #endif
        }

        #if os(visionOS)
        private var isHighlighted: Bool {
            isFocused || isHovered
        }

        private var borderColor: Color {
            if isHighlighted {
                return Theme.Colors.accent
            }
            if isSelected {
                let opacity = colorSchemeContrast == .increased ? 0.45 : 0.24
                return Theme.Colors.background.opacity(opacity)
            }
            let opacity = colorSchemeContrast == .increased ? 0.9 : 0.55
            return Theme.Colors.textSecondary.opacity(opacity)
        }

        private var borderWidth: CGFloat {
            if isHighlighted {
                return colorSchemeContrast == .increased ? 3.5 : 3
            }
            return isSelected ? 1.5 : 1
        }
        #endif
    }
}

#Preview("Stats range controls") {
    @Previewable @State var selection: StatsRangeSelection = .window(.last7d)

    StatsRangeControls(
        selection: $selection,
        filters: [
            MetricFilter(
                id: "saved-week",
                name: "Last week",
                window: .last7d,
                start: nil,
                end: nil,
                createdAt: .now,
                updatedAt: .now
            ),
            MetricFilter(
                id: "saved-custom",
                name: "Launch weekend",
                window: nil,
                start: Calendar.current.date(byAdding: .day, value: -3, to: .now),
                end: nil,
                createdAt: .now,
                updatedAt: .now
            )
        ],
        onSave: { _ in },
        onDelete: { _ in }
    )
    .padding()
    .background(Theme.Colors.background)
}
