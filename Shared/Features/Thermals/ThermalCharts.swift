//
//  ThermalCharts.swift
//  TelephoneBoothOperatorMobile
//
//  Swift Charts rendering for combined and per-sensor thermal history.
//

import Charts
import Foundation
import SwiftUI

#if !os(watchOS) && !os(tvOS)
struct ThermalHistoryCharts: View {
    let history: ThermalHistoryResponse
    let range: ThermalRangePreset

    private var chartData: ThermalChartData {
        ThermalChartData(history: history)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            ThermalChartCard(
                title: "Combined history",
                subtitle: "\(history.source.effectiveDisplayName) · \(range.displayName)",
                series: chartData.series,
                range: range,
                emptyMessage: "No supported thermal series were returned in this range.",
                height: 250
            )

            ThermalSensorDisclosure(
                title: "Pi CPU",
                subtitle: latestLabel(chartData.piCPU),
                series: chartData.piCPU,
                range: range,
                emptyMessage: "No Pi CPU temperature data in this range.",
                isInitiallyExpanded: true,
                paletteOffset: 0
            )

            ThermalSensorDisclosure(
                title: "Router battery",
                subtitle: latestLabel(chartData.routerBattery),
                series: chartData.routerBattery,
                range: range,
                emptyMessage: "No router battery temperature data in this range.",
                isInitiallyExpanded: true,
                paletteOffset: 1
            )

            if chartData.routerZones.isEmpty {
                ThermalSensorDisclosure(
                    title: "Router thermal zones",
                    subtitle: "No zone series",
                    series: [],
                    range: range,
                    emptyMessage: "No router thermal-zone data in this range.",
                    isInitiallyExpanded: false,
                    paletteOffset: 2
                )
            } else {
                ForEach(Array(chartData.routerZones.enumerated()), id: \.element.id) { index, zone in
                    ThermalSensorDisclosure(
                        title: zone.displayName,
                        subtitle: latestLabel([zone]),
                        series: [zone],
                        range: range,
                        emptyMessage: "No samples were returned for this router zone.",
                        isInitiallyExpanded: false,
                        paletteOffset: index + 2
                    )
                }
            }
        }
    }

    private func latestLabel(_ series: [ThermalChartSeries]) -> String {
        guard let latest = series
            .flatMap(\.points)
            .max(by: { $0.timestamp < $1.timestamp }) else {
            return "No samples"
        }
        return "Latest \(SystemVitals.formatTemperature(latest.value))"
    }
}

private struct ThermalSensorDisclosure: View {
    let title: String
    let subtitle: String
    let series: [ThermalChartSeries]
    let range: ThermalRangePreset
    let emptyMessage: String
    let paletteOffset: Int

    @State private var isExpanded: Bool

    init(
        title: String,
        subtitle: String,
        series: [ThermalChartSeries],
        range: ThermalRangePreset,
        emptyMessage: String,
        isInitiallyExpanded: Bool,
        paletteOffset: Int
    ) {
        self.title = title
        self.subtitle = subtitle
        self.series = series
        self.range = range
        self.emptyMessage = emptyMessage
        self.paletteOffset = paletteOffset
        _isExpanded = State(initialValue: isInitiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ThermalLineChart(
                series: series,
                range: range,
                emptyMessage: emptyMessage,
                height: 210,
                paletteOffset: paletteOffset
            )
            .padding(.top, Theme.Spacing.medium)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Fonts.bodyLarge.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .tint(Theme.Colors.accent)
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground()
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

private struct ThermalChartCard: View {
    let title: String
    let subtitle: String
    let series: [ThermalChartSeries]
    let range: ThermalRangePreset
    let emptyMessage: String
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(text: title)
                Text(subtitle)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ThermalLineChart(
                series: series,
                range: range,
                emptyMessage: emptyMessage,
                height: height,
                paletteOffset: 0
            )
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground()
    }
}

private struct ThermalLineChart: View {
    let series: [ThermalChartSeries]
    let range: ThermalRangePreset
    let emptyMessage: String
    let height: CGFloat
    let paletteOffset: Int

    private var populatedSeries: [ThermalChartSeries] {
        series.filter { !$0.points.isEmpty }
    }

    var body: some View {
        if populatedSeries.isEmpty {
            Text(emptyMessage)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Chart {
                    ForEach(Array(populatedSeries.enumerated()), id: \.element.id) { index, item in
                        ForEach(item.points) { point in
                            LineMark(
                                x: .value("Time", point.date),
                                y: .value("Temperature", point.value),
                                series: .value("Sensor", item.id)
                            )
                            .foregroundStyle(ThermalChartPalette.color(at: index + paletteOffset))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)

                            if item.points.count <= 48 {
                                PointMark(
                                    x: .value("Time", point.date),
                                    y: .value("Temperature", point.value)
                                )
                                .foregroundStyle(
                                    ThermalChartPalette.color(at: index + paletteOffset)
                                )
                                .symbolSize(16)
                            }
                        }
                    }
                }
                .frame(height: height)
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.12))
                        AxisTick()
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(date))
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.12))
                        AxisValueLabel {
                            if let temperature = value.as(Double.self) {
                                Text(String(format: "%.0f°", temperature))
                                    .font(Theme.Fonts.caption.monospacedDigit())
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .accessibilityLabel(accessibilitySummary)

                if populatedSeries.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.medium) {
                            ForEach(Array(populatedSeries.enumerated()), id: \.element.id) { index, item in
                                Label {
                                    Text(item.displayName)
                                } icon: {
                                    Circle()
                                        .fill(
                                            ThermalChartPalette.color(
                                                at: index + paletteOffset
                                            )
                                        )
                                        .frame(width: 8, height: 8)
                                }
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = populatedSeries.flatMap(\.points).map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...100
        }
        let padding = max(2, (maximum - minimum) * 0.15)
        let lower = floor((minimum - padding) * 2) / 2
        let upper = ceil((maximum + padding) * 2) / 2
        return lower...(upper > lower ? upper : lower + 4)
    }

    private var accessibilitySummary: String {
        let names = populatedSeries.map(\.displayName).joined(separator: ", ")
        return "Temperature history for \(names), \(range.displayName)"
    }

    private func axisLabel(_ date: Date) -> String {
        switch range {
        case .last6Hours, .last24Hours:
            return date.formatted(.dateTime.hour().minute())
        case .last7Days, .last30Days:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private enum ThermalChartPalette {
    static func color(at index: Int) -> Color {
        switch index % 6 {
        case 0: return Theme.Colors.accent
        case 1: return Theme.Colors.secondary
        case 2: return Theme.Colors.info
        case 3: return Theme.Colors.warning
        case 4: return Theme.Colors.success
        default: return Theme.Colors.error
        }
    }
}
#endif
