import MinoDomain

public actor FileCoupleSnapshotStore: CoupleSnapshotStore {
    private let file: AtomicJSONFile<CoupleSnapshot>

    public init(paths: AppStoragePaths) {
        self.file = AtomicJSONFile(
            url: paths.coupleSnapshotFile,
            schemaVersion: 1
        )
    }

    public func load() async throws -> CoupleSnapshot? {
        try file.load()
    }

    public func save(_ snapshot: CoupleSnapshot) async throws {
        try file.save(snapshot)
    }

    public func clear() async throws {
        try file.delete()
    }
}

public actor InMemoryCoupleSnapshotStore: CoupleSnapshotStore {
    private var snapshot: CoupleSnapshot?

    public init(snapshot: CoupleSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() async throws -> CoupleSnapshot? {
        snapshot
    }

    public func save(_ snapshot: CoupleSnapshot) async throws {
        self.snapshot = snapshot
    }

    public func clear() async throws {
        snapshot = nil
    }
}
