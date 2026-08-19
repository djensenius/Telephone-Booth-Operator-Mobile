//
//  ThermalClientTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class ThermalClientTests: XCTestCase {
    func testCurrentComponentsEndpointPath() throws {
        let request = ThermalEndpoint.currentComponents
        let url = try request.url(relativeTo: URL(string: "https://operator.example")!)

        XCTAssertEqual(request.path, "/v1/system/components/current")
        XCTAssertTrue(request.queryItems.isEmpty)
        XCTAssertEqual(url.absoluteString, "https://operator.example/v1/system/components/current")
    }

    func testCurrentWeatherEndpointBuildsExpectedURLAndQuery() throws {
        let request = try ThermalEndpoint.currentWeather(boothId: " booth id/01 ")
        let url = try request.url(relativeTo: URL(string: "https://operator.example")!)
        let queryItems = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )

        XCTAssertEqual(request.path, "/v1/system/weather/current")
        XCTAssertEqual(queryItems.map(\.name), ["boothId"])
        XCTAssertEqual(queryItems.first?.value, "booth id/01")
        XCTAssertEqual(url.path, "/v1/system/weather/current")
    }

    func testCurrentWeatherEndpointRejectsBlankBooth() {
        XCTAssertThrowsError(try ThermalEndpoint.currentWeather(boothId: "  ")) { error in
            guard case OperatorError.invalidURL = error else {
                return XCTFail("Expected OperatorError.invalidURL, got \(error)")
            }
        }
    }

    func testThermalHistoryEndpointBuildsExpectedURLAndQuery() throws {
        let from = Date(timeIntervalSince1970: 1_786_968_000)
        let end = Date(timeIntervalSince1970: 1_787_054_400)
        let query = ThermalHistoryQuery(
            boothId: "booth id/with spaces",
            componentId: "router/main",
            from: from,
            end: end,
            stepSeconds: 1
        )

        let request = try ThermalEndpoint.history(query: query)
        let url = try request.url(relativeTo: URL(string: "https://operator.example/base")!)
        let queryItems = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(url.path, "/base/v1/system/thermals/history")
        XCTAssertEqual(values["boothId"], "booth id/with spaces")
        XCTAssertEqual(values["componentId"], "router/main")
        XCTAssertEqual(values["from"], OperatorJSON.iso8601String(from: from))
        XCTAssertEqual(values["to"], OperatorJSON.iso8601String(from: end))
        XCTAssertEqual(values["stepSeconds"], "15")
        XCTAssertTrue(url.absoluteString.contains("booth%20id/with%20spaces"))
    }

    func testThermalHistoryEndpointRejectsBlankBooth() {
        let query = ThermalHistoryQuery(
            boothId: "   ",
            from: Date(timeIntervalSince1970: 1),
            end: Date(timeIntervalSince1970: 2),
            stepSeconds: 15
        )

        XCTAssertThrowsError(try ThermalEndpoint.history(query: query)) { error in
            guard case OperatorError.invalidURL = error else {
                return XCTFail("Expected OperatorError.invalidURL, got \(error)")
            }
        }
    }
}

final class ThermalsViewModelStateTests: XCTestCase {
    @MainActor
    func testFailedCurrentRefreshCompletesWithErrorInsteadOfEmptyState() async {
        let provider = StubThermalsDataProvider(
            components: .failure(.unavailable),
            systems: .failure(.unavailable)
        )
        let model = ThermalsViewModel(provider: provider)

        await model.refreshCurrent()

        XCTAssertTrue(model.hasCompletedCurrentRequest)
        XCTAssertTrue(model.sourceOptions.isEmpty)
        XCTAssertNotNil(model.currentError)
    }

    @MainActor
    func testEmptyCurrentRefreshCompletesWithoutError() async {
        let model = ThermalsViewModel(provider: StubThermalsDataProvider())

        await model.refreshCurrent()

        XCTAssertTrue(model.hasCompletedCurrentRequest)
        XCTAssertTrue(model.sourceOptions.isEmpty)
        XCTAssertNil(model.currentError)
    }

