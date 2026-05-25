//
//  TBOperatorMobileWidgetsBundle.swift
//  TBOperatorMobileWidgets
//
//  Widget bundle for the Telephone-Booth-Operator mobile app. Each widget
//  reads its data from a WidgetSnapshot file written by the main app into
//  a shared App Group container — no auth or network calls happen here.
//

import SwiftUI
import WidgetKit

@main
struct TBOperatorMobileWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BoothStatusWidget()
        PendingModerationWidget()
        CallsTodayWidget()
        #if canImport(ActivityKit)
        CallInProgressLiveActivity()
        #endif
    }
}
