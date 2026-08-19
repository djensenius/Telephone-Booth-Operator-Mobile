//
//  ThermalsViewModel.swift
//  TelephoneBoothOperatorMobile
//
//  Main-actor state and request coordination for the shared Thermals tab.
//

import Foundation
import Observation

#if !os(watchOS) && !os(tvOS)
protocol ThermalsDataProvider: Sendable {
    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope]
    func fetchAllCurrentSystems() async throws -> [BoothSystemSnapshotEnvelope]
    func fetchCurrentWeather(boothId: String) async throws -> CurrentWeather?
    func fetchThermalHistory(query: ThermalHistoryQuery) async throws -> ThermalHistoryResponse
}

extension OperatorClient: ThermalsDataProvider {}

struct ThermalSourceOption: Sendable, Hashable, Identifiable {
    let id: String
    let boothId: String
    let name: String
    let componentEnvelopeId: String?

    var pickerLabel: String {
        name == boothId ? name : "\(name) · \(boothId)"
    }
}

@MainActor
@Observable
final class ThermalsViewModel {
    var componentSources: [SystemComponentCurrentEnvelope] = []
    var systemEnvelopes: [BoothSystemSnapshotEnvelope] = []
    var selectedSourceId = "" {
        didSet {
            if oldValue != selectedSourceId {
                clearHistory()
                clearCurrentWeather()
            }
        }
    }
    var range: ThermalRangePreset = .default {
        didSet {
            if oldValue != range {
                clearHistory()
            }
        }
    }
    private(set) var history: ThermalHistoryResponse?
    private(set) var historyRange: ClosedRange<Date>?
    private(set) var currentWeather: CurrentWeather?
    private(set) var currentError: String?
    private(set) var currentWeatherError: String?
    private(set) var historyError: String?
    private(set) var hasCompletedCurrentRequest = false
    private(set) var hasCompletedCurrentWeatherRequest = false
    private(set) var hasCompletedHistoryRequest = false
    private(set) var isLoadingCurrent = false
    private(set) var isLoadingCurrentWeather = false
    private(set) var isLoadingHistory = false

    @ObservationIgnored private let provider: any ThermalsDataProvider
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var historyGeneration = 0
    @ObservationIgnored private var weatherGeneration = 0
    @ObservationIgnored private var loadedSelectionId: String?
    @ObservationIgnored private var loadedRange: ThermalRangePreset?

    init(
        client: OperatorClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        provider = client
        self.now = now
    }

    init(
        provider: any ThermalsDataProvider,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.now = now
    }

    var currentWeatherFooter: String {
        currentWeather?.freshnessLabel(now: now()) ?? (
            isLoadingCurrentWeather ? "Refreshing current weather…" : "Awaiting current weather"
        )
    }

    var sourceOptions: [ThermalSourceOption] {
        var options = componentSources.map { envelope in
            ThermalSourceOption(
                id: "component:\(envelope.id)",
                boothId: envelope.source.boothId,
                name: envelope.source.effectiveDisplayName,
                componentEnvelopeId: envelope.id
            )
        }
        let componentBooths = Set(options.map(\.boothId))
        options.append(contentsOf: systemEnvelopes.compactMap { envelope in
            guard !componentBooths.contains(envelope.boothId) else { return nil }
            return ThermalSourceOption(
                id: "booth:\(envelope.boothId)",
                boothId: envelope.boothId,
                name: "Booth \(envelope.boothId)",
                componentEnvelopeId: nil
            )
        })
        return options.sorted(by: Self.sourceOptionOrder)
    }

    var selectedSource: ThermalSourceOption? {
        sourceOptions.first(where: { $0.id == selectedSourceId })
    }

    var piTemperature: Double? {
        selectedSystemEnvelope?.snapshot.cpuTemperatureCelsius
    }

    var routerBatteryTemperature: Double? {
        selectedComponentEnvelope?.latestSnapshot?.battery?.temperatureCelsius
    }

    var hottestRouterZone: SystemComponentSnapshot.ThermalZone? {
        selectedComponentEnvelope?.latestSnapshot?.hottestThermalZone
    }

    var selectedComponentName: String? {
        selectedComponentEnvelope?.source.effectiveDisplayName
    }

    var currentFooter: String {
        let piUpdatedAt = selectedSystemEnvelope?.receivedAt
        let routerUpdatedAt = selectedComponentEnvelope?.freshnessDate
        switch (piUpdatedAt, routerUpdatedAt) {
        case (.some(let piDate), .some(let routerDate)):
            return "Pi updated \(Self.formattedTime(piDate)) · "
                + "Router updated \(Self.formattedTime(routerDate))"
        case (.some(let piDate), .none):
            return "Pi updated \(Self.formattedTime(piDate))"
        case (.none, .some(let routerDate)):
            return "Router updated \(Self.formattedTime(routerDate))"
        case (.none, .none):
            return isLoadingCurrent ? "Refreshing current readings…" : "Awaiting current readings"
        }
    }

    func refreshCurrentAndLoadDetailsIfNeeded() async {
        await refreshCurrent()
        await refreshDetails(force: false)
    }

    func refreshAll() async {
        await refreshCurrent()
        await refreshDetails(force: true)
    }

    func refreshCurrent() async {
        let previousBooth = selectedSource?.boothId
        isLoadingCurrent = true
        defer { isLoadingCurrent = false }
        var messages: [String] = []

        do {
            componentSources = try await provider.fetchCurrentSystemComponents()
        } catch {
            messages.append(Self.errorMessage(prefix: "Router readings", error: error))
        }
        do {
            systemEnvelopes = try await provider.fetchAllCurrentSystems()
        } catch {
            messages.append(Self.errorMessage(prefix: "Pi readings", error: error))
        }

        guard !Task.isCancelled else { return }
        normalizeSelection(preferredBooth: previousBooth)
        currentError = messages.isEmpty ? nil : messages.joined(separator: " ")
        hasCompletedCurrentRequest = true
    }

