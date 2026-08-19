//
//  ThermalsView.swift
//  TelephoneBoothOperatorMobile
//
//  Fleet-aware current thermal readings and historical charts.
//

import Foundation
import Observation
import SwiftUI

#if !os(watchOS) && !os(tvOS)
public struct ThermalsView: View {
    @State private var model: ThermalsViewModel

    public init(client: OperatorClient = .shared) {
        _model = State(initialValue: ThermalsViewModel(client: client))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let currentError = model.currentError, !model.sourceOptions.isEmpty {
                    BannerView(message: currentError, kind: .error)
                }

                if !model.hasCompletedCurrentRequest || model.sourceOptions.isEmpty {
                    currentUnavailableContent
                } else {
                    controlsCard
                    currentReadingsCard
                    currentWeatherContent
                }

                if let historyError = model.historyError, model.history != nil {
                    BannerView(message: historyError, kind: .error)
                }
                historyContent
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.background)
        .autoRefresh(every: .seconds(5)) {
            await model.refreshCurrent()
        }
        .autoRefresh(
            id: CurrentWeatherTaskID(
                sourceId: model.selectedSourceId,
                boothId: model.selectedSource?.boothId
            ),
            every: .seconds(60)
        ) {
            await model.refreshCurrentWeather()
        }
        .autoRefresh(
            id: ThermalHistoryTaskID(sourceId: model.selectedSourceId, range: model.range),
            every: .seconds(60)
        ) {
            await model.refreshHistory()
        }
        .refreshable {
            await model.refreshAll()
        }
    }

    @ViewBuilder
    private var currentUnavailableContent: some View {
        if model.isLoadingCurrent || !model.hasCompletedCurrentRequest {
            ThermalStateCard(
                icon: "thermometer.medium",
                title: "Loading current thermals",
                message: "Checking the Pi and router telemetry sources."
            ) {
                ProgressView()
            }
        } else if let currentError = model.currentError {
            ThermalStateCard(
                icon: "wifi.slash",
                title: "Current thermals unavailable",
                message: currentError
            ) {
                Button("Try Again") {
                    Task { await model.refreshAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
            }
        } else {
            ThermalStateCard(
                icon: "thermometer.medium.slash",
                title: "No thermal sources",
                message: "No booth or router has reported a current thermal snapshot yet."
            ) {
                Button("Try Again") {
                    Task { await model.refreshAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
            }
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            if model.sourceOptions.count > 1 {
                SectionHeader(text: "Source")
                Picker("Thermal source", selection: $model.selectedSourceId) {
                    ForEach(model.sourceOptions) { option in
                        Text(option.pickerLabel).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Booth thermal source")
            } else if let selected = model.selectedSource {
                Label(selected.pickerLabel, systemImage: "server.rack")
                    .font(Theme.Fonts.bodyMedium.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            SectionHeader(text: "Range")
            HStack(spacing: Theme.Spacing.small) {
                ForEach(ThermalRangePreset.allCases) { range in
                    Button {
                        model.range = range
                    } label: {
                        Text(range.rawValue)
                            .font(Theme.Fonts.bodySmall)
                            .fontWeight(model.range == range ? .semibold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.small)
                            .background(
                                (model.range == range
                                    ? Theme.Colors.accent
                                    : Theme.Colors.textSecondary
                                )
                                .opacity(model.range == range ? 0.2 : 0.08),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                model.range == range
                                    ? Theme.Colors.accent
                                    : Theme.Colors.textPrimary
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(range.displayName)
                    .accessibilityAddTraits(model.range == range ? .isSelected : [])
                }
            }
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground()
    }

    private var currentReadingsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(text: "Current readings")
                Spacer(minLength: 0)
                if let selected = model.selectedSource {
                    Text(selected.boothId)
                        .font(Theme.Fonts.caption.monospaced())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            let columns = [GridItem(.adaptive(minimum: 145), spacing: Theme.Spacing.small)]
            LazyVGrid(columns: columns, spacing: Theme.Spacing.small) {
                ThermalSummaryTile(
                    label: "Pi CPU",
                    value: SystemVitals.formatTemperature(model.piTemperature),
                    detail: "Main booth computer",
                    severity: SystemVitals.temperatureSeverity(model.piTemperature)
                )
                ThermalSummaryTile(
                    label: "Router battery",
                    value: SystemVitals.formatTemperature(model.routerBatteryTemperature),
                    detail: model.selectedComponentName ?? "Router source",
                    severity: SystemVitals.temperatureSeverity(model.routerBatteryTemperature)
                )
                ThermalSummaryTile(
                    label: "Hottest router zone",
                    value: SystemVitals.formatTemperature(
                        model.hottestRouterZone?.temperatureCelsius
                    ),
                    detail: model.hottestRouterZone?.name ?? "No zone reading",
                    severity: SystemVitals.temperatureSeverity(
                        model.hottestRouterZone?.temperatureCelsius
                    )
                )
            }

            Text(model.currentFooter)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground()
    }

    @ViewBuilder
    private var currentWeatherContent: some View {
        if let weather = model.currentWeather {
            CurrentWeatherCard(
                weather: weather,
                isRefreshing: model.isLoadingCurrentWeather,
                freshnessLabel: model.currentWeatherFooter
            )
            if let error = model.currentWeatherError {
                BannerView(message: error, kind: .error)
            }
        } else if model.isLoadingCurrentWeather
                    || !model.hasCompletedCurrentWeatherRequest {
            ThermalStateCard(
                icon: "cloud.sun",
                title: "Loading current weather",
                message: "Checking the latest outdoor conditions for this booth."
            ) {
                ProgressView()
            }
        } else {
            ThermalStateCard(
                icon: "cloud.sun.rain",
                title: "Current weather unavailable",
                message: model.currentWeatherError
                    ?? "No current weather reading is available for this booth."
            ) {
                Button("Try Again") {
                    Task { await model.refreshCurrentWeather() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if model.selectedSource != nil,
           model.history == nil,
           model.isLoadingHistory || !model.hasCompletedHistoryRequest {
            ThermalStateCard(
                icon: "chart.xyaxis.line",
                title: "Loading thermal history",
                message: "Fetching \(model.range.displayName.lowercased())."
            ) {
                ProgressView()
            }
        } else if let history = model.history {
            ThermalHistoryCharts(
                history: history,
                range: model.range,
                xDomain: model.historyRange ?? (history.from...history.end)
            )
        } else if let historyError = model.historyError {
            ThermalStateCard(
                icon: "wifi.slash",
                title: "Thermal history unavailable",
                message: historyError
            ) {
                Button("Try Again") {
                    Task { await model.refreshHistory() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
            }
        } else if model.selectedSource != nil {
            ThermalStateCard(
                icon: "chart.xyaxis.line",
                title: "No thermal history",
                message: "No temperature series were returned for this source and range."
            )
        }
    }
}

private struct CurrentWeatherCard: View {
    let weather: CurrentWeather
    let isRefreshing: Bool
    let freshnessLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(text: "Current weather")
                Spacer(minLength: 0)
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing current weather")
                }
            }

            let columns = [GridItem(.adaptive(minimum: 145), spacing: Theme.Spacing.small)]
            LazyVGrid(columns: columns, spacing: Theme.Spacing.small) {
                CurrentWeatherTile(
                    label: "Outdoor temperature",
                    value: SystemVitals.formatTemperature(weather.temperatureCelsius),
                    detail: "Air temperature"
                )
                CurrentWeatherTile(
                    label: "Relative humidity",
                    value: Self.percentLabel(weather.relativeHumidityPercent),
                    detail: "Relative humidity"
                )
                CurrentWeatherTile(
                    label: "Condition",
                    value: weather.condition.displayName,
                    detail: weather.source.replacingOccurrences(of: "_", with: " ").capitalized
                )
                CurrentWeatherTile(
                    label: "Cloud cover",
                    value: Self.percentLabel(weather.cloudCoverPercent),
                    detail: "Sky coverage"
                )
            }

            Text(freshnessLabel)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground()
    }

    private static func percentLabel(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }
}

private struct CurrentWeatherTile: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.headerLarge().monospacedDigit())
                .foregroundStyle(Theme.Colors.info)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Colors.info.opacity(0.08))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value), \(detail)")
    }
}

private struct ThermalSummaryTile: View {
    let label: String
    let value: String
    let detail: String
    let severity: SystemVitals.Severity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.headerLarge().monospacedDigit())
                .foregroundStyle(severity.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(severity.tint.opacity(severity == .nominal ? 0.08 : 0.16))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value), \(detail)")
    }
}

struct ThermalStateCard<Accessory: View>: View {
    let icon: String
    let title: String
    let message: String
    let accessory: Accessory

    init(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(title)
                .font(Theme.Fonts.bodyLarge.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            accessory
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }
}

extension ThermalStateCard where Accessory == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) {
            EmptyView()
        }
    }
}

private struct ThermalHistoryTaskID: Equatable {
    let sourceId: String
    let range: ThermalRangePreset
}

private struct CurrentWeatherTaskID: Equatable {
    let sourceId: String
    let boothId: String?
}
#endif
