//
//  WidgetFetchResult.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

enum WidgetFetchResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
}

func captureWidgetFetch<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) async -> WidgetFetchResult<Value> {
    do {
        return .success(try await operation())
    } catch is CancellationError {
        return .failure("cancelled")
    } catch {
        return .failure(error.localizedDescription)
    }
}