    @MainActor
    func testNotFoundWeatherAndEmptyHistoryCompleteWithoutErrors() async {
        let component = makeComponent()
        let history = makeEmptyHistory(source: component.source)
        let provider = StubThermalsDataProvider(
            components: .success([component]),
            weather: .success(nil),
            history: .success(history)
        )
        let model = ThermalsViewModel(provider: provider)

        await model.refreshCurrentAndLoadDetailsIfNeeded()

        XCTAssertTrue(model.hasCompletedCurrentWeatherRequest)
        XCTAssertNil(model.currentWeather)
        XCTAssertNil(model.currentWeatherError)
        XCTAssertTrue(model.hasCompletedHistoryRequest)
        XCTAssertEqual(model.history, history)
        XCTAssertNil(model.historyError)
    }

    @MainActor
    func testWeatherAndHistoryFailuresCompleteWithErrors() async {
        let provider = StubThermalsDataProvider(
            components: .success([makeComponent()]),
            weather: .failure(.unavailable),
            history: .failure(.unavailable)
        )
        let model = ThermalsViewModel(provider: provider)

        await model.refreshCurrentAndLoadDetailsIfNeeded()

        XCTAssertTrue(model.hasCompletedCurrentWeatherRequest)
        XCTAssertNil(model.currentWeather)
        XCTAssertNotNil(model.currentWeatherError)
        XCTAssertTrue(model.hasCompletedHistoryRequest)
        XCTAssertNil(model.history)
        XCTAssertNotNil(model.historyError)
    }

    private func makeEmptyHistory(
        source: SystemComponentSource
    ) -> ThermalHistoryResponse {
        ThermalHistoryResponse(
            boothId: source.boothId,
            source: source,
            from: Date(timeIntervalSince1970: 1_787_000_000),
            end: Date(timeIntervalSince1970: 1_787_003_600),
            stepSeconds: 300,
            series: []
        )
    }

    private func makeComponent() -> SystemComponentCurrentEnvelope {
        SystemComponentCurrentEnvelope(
            source: SystemComponentSource(
                boothId: "booth-a",
                componentId: "router-a",
                displayName: "Gallery router",
                kind: "router",
                prometheusJob: "glinet",
                prometheusInstance: "booth-a"
            ),
            latestSnapshot: SystemComponentSnapshot(
                battery: .init(temperatureCelsius: 42)
            )
        )
    }
}

private enum ThermalStubError: Error, Sendable {
    case unavailable
}

private struct StubThermalsDataProvider: ThermalsDataProvider {
    let components: Result<[SystemComponentCurrentEnvelope], ThermalStubError>
    let systems: Result<[BoothSystemSnapshotEnvelope], ThermalStubError>
    let weather: Result<CurrentWeather?, ThermalStubError>
    let history: Result<ThermalHistoryResponse, ThermalStubError>

    init(
        components: Result<
            [SystemComponentCurrentEnvelope],
            ThermalStubError
        > = .success([]),
        systems: Result<
            [BoothSystemSnapshotEnvelope],
            ThermalStubError
        > = .success([]),
        weather: Result<CurrentWeather?, ThermalStubError> = .success(nil),
        history: Result<
            ThermalHistoryResponse,
            ThermalStubError
        > = .failure(.unavailable)
    ) {
        self.components = components
        self.systems = systems
        self.weather = weather
        self.history = history
    }

    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope] {
        try components.get()
    }

    func fetchAllCurrentSystems() async throws -> [BoothSystemSnapshotEnvelope] {
        try systems.get()
    }

    func fetchCurrentWeather(boothId: String) async throws -> CurrentWeather? {
        try weather.get()
    }

    func fetchThermalHistory(
        query: ThermalHistoryQuery
    ) async throws -> ThermalHistoryResponse {
        try history.get()
    }
}
