import MinoDomain

public actor FileFriendshipEventCursorStore: FriendshipEventCursorStore {
    private let file: AtomicJSONFile<[String: String]>
    private var cachedCursors: [String: String]?

    public init(paths: AppStoragePaths) {
        self.file = AtomicJSONFile(
            url: paths.rootDirectory.appendingPathComponent("friendship-event-cursors.json"),
            schemaVersion: 1
        )
    }

    public func load(for friendshipID: FriendshipID) async throws -> String? {
        try loadCursors()[friendshipID.rawValue]
    }

    public func save(_ eventID: String, for friendshipID: FriendshipID) async throws {
        var cursors = try loadCursors()
        cursors[friendshipID.rawValue] = eventID
        try file.save(cursors)
        cachedCursors = cursors
    }

    public func clear(for friendshipID: FriendshipID) async throws {
        var cursors = try loadCursors()
        cursors.removeValue(forKey: friendshipID.rawValue)
        if cursors.isEmpty {
            try file.delete()
        } else {
            try file.save(cursors)
        }
        cachedCursors = cursors
    }

    private func loadCursors() throws -> [String: String] {
        if let cachedCursors { return cachedCursors }
        let cursors = try file.load() ?? [:]
        cachedCursors = cursors
        return cursors
    }
}

public actor InMemoryFriendshipEventCursorStore: FriendshipEventCursorStore {
    private var cursors: [FriendshipID: String]

    public init(cursors: [FriendshipID: String] = [:]) {
        self.cursors = cursors
    }

    public func load(for friendshipID: FriendshipID) async throws -> String? {
        cursors[friendshipID]
    }

    public func save(_ eventID: String, for friendshipID: FriendshipID) async throws {
        cursors[friendshipID] = eventID
    }

    public func clear(for friendshipID: FriendshipID) async throws {
        cursors.removeValue(forKey: friendshipID)
    }
}

@available(*, deprecated, renamed: "FileFriendshipEventCursorStore")
public typealias FileCoupleEventCursorStore = FileFriendshipEventCursorStore

@available(*, deprecated, renamed: "InMemoryFriendshipEventCursorStore")
public typealias InMemoryCoupleEventCursorStore = InMemoryFriendshipEventCursorStore
