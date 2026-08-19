//
//  TVThermalsView.swift
//  TelephoneBoothOperatorMobile
//
//  Ten-foot thermal telemetry dashboard for tvOS.
//

#if os(tvOS)

import Charts
import Foundation
import SwiftUI

struct TVThermalsView: View {
    @State private var model: ThermalsViewModel

    init(client: OperatorClient = .shared) {
        _model = State(initialValue: ThermalsViewModel(client: client))
    }

    var body: some View {
        TVScreen(
            title: "Thermals",
            systemImage: "thermometer.variable.and.figure",
            accessory: { sourceAccessory },
            content: {
                sourceSelector
                rangeSelector

                if let error = model.currentError, !model.sourceOptions.isEmpty {
                    TVBanner(message: error)
                }

                if !model.hasCompletedCurrentRequest || model.sourceOptions.isEmpty {
                    currentUnavailable
                } else {
                    currentReadings
                    weatherContent
                }

                if let error = model.historyError, model.history != nil {
                    TVBanner(message: error)
                }
                historyContent
            }
        )
        .autoRefresh(every: .seconds(5)) {
            await model.refreshCurrent()
        }
        .autoRefresh(
            id: TVCurrentWeatherTaskID(
                sourceId: model.selectedSourceId,
                boothId: model.selectedSource?.boothId
            ),
            every: .seconds(60)
        ) {
            await model.refreshCurrentWeather()
        }
        .autoRefresh(
            id: TVThermalHistoryTaskID(
                sourceId: model.selectedSourceId,
                range: model.range
            ),
            every: .seconds(60)
        ) {
            await model.refreshHistory()
        }
    }

