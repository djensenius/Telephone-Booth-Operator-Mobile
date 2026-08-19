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

        await model.refreshAll()

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

        await model.refreshAll()

        XCTAssertTrue(model.hasCompletedCurrentWeatherRequest)
        XCTAssertNil(model.currentWeather)
        XCTAssertNotNil(model.currentWeatherError)
        XCTAssertTrue(model.hasCompletedHistoryRequest)
        XCTAssertNil(model.history)
        XCTAssertNotNil(model.historyError)
    }

    @MainActor
    func testCurrentRefreshStartsBothSourcesBeforeEitherCompletes() async {
        let componentRequests = ThermalRequestGate<[SystemComponentCurrentEnvelope]>()
        let systemRequests = ThermalRequestGate<[BoothSystemSnapshotEnvelope]>()
        let component = makeComponent()
        let provider = ClosureThermalsDataProvider(
            components: { await componentRequests.request() },
            systems: { await systemRequests.request() }
        )
        let model = ThermalsViewModel(provider: provider)

        let refresh = Task { @MainActor in await model.refreshCurrent() }
        let startedTogether = await requestsStarted(
            componentRequests,
            and: systemRequests,
            expectedCount: 1
        )

        XCTAssertTrue(startedTogether)
        await componentRequests.resolve(1, with: [component])
        if await systemRequests.startedCount() == 0 {
            _ = await waitForRequests(systemRequests, expectedCount: 1)
        }
        await systemRequests.resolve(1, with: [])
        await refresh.value

        XCTAssertEqual(model.componentSources, [component])
        XCTAssertTrue(model.hasCompletedCurrentRequest)
        XCTAssertFalse(model.isLoadingCurrent)
    }

    @MainActor
    func testOverlappingCurrentRefreshIgnoresStaleCompletion() async {
        let componentRequests = ThermalRequestGate<[SystemComponentCurrentEnvelope]>()
        let systemRequests = ThermalRequestGate<[BoothSystemSnapshotEnvelope]>()
        let provider = ClosureThermalsDataProvider(
            components: { await componentRequests.request() },
            systems: { await systemRequests.request() }
        )
        let model = ThermalsViewModel(provider: provider)

        let firstRefresh = Task { @MainActor in await model.refreshCurrent() }
        let firstRequestsStarted = await requestsStarted(
            componentRequests,
            and: systemRequests,
            expectedCount: 1
        )
        XCTAssertTrue(firstRequestsStarted)

        let secondRefresh = Task { @MainActor in await model.refreshCurrent() }
        let secondRequestsStarted = await requestsStarted(
            componentRequests,
            and: systemRequests,
            expectedCount: 2
        )
        XCTAssertTrue(secondRequestsStarted)

        await componentRequests.resolve(1, with: [makeComponent(temperature: 18)])
        await systemRequests.resolve(1, with: [])
        await firstRefresh.value

        XCTAssertTrue(model.componentSources.isEmpty)
        XCTAssertFalse(model.hasCompletedCurrentRequest)
        XCTAssertTrue(model.isLoadingCurrent)

        let newestComponent = makeComponent(temperature: 24)
        await componentRequests.resolve(2, with: [newestComponent])
        await systemRequests.resolve(2, with: [])
        await secondRefresh.value

        XCTAssertEqual(model.componentSources, [newestComponent])
        XCTAssertTrue(model.hasCompletedCurrentRequest)
        XCTAssertFalse(model.isLoadingCurrent)
    }

    @MainActor
    func testOverlappingDetailRefreshesSupersedeInFlightRequests() async {
        let weatherRequests = ThermalRequestGate<CurrentWeather?>()
        let historyRequests = ThermalRequestGate<ThermalHistoryResponse>()
        let component = makeComponent()
        let provider = ClosureThermalsDataProvider(
            components: { [component] },
            weather: { _ in await weatherRequests.request() },
            history: { _ in await historyRequests.request() }
        )
        let model = ThermalsViewModel(provider: provider)
        await model.refreshCurrent()

        let firstWeather = Task { @MainActor in await model.refreshCurrentWeather() }
        let firstHistory = Task { @MainActor in await model.refreshHistory() }
        _ = await waitForRequests(weatherRequests, expectedCount: 1)
        _ = await waitForRequests(historyRequests, expectedCount: 1)

        let secondWeather = Task { @MainActor in await model.refreshCurrentWeather() }
        let secondHistory = Task { @MainActor in await model.refreshHistory() }
        let weatherCount = await waitForRequests(weatherRequests, expectedCount: 2)
        let historyCount = await waitForRequests(historyRequests, expectedCount: 2)

        XCTAssertEqual(weatherCount, 2)
        XCTAssertEqual(historyCount, 2)

        let newerWeather = makeWeather(temperature: 24)
        let olderWeather = makeWeather(temperature: 18)
        let newerHistory = makeEmptyHistory(
            source: component.source,
            end: Date(timeIntervalSince1970: 1_787_010_000)
        )
        let olderHistory = makeEmptyHistory(
            source: component.source,
            end: Date(timeIntervalSince1970: 1_787_005_000)
        )

        await weatherRequests.resolve(2, with: newerWeather)
        await historyRequests.resolve(2, with: newerHistory)
        await secondWeather.value
        await secondHistory.value
        await weatherRequests.resolve(1, with: olderWeather)
        await historyRequests.resolve(1, with: olderHistory)
        await firstWeather.value
        await firstHistory.value

        XCTAssertEqual(model.currentWeather, newerWeather)
        XCTAssertEqual(model.history, newerHistory)
        XCTAssertTrue(model.hasCompletedCurrentWeatherRequest)
        XCTAssertTrue(model.hasCompletedHistoryRequest)
        XCTAssertFalse(model.isLoadingCurrentWeather)
        XCTAssertFalse(model.isLoadingHistory)
    }

    private func makeEmptyHistory(
        source: SystemComponentSource,
        end: Date = Date(timeIntervalSince1970: 1_787_003_600)
    ) -> ThermalHistoryResponse {
        ThermalHistoryResponse(
            boothId: source.boothId,
            source: source,
            from: Date(timeIntervalSince1970: 1_787_000_000),
            end: end,
            stepSeconds: 300,
            series: []
        )
    }

    private func makeComponent(
        temperature: Double = 42
    ) -> SystemComponentCurrentEnvelope {
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
                battery: .init(temperatureCelsius: temperature)
            )
        )
    }

    private func makeWeather(temperature: Double) -> CurrentWeather {
        CurrentWeather(
            boothId: "booth-a",
            source: "open_meteo",
            temperatureCelsius: temperature,
            relativeHumidityPercent: 50,
            cloudCoverPercent: 10,
            condition: .clearSky,
            observedAt: Date(timeIntervalSince1970: 1_787_003_500),
            fetchedAt: Date(timeIntervalSince1970: 1_787_003_600)
        )
    }

    @MainActor
    private func waitForRequests<Value: Sendable>(
        _ gate: ThermalRequestGate<Value>,
        expectedCount: Int
    ) async -> Int {
        for _ in 0..<1_000 {
            let count = await gate.startedCount()
            if count >= expectedCount { return count }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await gate.startedCount()
    }

    @MainActor
    private func requestsStarted<First: Sendable, Second: Sendable>(
        _ first: ThermalRequestGate<First>,
        and second: ThermalRequestGate<Second>,
        expectedCount: Int
    ) async -> Bool {
        for _ in 0..<1_000 {
            let firstCount = await first.startedCount()
            let secondCount = await second.startedCount()
            if firstCount >= expectedCount, secondCount >= expectedCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
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

private struct ClosureThermalsDataProvider: ThermalsDataProvider {
    let components: @Sendable () async throws -> [SystemComponentCurrentEnvelope]
    let systems: @Sendable () async throws -> [BoothSystemSnapshotEnvelope]
    let weather: @Sendable (String) async throws -> CurrentWeather?
    let history: @Sendable (ThermalHistoryQuery) async throws -> ThermalHistoryResponse

    init(
        components: @escaping @Sendable () async throws
            -> [SystemComponentCurrentEnvelope] = { [] },
        systems: @escaping @Sendable () async throws
            -> [BoothSystemSnapshotEnvelope] = { [] },
        weather: @escaping @Sendable (String) async throws
            -> CurrentWeather? = { _ in nil },
        history: @escaping @Sendable (ThermalHistoryQuery) async throws
            -> ThermalHistoryResponse = { _ in throw ThermalStubError.unavailable }
    ) {
        self.components = components
        self.systems = systems
        self.weather = weather
        self.history = history
    }

    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope] {
        try await components()
    }

    func fetchAllCurrentSystems() async throws -> [BoothSystemSnapshotEnvelope] {
        try await systems()
    }

    func fetchCurrentWeather(boothId: String) async throws -> CurrentWeather? {
        try await weather(boothId)
    }

    func fetchThermalHistory(
        query: ThermalHistoryQuery
    ) async throws -> ThermalHistoryResponse {
        try await history(query)
    }
}

private actor ThermalRequestGate<Value: Sendable> {
    private var requestCount = 0
    private var continuations: [Int: CheckedContinuation<Value, Never>] = [:]

    func request() async -> Value {
        requestCount += 1
        let requestId = requestCount
        return await withCheckedContinuation { continuation in
            continuations[requestId] = continuation
        }
    }

    func startedCount() -> Int {
        requestCount
    }

    func resolve(_ requestId: Int, with value: Value) {
        continuations.removeValue(forKey: requestId)?.resume(returning: value)
    }
}
