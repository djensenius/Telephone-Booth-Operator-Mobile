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
                Button {
                    selection = .window(option)
                } label: {
                    Text(option.shortLabel)
                        .font(Theme.Fonts.bodySmall)
                        .fontWeight(selectedPreset == option ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.small)
                        .background(
                            (selectedPreset == option ? Theme.Colors.accent : Theme.Colors.textSecondary)
                                .opacity(selectedPreset == option ? 0.2 : 0.08),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            selectedPreset == option ? Theme.Colors.accent : Theme.Colors.textPrimary
                        )
                }
                .buttonStyle(.plain)
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
                Button("Apply custom range") { applyCustomRange() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
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
