//
//  NotificationVisibilityModifier.swift
//  TelephoneBoothOperatorMobile
//

import SwiftUI

private struct NotificationVisibilityModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.automaticRefreshEnabled) private var automaticRefreshEnabled
    @State private var scopeId = UUID()

    let scope: DeliveredNotificationScope?

    func body(content: Content) -> some View {
        content
            .onAppear { updateVisibility() }
            .onDisappear { NotificationManager.shared.markNotificationScopeHidden(id: scopeId) }
            .onChange(of: scenePhase) { updateVisibility() }
            .onChange(of: automaticRefreshEnabled) { updateVisibility() }
            .onChange(of: scope) { updateVisibility() }
    }

    private func updateVisibility() {
        guard scenePhase == .active, automaticRefreshEnabled, let scope else {
            NotificationManager.shared.markNotificationScopeHidden(id: scopeId)
            return
        }
        NotificationManager.shared.markNotificationScopeVisible(scope, id: scopeId)
    }
}

extension View {
    func notificationVisibilityScope(_ scope: DeliveredNotificationScope?) -> some View {
        modifier(NotificationVisibilityModifier(scope: scope))
    }
}
