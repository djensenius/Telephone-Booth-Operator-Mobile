//
//  InstructionsView.swift
//  TelephoneBoothOperatorMobile
//
//  Admin management for the global random pool of instruction clips.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct InstructionsView: View {
    enum InstructionFilter: String, CaseIterable, Identifiable {
        case all
        case active
        case inactive

        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        var status: InstructionStatus? {
            switch self {
            case .all: nil
            case .active: .active
            case .inactive: .inactive
            }
        }
    }

    enum LoadState: Equatable {
        case idle
        case loadingInitial
        case loadingMore
        case done
    }

    @State private var instructions: [Instruction] = []
    @State private var nextCursor: String?
    @State private var loadState: LoadState = .idle
    @State private var errorMessage: String?
    @State private var expandedId: String?
    @State private var filter: InstructionFilter = .all
    @State private var isComposing = false
    @State private var editing: Instruction?
    @State private var pendingDelete: Instruction?
    @State private var generation = 0
    @State private var loadedPageCount = 0

    private let client: OperatorClient
    private let pageSize: Int

    public init(client: OperatorClient = .shared, pageSize: Int = 50) {
        self.client = client
        self.pageSize = pageSize
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(InstructionFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)

            content
        }
        .background(Theme.Colors.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isComposing = true
                } label: {
                    Label("New Instruction", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isComposing) {
            InstructionComposerView(client: client) { created in
                if filter.status == nil || filter.status == created.status {
                    instructions.insert(created, at: 0)
                }
            }
        }
        .sheet(item: $editing) { instruction in
            InstructionDescriptionEditor(instruction: instruction, client: client) { updated in
                applyUpdate(updated)
            }
        }
        .confirmationDialog(
            "Delete this instruction?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Instruction", role: .destructive) {
                guard let instruction = pendingDelete else { return }
                Task { await delete(instruction) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The booth will stop choosing this clip from the active instruction pool.")
        }
        .autoRefresh {
            await refreshLoadedPages()
        }
        .onChange(of: filter) { _, _ in
            Task { await loadFirstPage() }
        }
        .refreshableIfAvailable {
            await loadFirstPage()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loadState == .loadingInitial && instructions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if instructions.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if let errorMessage {
                BannerView(message: errorMessage, kind: .error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                Text("The booth chooses one active instruction at random whenever a caller dials 0.")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(instructions) { instruction in
                InstructionRow(
                    instruction: instruction,
                    isExpanded: expandedId == instruction.id,
                    onToggle: { toggle(instruction.id) },
                    onEdit: { editing = instruction },
                    onActivate: { Task { await activate(instruction) } },
                    onDeactivate: { Task { await deactivate(instruction) } },
                    onDelete: { pendingDelete = instruction }
                )
                .operatorListRowBackground()
            }
            if nextCursor != nil {
                loadMoreFooter
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .operatorListStyle()
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if loadState == .loadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else {
            Button("Load more") {
                Task { await loadMore() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "phone.badge.waveform")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(emptyTitle)
                .font(Theme.Fonts.bodyLarge)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "No instructions yet"
        case .active: "No active instructions"
        case .inactive: "No inactive instructions"
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy) {
            expandedId = expandedId == id ? nil : id
        }
    }

    private func loadFirstPage() async {
        generation += 1
        let requested = generation
        loadState = .loadingInitial
        errorMessage = nil
        do {
            let page = try await client.fetchInstructions(
                cursor: nil,
                limit: pageSize,
                status: filter.status
            )
            guard requested == generation else { return }
            instructions = page.items
            nextCursor = page.nextCursor
            loadedPageCount = 1
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation else { return }
            errorMessage = error.localizedDescription
            loadState = .idle
        }
    }

    private func refreshLoadedPages() async {
        guard loadState != .loadingInitial, loadState != .loadingMore else { return }
        generation += 1
        let requested = generation
        let pageCount = max(loadedPageCount, 1)
        let status = filter.status
        loadState = .loadingInitial
        do {
            let refreshed = try await reloadLoadedPages(
                pageCount: pageCount,
                isCurrent: { requested == generation },
                fetchPage: { cursor in
                    let page = try await client.fetchInstructions(
                        cursor: cursor,
                        limit: pageSize,
                        status: status
                    )
                    return (page.items, page.nextCursor)
                }
            )
            guard requested == generation else { return }
            guard !Task.isCancelled else {
                loadState = nextCursor == nil ? .done : .idle
                return
            }
            instructions = refreshed.items
            nextCursor = refreshed.nextCursor
            loadedPageCount = refreshed.pageCount
            errorMessage = nil
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation else { return }
            loadState = nextCursor == nil ? .done : .idle
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, loadState == .idle else { return }
        let requested = generation
        loadState = .loadingMore
        do {
            let page = try await client.fetchInstructions(
                cursor: cursor,
                limit: pageSize,
                status: filter.status
            )
            guard requested == generation else { return }
            instructions.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            loadedPageCount += 1
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation else { return }
            errorMessage = error.localizedDescription
            loadState = .idle
        }
    }

    private func activate(_ instruction: Instruction) async {
        do {
            applyUpdate(try await client.activateInstruction(id: instruction.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deactivate(_ instruction: Instruction) async {
        do {
            applyUpdate(try await client.deactivateInstruction(id: instruction.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ instruction: Instruction) async {
        pendingDelete = nil
        do {
            try await client.deleteInstruction(id: instruction.id)
            instructions.removeAll { $0.id == instruction.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyUpdate(_ updated: Instruction) {
        if let status = filter.status, status != updated.status {
            instructions.removeAll { $0.id == updated.id }
        } else if let index = instructions.firstIndex(where: { $0.id == updated.id }) {
            instructions[index] = updated
        }
    }
}

private struct InstructionRow: View {
    let instruction: Instruction
    let isExpanded: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                Button(action: onToggle) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        Text(instruction.description ?? "Untitled instruction")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: Theme.Spacing.medium) {
                            statusBadge
                            Text(instruction.createdAt, format: .dateTime.month(.abbreviated).day().year())
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            if let duration = DurationFormatter.shortString(
                                milliseconds: instruction.audio.durationMs
                            ) {
                                Label(duration, systemImage: "clock")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Hide audio preview" : "Show audio preview")
                Spacer(minLength: 0)
                actionsMenu
            }
            if isExpanded {
                AudioPlayerView(audio: instruction.audio)
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private var statusBadge: some View {
        Text(instruction.status.displayName)
            .font(Theme.Fonts.caption)
            .fontWeight(.semibold)
            .foregroundStyle(statusColor)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
    }

    private var statusColor: Color {
        switch instruction.status {
        case .active: Theme.Colors.success
        case .inactive, .unknown: Theme.Colors.textSecondary
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button(action: onEdit) {
                Label("Edit Description", systemImage: "pencil")
            }
            if instruction.status == .active {
                Button(action: onDeactivate) {
                    Label("Deactivate", systemImage: "pause.circle")
                }
            } else {
                Button(action: onActivate) {
                    Label("Activate", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Instruction actions")
    }
}

private struct InstructionDescriptionEditor: View {
    let instruction: Instruction
    let client: OperatorClient
    let onUpdated: (Instruction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        instruction: Instruction,
        client: OperatorClient,
        onUpdated: @escaping (Instruction) -> Void
    ) {
        self.instruction = instruction
        self.client = client
        self.onUpdated = onUpdated
        _description = State(initialValue: instruction.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(2...5)
                    .onChange(of: description) { _, value in
                        if value.count > Instruction.descriptionMaxLength {
                            description = String(value.prefix(Instruction.descriptionMaxLength))
                        }
                    }
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
            }
            .navigationTitle("Edit Description")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 260)
        #endif
    }

    private func save() async {
        isSaving = true
        do {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await client.updateInstruction(
                id: instruction.id,
                description: trimmed.isEmpty ? nil : trimmed
            )
            onUpdated(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

#endif
