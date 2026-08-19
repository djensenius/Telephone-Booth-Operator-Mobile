//
//  ThermalModelsTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class ThermalModelsTests: XCTestCase {
    func testCurrentComponentListDecodesDirectSourceEnvelope() throws {
        let json = """
        {
          "items": [
            {
              "boothId": "booth-a",
              "componentId": "router-a",
              "displayName": "Gallery router",
              "kind": "router",
              "prometheusJob": "glinet",
              "prometheusInstance": "10.0.0.1",
              "capturedAt": "2026-08-18T04:00:00Z",
              "receivedAt": "2026-08-18T04:00:00.125Z",
              "latestSnapshot": {
                "battery": {"temperatureCelsius": 42.5},
                "thermalZones": [
                  {"name": "CPU", "temperatureCelsius": 55.2},
                  {"type": "Wi-Fi", "value": 49.1},
                  {"zone": 2, "temperatureCelsius": 44}
                ]
              }
            }
          ]
        }
        """

        let response = try OperatorJSON.decoder.decode(
            SystemComponentCurrentList.self,
            from: Data(json.utf8)
        )

        let envelope = try XCTUnwrap(response.items.first)
        XCTAssertEqual(envelope.source.boothId, "booth-a")
        XCTAssertEqual(envelope.source.effectiveDisplayName, "Gallery router")
        XCTAssertTrue(envelope.source.isRouter)
        XCTAssertEqual(envelope.latestSnapshot?.battery?.temperatureCelsius, 42.5)
        XCTAssertEqual(envelope.latestSnapshot?.thermalZones.map(\.name), ["CPU", "Wi-Fi", "2"])
        XCTAssertEqual(envelope.latestSnapshot?.hottestThermalZone?.name, "CPU")
        XCTAssertEqual(envelope.freshnessDate, envelope.receivedAt)
        XCTAssertNotNil(envelope.receivedAt)
    }

    func testCurrentComponentListDecodesNestedSourcesAndZoneMap() throws {
        let json = """
        {
          "sources": [
            {
              "source": {
                "boothId": "booth-b",
                "componentId": "router-b",
                "displayName": "Lobby router",
                "kind": "glinet-router",
                "prometheusJob": "router",
                "prometheusInstance": "router-b.local"
              },
              "latestSnapshot": {
                "timestamp": 1787025600,
                "battery": {"temperatureCelsius": "41.75"},
                "thermalZones": {
                  "thermal_zone0": 53.25,
                  "thermal_zone1": {
                    "displayName": "Radio",
                    "temperature": "48.5"
                  }
                }
              }
            }
          ]
        }
        """

        let response = try OperatorJSON.decoder.decode(
            SystemComponentCurrentList.self,
            from: Data(json.utf8)
        )

        let snapshot = try XCTUnwrap(response.items.first?.latestSnapshot)
        XCTAssertEqual(snapshot.battery?.temperatureCelsius, 41.75)
        XCTAssertEqual(snapshot.receivedAt, Date(timeIntervalSince1970: 1_787_025_600))
        XCTAssertEqual(snapshot.thermalZones.map(\.name), ["Radio", "thermal_zone0"])
        XCTAssertEqual(snapshot.hottestThermalZone?.name, "thermal_zone0")
    }

    func testThermalHistoryContractDecodesNumericStringsAndDates() throws {
        let json = """
        {
          "boothId": "booth-a",
          "source": {
            "boothId": "booth-a",
            "componentId": "router-a",
            "displayName": "Gallery router",
            "kind": "router",
            "prometheusJob": "glinet",
            "prometheusInstance": "router-a.local"
          },
          "from": "2026-08-17T04:00:00Z",
          "to": "2026-08-18T04:00:00.000Z",
          "stepSeconds": 300,
          "series": [
            {
              "metric": "booth_cpu_temperature_celsius",
              "labels": {},
              "points": [
                {"timestamp": "1786939200", "value": "48.25"},
                {"timestamp": 1786939500, "value": 49}
              ]
            }
          ]
        }
        """

        let response = try OperatorJSON.decoder.decode(
            ThermalHistoryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.boothId, "booth-a")
        XCTAssertEqual(response.stepSeconds, 300)
        XCTAssertEqual(response.source.displayName, "Gallery router")
        XCTAssertEqual(response.series.first?.points.first?.value, 48.25)
        XCTAssertEqual(response.series.first?.kind, .piCPU)
    }

    func testCurrentWeatherContractDecodesAndFormatsConditionAndFreshness() throws {
        let json = """
        {
          "boothId": "booth-01",
          "source": "open_meteo",
          "temperatureCelsius": 22.2,
          "relativeHumidityPercent": 67,
          "cloudCoverPercent": 0,
          "condition": "partly_cloudy",
          "observedAt": "2026-08-18T14:30:00.000Z",
          "fetchedAt": "2026-08-18T14:31:00.000Z"
        }
        """
        let weather = try OperatorJSON.decoder.decode(
            CurrentWeather.self,
            from: Data(json.utf8)
        )
        let now = Date(timeIntervalSince1970: weather.fetchedAt.timeIntervalSince1970 + 120)

        XCTAssertEqual(weather.boothId, "booth-01")
        XCTAssertEqual(weather.temperatureCelsius, 22.2)
        XCTAssertEqual(weather.relativeHumidityPercent, 67)
        XCTAssertEqual(weather.cloudCoverPercent, 0)
        XCTAssertEqual(weather.condition, .partlyCloudy)
        XCTAssertEqual(weather.condition.displayName, "Partly Cloudy")
        XCTAssertEqual(weather.freshnessLabel(now: now), "Fetched 2m ago · observed 3m ago")
    }

    func testCurrentWeatherConditionPreservesUnknownRawValues() throws {
        let condition = try JSONDecoder().decode(
            CurrentWeatherCondition.self,
            from: Data("\"future_weather\"".utf8)
        )

        XCTAssertEqual(condition, .unknown("future_weather"))
        XCTAssertEqual(condition.rawValue, "future_weather")
        XCTAssertEqual(condition.displayName, "Future Weather")
    }

    func testSeriesClassificationOrderingAndChartPointNormalization() {
        let input = [
            ThermalHistorySeries(
                metric: ThermalMetricName.routerZone,
                labels: ["type": "Wi-Fi", "zone": "thermal_zone1"],
                points: [.init(timestamp: 30, value: 48)]
            ),
            ThermalHistorySeries(
                metric: "future_temperature_metric",
                points: [.init(timestamp: 10, value: 10)]
            ),
            ThermalHistorySeries(
                metric: ThermalMetricName.routerBattery,
                points: [.init(timestamp: 20, value: 42)]
            ),
            ThermalHistorySeries(
                metric: ThermalMetricName.piCPU,
                points: [
                    .init(timestamp: 20, value: 49),
                    .init(timestamp: 10, value: 48),
                    .init(timestamp: 20, value: 50)
                ]
            ),
            ThermalHistorySeries(
                metric: ThermalMetricName.routerZone,
                labels: ["type": "CPU", "zone": "thermal_zone0"],
                points: [.init(timestamp: 30, value: 54)]
            )
        ]

        let chartData = ThermalChartData(series: input)

        XCTAssertEqual(
            chartData.series.map(\.kind),
            [
                .piCPU,
                .routerBattery,
                .routerZone("CPU · thermal_zone0"),
                .routerZone("Wi-Fi · thermal_zone1")
            ]
        )
        XCTAssertEqual(chartData.piCPU.first?.points.map(\.timestamp), [10, 20])
        XCTAssertEqual(chartData.piCPU.first?.points.last?.value, 50)
        XCTAssertEqual(chartData.routerZones.count, 2)
    }

    func testZoneClassificationFallsBackWithoutLabels() {
        let series = ThermalHistorySeries(
            metric: ThermalMetricName.routerZone,
            points: []
        )

        XCTAssertEqual(series.kind, .routerZone("Thermal zone"))
        XCTAssertEqual(series.kind.displayName, "Router thermal zone")
    }

    func testThermalHistoryQueryNormalizesRangeStepAndEncoding() {
        let earlier = Date(timeIntervalSince1970: 1_787_000_000)
        let later = Date(timeIntervalSince1970: 1_787_003_600)
        let query = ThermalHistoryQuery(
            boothId: " booth-a ",
            componentId: " router/a ",
            from: later,
            end: earlier,
            stepSeconds: 2
        )

        XCTAssertEqual(query.boothId, "booth-a")
        XCTAssertEqual(query.from, earlier)
        XCTAssertEqual(query.end, later)
        XCTAssertEqual(query.stepSeconds, 15)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: query.queryItems.map { ($0.name, $0.value) }),
            [
                "boothId": "booth-a",
                "componentId": "router/a",
                "from": OperatorJSON.iso8601String(from: earlier),
                "to": OperatorJSON.iso8601String(from: later),
                "stepSeconds": "15"
            ]
        )
    }

    func testDefaultRangeUsesExactRollingTwentyFourHourBounds() {
        let now = Date(timeIntervalSince1970: 1_787_003_600.375)
        let query = ThermalRangePreset.default.query(boothId: "booth-a", now: now)

        XCTAssertEqual(ThermalRangePreset.default, .last24Hours)
        XCTAssertEqual(query.end, now)
        XCTAssertEqual(query.from, now.addingTimeInterval(-24 * 60 * 60))
        XCTAssertEqual(query.stepSeconds, 300)
    }

    @MainActor
    func testHistoryRangeUsesInjectedCurrentInstant() async throws {
        let now = Date(timeIntervalSince1970: 1_787_003_600.375)
        let model = ThermalsViewModel(client: .demo, now: { now })

        await model.refreshCurrent()
        await model.refreshHistory()

        let historyRange = try XCTUnwrap(model.historyRange)
        XCTAssertEqual(historyRange.lowerBound, now.addingTimeInterval(-24 * 60 * 60))
        XCTAssertEqual(historyRange.upperBound, now)
        XCTAssertEqual(
            historyRange.upperBound.timeIntervalSince(historyRange.lowerBound),
            24 * 60 * 60
        )
    }

    @MainActor
    func testInitialThermalRefreshLoadsDependentDataAfterDiscoveringSource() async {
        let model = ThermalsViewModel(client: .demo)

        XCTAssertFalse(model.hasCompletedCurrentRequest)
        XCTAssertFalse(model.hasCompletedCurrentWeatherRequest)
        XCTAssertFalse(model.hasCompletedHistoryRequest)

        await model.refreshAll()

        XCTAssertTrue(model.hasCompletedCurrentRequest)
        XCTAssertTrue(model.hasCompletedCurrentWeatherRequest)
        XCTAssertTrue(model.hasCompletedHistoryRequest)
        XCTAssertNotNil(model.selectedSource)
        XCTAssertNotNil(model.currentWeather)
        XCTAssertNotNil(model.history)
    }

    @MainActor
    func testAutomaticThermalRefreshLoadsDetailsAndFanAfterDiscoveringSource() async {
        let now = DemoData.sessionAnchor.addingTimeInterval(120)
        let model = ThermalsViewModel(client: .demo, now: { now })

        await model.refreshAutomatically()
        await model.refreshAutomatically()

        XCTAssertTrue(model.hasCompletedCurrentRequest)
        XCTAssertTrue(model.hasCompletedCurrentWeatherRequest)
        XCTAssertTrue(model.hasCompletedHistoryRequest)
        XCTAssertNotNil(model.currentWeather)
        XCTAssertNotNil(model.history)
        XCTAssertNotNil(model.fan)
        XCTAssertEqual(model.fanValue, "67% PWM")
        XCTAssertEqual(model.fanDetail, "On · no tach feedback")
    }

    func testLiveVitalsRouterTemperatureMatchesBoothAndFormatsMissingData() {
        let now = Date(timeIntervalSince1970: 1_787_003_600)
        let sources = [
            makeComponent(
                boothId: "booth-b",
                name: "B router",
                receivedAt: now.addingTimeInterval(-20),
                temperature: 51
            ),
            makeComponent(
                boothId: "booth-a",
                name: "A router",
                receivedAt: now.addingTimeInterval(-30),
                temperature: 43.25
            )
        ]

        XCTAssertEqual(
            SystemVitals.routerBatteryTemperature(
                in: sources,
                boothId: "booth-a",
                now: now
            ),
            43.25
        )
        XCTAssertNil(
            SystemVitals.routerBatteryTemperature(in: sources, boothId: "missing", now: now)
        )
        XCTAssertNil(SystemVitals.routerBatteryTemperature(in: sources, boothId: nil, now: now))
        XCTAssertNil(
            SystemVitals.routerBatteryTemperature(
                in: [
                    makeComponent(
                        boothId: "booth-a",
                        name: "UPS",
                        kind: "ups",
                        prometheusJob: "power",
                        receivedAt: now,
                        temperature: 60
                    )
                ],
                boothId: "booth-a",
                now: now
            )
        )
        XCTAssertNil(
            SystemVitals.routerBatteryTemperature(
                in: [
                    makeComponent(
                        boothId: "booth-a",
                        name: "Stale router",
                        receivedAt: now.addingTimeInterval(-301),
                        temperature: 60
                    )
                ],
                boothId: "booth-a",
                now: now
            )
        )
        XCTAssertEqual(SystemVitals.formatTemperature(43.25), "43.2°C")
        XCTAssertEqual(SystemVitals.formatTemperature(nil), "—")
        XCTAssertEqual(SystemVitals.formatTemperature(.infinity), "—")
    }

    @MainActor
    func testMissingSelectionClearsLoadedHistory() async {
        let model = ThermalsViewModel(client: .demo)
        await model.refreshCurrent()
        await model.refreshHistory()
        XCTAssertNotNil(model.history)

        model.componentSources = []
        model.systemEnvelopes = []
        model.selectedSourceId = ""
        await model.refreshHistory()

        XCTAssertNil(model.history)
        XCTAssertNil(model.historyError)
        XCTAssertFalse(model.isLoadingHistory)
    }

    @MainActor
    func testCurrentWeatherLoadsForSelectionAndClearsWhenSelectionChanges() async {
        let now = DemoData.sessionAnchor.addingTimeInterval(120)
        let model = ThermalsViewModel(client: .demo, now: { now })
        await model.refreshCurrent()
        await model.refreshHistory()
        await model.refreshCurrentWeather()

        XCTAssertNotNil(model.history)
        XCTAssertEqual(model.currentWeather?.boothId, model.selectedSource?.boothId)
        XCTAssertEqual(model.currentWeather?.condition, .clearSky)
        XCTAssertEqual(model.currentWeatherFooter, "Fetched 2m ago · observed 3m ago")

        XCTAssertNotNil(model.currentWeather)
        model.componentSources.append(
            makeComponent(boothId: "booth-second", name: "Second router", temperature: nil)
        )
        model.selectedSourceId = "component:booth-second::booth-second-router"

        XCTAssertNil(model.history)
        XCTAssertNil(model.historyError)
        XCTAssertNil(model.currentWeather)
        XCTAssertNil(model.currentWeatherError)
        await model.refreshCurrentWeather()
        XCTAssertEqual(model.currentWeather?.boothId, "booth-second")
    }

    private func makeComponent(
        boothId: String,
        name: String,
        kind: String = "router",
        prometheusJob: String = "glinet",
        receivedAt: Date? = nil,
        temperature: Double?
    ) -> SystemComponentCurrentEnvelope {
        SystemComponentCurrentEnvelope(
            source: SystemComponentSource(
                boothId: boothId,
                componentId: "\(boothId)-\(kind)",
                displayName: name,
                kind: kind,
                prometheusJob: prometheusJob,
                prometheusInstance: boothId
            ),
            latestSnapshot: SystemComponentSnapshot(
                battery: .init(temperatureCelsius: temperature)
            ),
            capturedAt: receivedAt,
            receivedAt: receivedAt
        )
    }
}
