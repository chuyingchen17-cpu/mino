import Foundation
import MinoDomain

public actor FileSocialMutationOutboxStore: SocialMutationOutboxStore {
    private let file: AtomicJSONFile<[SocialMutation]>
    private let capacity: Int
    private var cached: [SocialMutation]?

    public init(paths: AppStoragePaths, capacity: Int = 500) {
        file = AtomicJSONFile(url: paths.socialMutationOutboxFile, schemaVersion: 1)
        self.capacity = max(1, capacity)
    }

    public func enqueue(_ mutation: SocialMutation) async throws {
        var values = try load()
        guard !values.contains(where: { $0.idempotencyKey == mutation.idempotencyKey }) else { return }
        if values.count >= capacity { values.removeFirst(values.count - capacity + 1) }
        values.append(mutation)
        try persist(values)
    }

    public func due(at date: Date) async throws -> [SocialMutation] {
        try load().filter { $0.nextAttemptAt <= date }.sorted { $0.createdAt < $1.createdAt }
    }

    public func markSucceeded(_ id: UUID) async throws {
        var values = try load()
        values.removeAll { $0.id == id }
        try persist(values)
    }

    public func markFailed(_ id: UUID, retryAt: Date) async throws {
        var values = try load()
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].attemptCount += 1
        values[index].nextAttemptAt = retryAt
        try persist(values)
    }

    public func clear() async throws {
        try persist([])
    }

    private func load() throws -> [SocialMutation] {
        if let cached { return cached }
        let values = try file.load() ?? []
        cached = values
        return values
    }

    private func persist(_ values: [SocialMutation]) throws {
        try file.save(values)
        cached = values
    }
}

public actor InMemorySocialMutationOutboxStore: SocialMutationOutboxStore {
    private var values: [SocialMutation]
    public init(values: [SocialMutation] = []) { self.values = values }
    public func enqueue(_ mutation: SocialMutation) async throws {
        guard !values.contains(where: { $0.idempotencyKey == mutation.idempotencyKey }) else { return }
        values.append(mutation)
    }
    public func due(at date: Date) async throws -> [SocialMutation] {
        values.filter { $0.nextAttemptAt <= date }.sorted { $0.createdAt < $1.createdAt }
    }
    public func markSucceeded(_ id: UUID) async throws { values.removeAll { $0.id == id } }
    public func markFailed(_ id: UUID, retryAt: Date) async throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].attemptCount += 1
        values[index].nextAttemptAt = retryAt
    }
    public func clear() async throws { values.removeAll() }
}
