import MinoDomain

public actor FileAccountEventCursorStore: AccountEventCursorStore {
    private let file: AtomicJSONFile<[String: Int64]>
    private var cached: [String: Int64]?

    public init(paths: AppStoragePaths) {
        file = AtomicJSONFile(url: paths.accountEventCursorFile, schemaVersion: 1)
    }

    public func load(for accountID: AccountID) async throws -> Int64? {
        try values()[accountID.rawValue]
    }

    public func save(_ cursor: Int64, for accountID: AccountID) async throws {
        var current = try values()
        current[accountID.rawValue] = max(cursor, current[accountID.rawValue] ?? 0)
        try file.save(current)
        cached = current
    }

    public func clear(for accountID: AccountID) async throws {
        var current = try values()
        current.removeValue(forKey: accountID.rawValue)
        if current.isEmpty { try file.delete() } else { try file.save(current) }
        cached = current
    }

    private func values() throws -> [String: Int64] {
        if let cached { return cached }
        let loaded = try file.load() ?? [:]
        cached = loaded
        return loaded
    }
}

public actor InMemoryAccountEventCursorStore: AccountEventCursorStore {
    private var cursors: [AccountID: Int64]
    public init(cursors: [AccountID: Int64] = [:]) { self.cursors = cursors }
    public func load(for accountID: AccountID) async throws -> Int64? { cursors[accountID] }
    public func save(_ cursor: Int64, for accountID: AccountID) async throws {
        cursors[accountID] = max(cursor, cursors[accountID] ?? 0)
    }
    public func clear(for accountID: AccountID) async throws { cursors.removeValue(forKey: accountID) }
}
