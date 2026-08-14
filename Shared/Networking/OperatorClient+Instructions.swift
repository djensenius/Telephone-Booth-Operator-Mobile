//
//  OperatorClient+Instructions.swift
//  TelephoneBoothOperatorMobile
//
//  Admin management for the global pool of instruction recordings.
//

import Foundation

extension OperatorClient {
    public func fetchInstructions(
        cursor: String? = nil,
        limit: Int = 50,
        status: InstructionStatus? = nil
    ) async throws -> InstructionList {
        if await usesDemoData {
            let filtered = status == nil
                ? DemoData.instructions
                : DemoData.instructions.filter { $0.status == status }
            return InstructionList(items: Array(filtered.prefix(limit)), nextCursor: nil)
        }
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await get("/v1/instructions", query: items)
    }

    public func createInstruction(
        description: String?,
        audioFileId: String,
        status: InstructionStatus? = nil
    ) async throws -> Instruction {
        if await usesDemoData { throw OperatorError.unauthenticated }
        return try await postJSON(
            "/v1/instructions",
            body: InstructionCreate(
                description: description,
                audioFileId: audioFileId,
                status: status
            )
        )
    }

    public func updateInstruction(id: String, description: String?) async throws -> Instruction {
        if await usesDemoData {
            guard let existing = DemoData.instructions.first(where: { $0.id == id }) else {
                throw OperatorError.unauthenticated
            }
            return Instruction(
                id: existing.id,
                description: description,
                status: existing.status,
                createdAt: existing.createdAt,
                audio: existing.audio
            )
        }
        return try await patchJSON(
            "/v1/instructions/\(id)",
            body: InstructionUpdate(description: description)
        )
    }

    public func activateInstruction(id: String) async throws -> Instruction {
        if await usesDemoData { return try demoInstruction(id: id, status: .active) }
        return try await postEmpty("/v1/instructions/\(id)/activate")
    }

    public func deactivateInstruction(id: String) async throws -> Instruction {
        if await usesDemoData { return try demoInstruction(id: id, status: .inactive) }
        return try await postEmpty("/v1/instructions/\(id)/deactivate")
    }

    public func deleteInstruction(id: String) async throws {
        if await usesDemoData { return }
        try await delete("/v1/instructions/\(id)")
    }

    private func demoInstruction(
        id: String,
        status: InstructionStatus
    ) throws -> Instruction {
        guard let existing = DemoData.instructions.first(where: { $0.id == id }) else {
            throw OperatorError.unauthenticated
        }
        return Instruction(
            id: existing.id,
            description: existing.description,
            status: status,
            createdAt: existing.createdAt,
            audio: existing.audio
        )
    }
}