    func refreshCurrentWeather() async {
        guard let selectedSource else {
            clearCurrentWeather()
            return
        }
        guard !isLoadingCurrentWeather else { return }
        weatherGeneration += 1
        let generation = weatherGeneration
        let requestedSelectionId = selectedSourceId
        let requestedBoothId = selectedSource.boothId
        isLoadingCurrentWeather = true
        defer {
            if generation == weatherGeneration {
                isLoadingCurrentWeather = false
            }
        }

        do {
            let result = try await provider.fetchCurrentWeather(boothId: requestedBoothId)
            guard !Task.isCancelled,
                  generation == weatherGeneration,
                  selectedSourceId == requestedSelectionId,
                  self.selectedSource?.boothId == requestedBoothId else {
                return
            }
            currentWeather = result
            currentWeatherError = nil
            hasCompletedCurrentWeatherRequest = true
        } catch {
            guard !Task.isCancelled,
                  generation == weatherGeneration,
                  selectedSourceId == requestedSelectionId,
                  self.selectedSource?.boothId == requestedBoothId else {
                return
            }
            currentWeatherError = Self.errorMessage(prefix: "Current weather", error: error)
            hasCompletedCurrentWeatherRequest = true
        }
    }

    func refreshHistory() async {
        guard let selectedSource else {
            clearHistory()
            return
        }
        guard !isLoadingHistory else { return }
        historyGeneration += 1
        let generation = historyGeneration
        let requestedSelectionId = selectedSourceId
        let requestedRange = range
        let requestedQuery = requestedRange.query(
            boothId: selectedSource.boothId,
            componentId: selectedComponentEnvelope?.source.componentId,
            now: now()
        )
        if loadedSelectionId != requestedSelectionId || loadedRange != requestedRange {
            history = nil
            historyRange = nil
            historyError = nil
        }
        isLoadingHistory = true
        defer {
            if generation == historyGeneration {
                isLoadingHistory = false
            }
        }

        do {
            let result = try await provider.fetchThermalHistory(query: requestedQuery)
            guard !Task.isCancelled,
                  generation == historyGeneration,
                  selectedSourceId == requestedSelectionId,
                  range == requestedRange else {
                return
            }
            history = result
            historyRange = requestedQuery.from...requestedQuery.end
            loadedSelectionId = requestedSelectionId
            loadedRange = requestedRange
            historyError = nil
            hasCompletedHistoryRequest = true
        } catch {
            guard !Task.isCancelled,
                  generation == historyGeneration,
                  selectedSourceId == requestedSelectionId,
                  range == requestedRange else {
                return
            }
            historyError = Self.errorMessage(prefix: "Thermal history", error: error)
            hasCompletedHistoryRequest = true
        }
    }

    private func refreshDetails(force: Bool) async {
        guard !Task.isCancelled, selectedSource != nil else { return }
        if force || !hasCompletedCurrentWeatherRequest {
            await refreshCurrentWeather()
        }
        guard !Task.isCancelled else { return }
        if force || !hasCompletedHistoryRequest {
            await refreshHistory()
        }
    }

    private var selectedSystemEnvelope: BoothSystemSnapshotEnvelope? {
        guard let boothId = selectedSource?.boothId else { return nil }
        return systemEnvelopes
            .filter { $0.boothId == boothId }
            .max { $0.receivedAt < $1.receivedAt }
    }

    private var selectedComponentEnvelope: SystemComponentCurrentEnvelope? {
        guard let selectedSource else { return nil }
        if let componentEnvelopeId = selectedSource.componentEnvelopeId {
            return componentSources.first(where: { $0.id == componentEnvelopeId })
        }
        return componentSources.first(where: { $0.source.boothId == selectedSource.boothId })
    }

    private func normalizeSelection(preferredBooth: String?) {
        let options = sourceOptions
        guard !options.isEmpty else {
            selectedSourceId = ""
            clearHistory()
            clearCurrentWeather()
            return
        }
        if options.contains(where: { $0.id == selectedSourceId }) { return }
        selectedSourceId = options.first(where: { $0.boothId == preferredBooth })?.id
            ?? options[0].id
    }

    private static func sourceOptionOrder(
        _ lhs: ThermalSourceOption,
        _ rhs: ThermalSourceOption
    ) -> Bool {
        let boothOrder = lhs.boothId.localizedCaseInsensitiveCompare(rhs.boothId)
        if boothOrder != .orderedSame { return boothOrder == .orderedAscending }
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func errorMessage(prefix: String, error: Error) -> String {
        if case OperatorError.transport(let inner) = error,
           let urlError = inner as? URLError,
           [
               URLError.notConnectedToInternet,
               .networkConnectionLost,
               .cannotConnectToHost,
               .timedOut
           ].contains(urlError.code) {
            return "\(prefix) unavailable while offline."
        }
        return "\(prefix) couldn't load: \(error.localizedDescription)"
    }

    private static func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    private func clearHistory() {
        historyGeneration += 1
        history = nil
        historyRange = nil
        historyError = nil
        loadedSelectionId = nil
        loadedRange = nil
        hasCompletedHistoryRequest = false
        isLoadingHistory = false
    }

    private func clearCurrentWeather() {
        weatherGeneration += 1
        currentWeather = nil
        currentWeatherError = nil
        hasCompletedCurrentWeatherRequest = false
        isLoadingCurrentWeather = false
    }
}
#endif