    @ViewBuilder
    private var sourceAccessory: some View {
        if let source = model.selectedSource {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Source")
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(source.boothId)
                    .font(.system(size: 30, weight: .semibold).monospaced())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    @ViewBuilder
    private var sourceSelector: some View {
        if model.sourceOptions.count > 1 {
            Menu {
                ForEach(model.sourceOptions) { option in
                    Button {
                        model.selectedSourceId = option.id
                    } label: {
                        if model.selectedSourceId == option.id {
                            Label(option.pickerLabel, systemImage: "checkmark")
                        } else {
                            Text(option.pickerLabel)
                        }
                    }
                }
            } label: {
                Label(
                    model.selectedSource?.pickerLabel ?? "Choose thermal source",
                    systemImage: "server.rack"
                )
                .font(.system(size: 30, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            }
            .buttonStyle(TVSegmentButtonStyle(isSelected: false))
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 20) {
            ForEach(ThermalRangePreset.allCases) { range in
                Button {
                    model.range = range
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 30, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                }
                .buttonStyle(TVSegmentButtonStyle(isSelected: model.range == range))
                .accessibilityLabel(range.displayName)
                .accessibilityAddTraits(model.range == range ? [.isSelected] : [])
            }
        }
    }

    private var currentUnavailable: some View {
        TVFocusCard {
            HStack(spacing: 22) {
                if model.isLoadingCurrent || !model.hasCompletedCurrentRequest {
                    ProgressView()
                } else {
                    Image(systemName: "thermometer.medium.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentUnavailableTitle)
                        .font(TVMetrics.Font.cardTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(currentUnavailableMessage)
                        .font(TVMetrics.Font.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var currentUnavailableTitle: String {
        if model.isLoadingCurrent || !model.hasCompletedCurrentRequest {
            return "Loading current thermals"
        }
        return model.currentError == nil ? "No thermal sources" : "Thermals unavailable"
    }

    private var currentUnavailableMessage: String {
        if let error = model.currentError {
            return error
        }
        return model.hasCompletedCurrentRequest
            ? "No booth or router has reported a current thermal snapshot yet."
            : "Checking Pi and router telemetry sources."
    }

    private var currentReadings: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 24) {
                TVCardHeader(title: "Current readings", systemImage: "thermometer.medium")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
                    spacing: 20
                ) {
                    TVStatTile(
                        label: "Pi CPU",
                        value: SystemVitals.formatTemperature(model.piTemperature),
                        tint: SystemVitals.temperatureSeverity(model.piTemperature).tint,
                        caption: "Main booth computer"
                    )
                    TVStatTile(
                        label: "Router battery",
                        value: SystemVitals.formatTemperature(model.routerBatteryTemperature),
                        tint: SystemVitals.temperatureSeverity(
                            model.routerBatteryTemperature
                        ).tint,
                        caption: model.selectedComponentName ?? "Router source"
                    )
                    TVStatTile(
                        label: "Hottest router zone",
                        value: SystemVitals.formatTemperature(
                            model.hottestRouterZone?.temperatureCelsius
                        ),
                        tint: SystemVitals.temperatureSeverity(
                            model.hottestRouterZone?.temperatureCelsius
                        ).tint,
                        caption: model.hottestRouterZone?.name ?? "No zone reading"
                    )
                }
                Text(model.currentFooter)
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var weatherContent: some View {
        if let weather = model.currentWeather {
            TVFocusCard {
                VStack(alignment: .leading, spacing: 24) {
                    TVCardHeader(title: "Current weather", systemImage: "cloud.sun")
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 20),
                            count: 4
                        ),
                        spacing: 20
                    ) {
                        TVStatTile(
                            label: "Outdoor",
                            value: SystemVitals.formatTemperature(
                                weather.temperatureCelsius
                            )
                        )
                        TVStatTile(
                            label: "Humidity",
                            value: percent(weather.relativeHumidityPercent)
                        )
                        TVStatTile(label: "Condition", value: weather.condition.displayName)
                        TVStatTile(
                            label: "Cloud cover",
                            value: percent(weather.cloudCoverPercent)
                        )
                    }
                    Text(model.currentWeatherFooter)
                        .font(TVMetrics.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let error = model.currentWeatherError {
                TVBanner(message: error)
            }
        } else {
            TVFocusCard {
                HStack(spacing: 22) {
                    if model.isLoadingCurrentWeather
                        || !model.hasCompletedCurrentWeatherRequest {
                        ProgressView()
                    } else {
                        Image(systemName: "cloud.sun.rain")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text(
                        model.currentWeatherError
                            ?? "No current weather reading is available for this booth."
                    )
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let history = model.history {
            TVThermalHistoryCard(
                history: history,
                range: model.range,
                xDomain: model.historyRange ?? (history.from...history.end)
            )
        } else if model.selectedSource != nil {
            TVFocusCard {
                HStack(spacing: 22) {
                    if model.isLoadingHistory || !model.hasCompletedHistoryRequest {
                        ProgressView()
                    } else {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            model.historyError == nil
                                ? "Loading thermal history"
                                : "Thermal history unavailable"
                        )
                        .font(TVMetrics.Font.cardTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        Text(
                            model.historyError
                                ?? "Fetching \(model.range.displayName.lowercased())."
                        )
                        .font(TVMetrics.Font.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }
}

private struct TVThermalHistoryCard: View {
    let history: ThermalHistoryResponse
    let range: ThermalRangePreset
    let xDomain: ClosedRange<Date>

    private var chartData: ThermalChartData {
        ThermalChartData(history: history)
    }

    var body: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 24) {
                TVCardHeader(title: "Thermal history", systemImage: "chart.xyaxis.line")
                Text("\(history.source.effectiveDisplayName) · \(range.displayName)")
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if chartData.series.allSatisfy({ $0.points.isEmpty }) {
                    Text("No supported thermal series were returned in this range.")
                        .font(TVMetrics.Font.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart {
                        ForEach(
                            Array(chartData.series.enumerated()),
                            id: \.element.id
                        ) { index, series in
                            ForEach(series.points) { point in
                                LineMark(
                                    x: .value("Time", point.date),
                                    y: .value("Temperature", point.value),
                                    series: .value("Sensor", series.id)
                                )
                                .foregroundStyle(color(at: index))
                                .lineStyle(
                                    StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                    .frame(height: 380)
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: yDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisGridLine()
                                .foregroundStyle(
                                    Theme.Colors.textSecondary.opacity(0.15)
                                )
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(axisLabel(date))
                                        .font(TVMetrics.Font.caption)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                                .foregroundStyle(
                                    Theme.Colors.textSecondary.opacity(0.15)
                                )
                            AxisValueLabel {
                                if let temperature = value.as(Double.self) {
                                    Text(String(format: "%.0f°", temperature))
                                        .font(TVMetrics.Font.caption.monospacedDigit())
                                }
                            }
                        }
                    }

                    HStack(spacing: 28) {
                        ForEach(
                            Array(chartData.series.enumerated()),
                            id: \.element.id
                        ) { index, series in
                            Label {
                                Text(series.displayName)
                            } icon: {
                                Circle()
                                    .fill(color(at: index))
                                    .frame(width: 14, height: 14)
                            }
                            .font(TVMetrics.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = chartData.series.flatMap(\.points).map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...100
        }
        let padding = max(2, (maximum - minimum) * 0.15)
        let lower = floor((minimum - padding) * 2) / 2
        let upper = ceil((maximum + padding) * 2) / 2
        return lower...(upper > lower ? upper : lower + 4)
    }

    private func axisLabel(_ date: Date) -> String {
        switch range {
        case .last6Hours, .last24Hours:
            date.formatted(.dateTime.hour().minute())
        case .last7Days, .last30Days:
            date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func color(at index: Int) -> Color {
        switch index % 6 {
        case 0: Theme.Colors.accent
        case 1: Theme.Colors.secondary
        case 2: Theme.Colors.info
        case 3: Theme.Colors.warning
        case 4: Theme.Colors.success
        default: Theme.Colors.error
        }
    }
}

private struct TVThermalHistoryTaskID: Equatable {
    let sourceId: String
    let range: ThermalRangePreset
}

private struct TVCurrentWeatherTaskID: Equatable {
    let sourceId: String
    let boothId: String?
}

#Preview {
    TVThermalsView(client: .demo)
}

#endif
