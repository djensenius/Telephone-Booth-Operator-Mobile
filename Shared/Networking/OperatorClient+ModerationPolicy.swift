//
//  OperatorClient+ModerationPolicy.swift
//  TelephoneBoothOperatorMobile
//

extension OperatorClient {
    public func fetchModerationPolicy() async throws -> ModerationPolicy {
        if await usesDemoData { return ModerationPolicyDefaults.fallback }
        return try await get("/v1/moderation-policy")
    }

    public func fetchModerationPolicyWithFallback() async -> ModerationPolicy {
        do {
            return try await fetchModerationPolicy()
        } catch {
            return ModerationPolicyDefaults.fallback
        }
    }
}
