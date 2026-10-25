//
//  BoothStatusLiveStore+Widgets.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

extension BoothStatusLiveStore {
    func writeWidgetSnapshotIfPossible() {
        guard shouldPublishWidgetChanges else { return }
        #if os(macOS)
        guard stats != nil else { return }
        // Do not publish cached UI/socket observations into the Mac widget file.
        // Refresh through the same serialized REST path as the extension instead.
        WidgetRefreshScheduler.refreshForLiveChange()
        #else
        guard let stats else { return }
        let systemEnvelope = self.systemEnvelope
        let componentSources = self.componentSources
        let componentsObservedAt = self.componentsObservedAt
        let systemObservedAt = self.systemObservedAt
        let apiRevision = WidgetRefreshCoordinator.currentAPIRevision
        let observedAt = Date()
        Task {
            await WidgetRefreshCoordinator.shared.apply(
                stats: stats, systemEnvelope: systemEnvelope, components: componentSources,
                systemObservedAt: systemObservedAt, componentsObservedAt: componentsObservedAt,
                apiRevision: apiRevision, observedAt: observedAt
            )
        }
        #endif
    }
}
