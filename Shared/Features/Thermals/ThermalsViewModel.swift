//
//  ThermalsViewModel.swift
//  TelephoneBoothOperatorMobile
//
//  Main-actor state and request coordination for the shared Thermals tab.
//

import Foundation
import Observation

#if !os(watchOS) && !os(tvOS)
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
    var selectedSourceId = ""
    var range: ThermalRangePreset = .default
    private(set) var history: ThermalHistoryResponse?
    private(set) var currentError: String?
    private(set) var historyError: String?
    private(set) var isLoadingCurrent = false
    private(set) var isLoadingHistory = false

    @ObservationIgnored private let client: OperatorClient
    @ObservationIgnored private var historyGeneration = 0
    @ObservationIgnored private var loadedSelectionId: String?
    @ObservationIgnored private var loadedRange: ThermalRangePreset?

    init(client: OperatorClient) {
        self.client = client
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
        guard let updatedAt = latestCurrentDate else {
            return isLoadingCurrent ? "Refreshing current readings…" : "Awaiting current readings"
        }
        return "Updated " + updatedAt.formatted(date: .omitted, time: .standard)
    }

    func refreshCurrent() async {
        let previousBooth = selectedSource?.boothId
        isLoadingCurrent = true
        defer { isLoadingCurrent = false }
        var messages: [String] = []

        do {
            componentSources = try await client.fetchCurrentSystemComponents()
        } catch {
            messages.append(Self.errorMessage(prefix: "Router readings", error: error))
        }
        do {
            systemEnvelopes = try await client.fetchAllCurrentSystems()
        } catch {
            messages.append(Self.errorMessage(prefix: "Pi readings", error: error))
        }

        normalizeSelection(preferredBooth: previousBooth)
        currentError = messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    func refreshHistory() async {
        guard let selectedSource else { return }
        historyGeneration += 1
        let generation = historyGeneration
        let requestedSelectionId = selectedSourceId
        let requestedRange = range
        if loadedSelectionId != requestedSelectionId || loadedRange != requestedRange {
            history = nil
            historyError = nil
        }
        isLoadingHistory = true
        defer {
            if generation == historyGeneration {
                isLoadingHistory = false
            }
        }

        do {
            let result = try await client.fetchThermalHistory(
                query: requestedRange.query(boothId: selectedSource.boothId)
            )
            guard !Task.isCancelled,
                  generation == historyGeneration,
                  selectedSourceId == requestedSelectionId,
                  range == requestedRange else {
                return
            }
            history = result
            loadedSelectionId = requestedSelectionId
            loadedRange = requestedRange
            historyError = nil
        } catch {
            guard !Task.isCancelled, generation == historyGeneration else { return }
            historyError = Self.errorMessage(prefix: "Thermal history", error: error)
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

    private var latestCurrentDate: Date? {
        [selectedSystemEnvelope?.receivedAt, selectedComponentEnvelope?.latestSnapshot?.receivedAt]
            .compactMap(\.self)
            .max()
    }

    private func normalizeSelection(preferredBooth: String?) {
        let options = sourceOptions
        guard !options.isEmpty else {
            selectedSourceId = ""
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
}
#endif
