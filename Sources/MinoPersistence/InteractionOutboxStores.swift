import Foundation
import MinoDomain

public actor FileInteractionOutboxStore: InteractionOutboxStore {
    private let file: AtomicJSONFile<[InteractionOutboxEntry]>
    private let capacity: Int
    private let retryPolicy: OutboxRetryPolicy
    private var cachedEntries: [InteractionOutboxEntry]?

    public init(
        paths: AppStoragePaths,
        capacity: Int = 500,
        retryPolicy: OutboxRetryPolicy = OutboxRetryPolicy()
    ) {
        self.file = AtomicJSONFile(
            url: paths.interactionOutboxFile,
            schemaVersion: 1
        )
        self.capacity = max(0, capacity)
        self.retryPolicy = retryPolicy
    }

    @discardableResult
    public func enqueue(_ command: InteractionCommand, at date: Date) async throws -> Bool {
        var state = try loadState()
        let inserted = try state.enqueue(command, at: date)
        guard inserted else { return false }
        try persist(state)
        return true
    }

    public func dueEntries(at date: Date, limit: Int) async throws -> [InteractionOutboxEntry] {
        try loadState().dueEntries(at: date, limit: limit)
    }

    public func markDelivered(idempotencyKey: UUID) async throws {
        var state = try loadState()
        guard state.markDelivered(idempotencyKey: idempotencyKey) else { return }
        try persist(state)
    }

    public func markFailed(idempotencyKey: UUID, errorCode: String, at date: Date) async throws {
        var state = try loadState()
        guard state.markFailed(idempotencyKey: idempotencyKey, errorCode: errorCode, at: date) else {
            return
        }
        try persist(state)
    }

    public func pendingCount() async throws -> Int {
        try loadState().entries.count
    }

    public func clear() async throws {
        try file.delete()
        cachedEntries = []
    }

    private func loadState() throws -> OutboxState {
        if let cachedEntries {
            return OutboxState(
                entries: cachedEntries,
                capacity: capacity,
                retryPolicy: retryPolicy
            )
        }
        let entries = try file.load() ?? []
        cachedEntries = entries
        return OutboxState(
            entries: entries,
            capacity: capacity,
            retryPolicy: retryPolicy
        )
    }

    private func persist(_ state: OutboxState) throws {
        try file.save(state.entries)
        cachedEntries = state.entries
    }
}

public actor InMemoryInteractionOutboxStore: InteractionOutboxStore {
    private var state: OutboxState

    public init(
        capacity: Int = 500,
        retryPolicy: OutboxRetryPolicy = OutboxRetryPolicy()
    ) {
        self.state = OutboxState(
            entries: [],
            capacity: max(0, capacity),
            retryPolicy: retryPolicy
        )
    }

    @discardableResult
    public func enqueue(_ command: InteractionCommand, at date: Date) async throws -> Bool {
        try state.enqueue(command, at: date)
    }

    public func dueEntries(at date: Date, limit: Int) async throws -> [InteractionOutboxEntry] {
        state.dueEntries(at: date, limit: limit)
    }

    public func markDelivered(idempotencyKey: UUID) async throws {
        _ = state.markDelivered(idempotencyKey: idempotencyKey)
    }

    public func markFailed(idempotencyKey: UUID, errorCode: String, at date: Date) async throws {
        _ = state.markFailed(idempotencyKey: idempotencyKey, errorCode: errorCode, at: date)
    }

    public func pendingCount() async throws -> Int {
        state.entries.count
    }

    public func clear() async throws {
        state.entries = []
    }
}

private struct OutboxState: Sendable {
    var entries: [InteractionOutboxEntry]
    let capacity: Int
    let retryPolicy: OutboxRetryPolicy

    mutating func enqueue(_ command: InteractionCommand, at date: Date) throws -> Bool {
        if entries.contains(where: { $0.command.idempotencyKey == command.idempotencyKey }) {
            return false
        }
        guard entries.count < capacity else {
            throw InteractionOutboxError.full(limit: capacity)
        }
        entries.append(
            InteractionOutboxEntry(
                command: command,
                enqueuedAt: date,
                nextAttemptAt: date
            )
        )
        return true
    }

    func dueEntries(at date: Date, limit: Int) -> [InteractionOutboxEntry] {
        guard limit > 0 else { return [] }
        return entries
            .filter { $0.nextAttemptAt <= date }
            .sorted {
                if $0.nextAttemptAt == $1.nextAttemptAt {
                    return $0.enqueuedAt < $1.enqueuedAt
                }
                return $0.nextAttemptAt < $1.nextAttemptAt
            }
            .prefix(limit)
            .map { $0 }
    }

    mutating func markDelivered(idempotencyKey: UUID) -> Bool {
        let previousCount = entries.count
        entries.removeAll { $0.command.idempotencyKey == idempotencyKey }
        return entries.count != previousCount
    }

    mutating func markFailed(idempotencyKey: UUID, errorCode: String, at date: Date) -> Bool {
        guard let index = entries.firstIndex(where: {
            $0.command.idempotencyKey == idempotencyKey
        }) else {
            return false
        }

        entries[index].attemptCount += 1
        entries[index].lastErrorCode = String(errorCode.prefix(128))
        let delay = retryPolicy.delay(afterAttempt: entries[index].attemptCount)
        entries[index].nextAttemptAt = date.addingTimeInterval(delay)
        return true
    }
}
