import MinoDomain

public actor FilePersonalTimelineStore: PersonalTimelineStore {
    private let file: AtomicJSONFile<[PersonalTimelineEvent]>
    private let capacity: Int
    private var cachedEvents: [PersonalTimelineEvent]?

    public init(paths: AppStoragePaths, capacity: Int = 500) {
        self.file = AtomicJSONFile(
            url: paths.personalTimelineFile,
            schemaVersion: 1
        )
        self.capacity = max(1, capacity)
    }

    public func load() async throws -> [PersonalTimelineEvent] {
        try loadEvents()
    }

    public func append(_ event: PersonalTimelineEvent) async throws {
        try await merge([event])
    }

    public func merge(_ events: [PersonalTimelineEvent]) async throws {
        var merged = try loadEvents()
        var knownIDs = Set(merged.map(\.id))
        merged.append(contentsOf: events.filter { knownIDs.insert($0.id).inserted })
        merged.sort { $0.occurredAt < $1.occurredAt }
        if merged.count > capacity {
            merged.removeFirst(merged.count - capacity)
        }
        try file.save(merged)
        cachedEvents = merged
    }

    public func clear() async throws {
        try file.save([])
        cachedEvents = []
    }

    private func loadEvents() throws -> [PersonalTimelineEvent] {
        if let cachedEvents {
            return cachedEvents
        }
        if let events = try file.load() {
            cachedEvents = events
            return events
        }
        let events: [PersonalTimelineEvent] = []
        cachedEvents = events
        return events
    }
}

public actor InMemoryPersonalTimelineStore: PersonalTimelineStore {
    private var events: [PersonalTimelineEvent]
    private let capacity: Int

    public init(events: [PersonalTimelineEvent] = [], capacity: Int = 500) {
        self.events = events.sorted { $0.occurredAt < $1.occurredAt }
        self.capacity = max(1, capacity)
    }

    public func load() async throws -> [PersonalTimelineEvent] {
        events
    }

    public func append(_ event: PersonalTimelineEvent) async throws {
        try await merge([event])
    }

    public func merge(_ incoming: [PersonalTimelineEvent]) async throws {
        var knownIDs = Set(events.map(\.id))
        events.append(contentsOf: incoming.filter { knownIDs.insert($0.id).inserted })
        events.sort { $0.occurredAt < $1.occurredAt }
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    public func clear() async throws {
        events = []
    }
}
