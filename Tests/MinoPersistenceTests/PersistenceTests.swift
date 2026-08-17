import Foundation
import MinoDomain
import Testing

@testable import MinoPersistence

@Test
func livePathsIsolateDebugClientProfiles() throws {
    let applicationSupport = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: applicationSupport) }

    let alice = try AppStoragePaths.live(
        storageNamespace: "alice",
        applicationSupportDirectory: applicationSupport
    )
    let bob = try AppStoragePaths.live(
        storageNamespace: "bob",
        applicationSupportDirectory: applicationSupport
    )
    let standard = try AppStoragePaths.live(
        applicationSupportDirectory: applicationSupport
    )

    let minoRoot = applicationSupport.appendingPathComponent("Mino", isDirectory: true)
    #expect(alice.rootDirectory == minoRoot.appendingPathComponent("alice", isDirectory: true))
    #expect(bob.rootDirectory == minoRoot.appendingPathComponent("bob", isDirectory: true))
    #expect(standard.rootDirectory == minoRoot)
    #expect(alice.coupleSnapshotFile != bob.coupleSnapshotFile)

    let attributes = try FileManager.default.attributesOfItem(atPath: alice.rootDirectory.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test
func livePathsRejectUnsafeStorageNamespace() throws {
    let applicationSupport = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: applicationSupport) }

    #expect(throws: PersistenceError.invalidStorageNamespace("../bob")) {
        try AppStoragePaths.live(
            storageNamespace: "../bob",
            applicationSupportDirectory: applicationSupport
        )
    }
}

@Test
func coupleSnapshotPersistsAcrossStoreInstances() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let paths = AppStoragePaths(rootDirectory: temporaryDirectory)
    let snapshot = makeSnapshot()

    let writer = FileCoupleSnapshotStore(paths: paths)
    try await writer.save(snapshot)

    let reader = FileCoupleSnapshotStore(paths: paths)
    #expect(try await reader.load() == snapshot)

    let attributes = try FileManager.default.attributesOfItem(atPath: paths.coupleSnapshotFile.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func outboxPersistsDeduplicatesAndRetries() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let paths = AppStoragePaths(rootDirectory: temporaryDirectory)
    let now = Date(timeIntervalSince1970: 1_000.75)
    let command = makeCommand()

    let writer = FileInteractionOutboxStore(paths: paths)
    #expect(try await writer.enqueue(command, at: now))
    #expect(try await !writer.enqueue(command, at: now))

    let reader = FileInteractionOutboxStore(paths: paths)
    #expect(try await reader.pendingCount() == 1)
    #expect(try await reader.dueEntries(at: now, limit: 10).count == 1)

    try await reader.markFailed(
        idempotencyKey: command.idempotencyKey,
        errorCode: "temporarily_unavailable",
        at: now
    )
    #expect(try await reader.dueEntries(at: now.addingTimeInterval(1), limit: 10).isEmpty)
    let retried = try #require(
        await reader.dueEntries(at: now.addingTimeInterval(2), limit: 10).first
    )
    #expect(retried.attemptCount == 1)
    #expect(retried.lastErrorCode == "temporarily_unavailable")

    try await reader.markDelivered(idempotencyKey: command.idempotencyKey)
    #expect(try await reader.pendingCount() == 0)
}

@Test
func outboxEnforcesCapacity() async throws {
    let store = InMemoryInteractionOutboxStore(capacity: 1)
    let now = Date(timeIntervalSince1970: 1_000)
    _ = try await store.enqueue(makeCommand(), at: now)

    await #expect(throws: InteractionOutboxError.full(limit: 1)) {
        try await store.enqueue(
            makeCommand(idempotencyKey: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
            at: now
        )
    }
}

@Test
func unsupportedPersistenceSchemaFailsWithoutDeletingData() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let paths = AppStoragePaths(rootDirectory: temporaryDirectory)
    try Data("{\"schemaVersion\":99,\"payload\":{\"incompatible\":true}}".utf8).write(
        to: paths.interactionOutboxFile
    )
    let store = FileInteractionOutboxStore(paths: paths)

    do {
        _ = try await store.pendingCount()
        Issue.record("Expected unsupported schema failure")
    } catch let error as PersistenceError {
        #expect(error == .unsupportedSchema(expected: 1, actual: 99))
    }
    #expect(FileManager.default.fileExists(atPath: paths.interactionOutboxFile.path))
}

@Test
func timelinePersistsOrdersAndDeduplicatesEvents() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let paths = AppStoragePaths(rootDirectory: temporaryDirectory)
    let later = PersonalTimelineEvent(
        id: "event_2",
        kind: .visitArrived,
        occurredAt: Date(timeIntervalSince1970: 2_000)
    )
    let earlier = PersonalTimelineEvent(
        id: "event_1",
        kind: .visitInvited,
        occurredAt: Date(timeIntervalSince1970: 1_000)
    )

    let writer = FilePersonalTimelineStore(paths: paths)
    try await writer.merge([later, earlier, later])

    let reader = FilePersonalTimelineStore(paths: paths)
    let events = try await reader.load()
    #expect(events.map(\.id) == ["event_1", "event_2"])
    let attributes = try FileManager.default.attributesOfItem(atPath: paths.personalTimelineFile.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func personalTimelineMigratesLegacyFileWithoutDeletingIt() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let paths = AppStoragePaths(rootDirectory: temporaryDirectory)
    let event = PersonalTimelineEvent(
        id: "event_legacy",
        kind: .visitArrived,
        occurredAt: Date(timeIntervalSince1970: 1_000)
    )
    let legacyFile = AtomicJSONFile<[PersonalTimelineEvent]>(
        url: paths.legacyCoupleTimelineFile,
        schemaVersion: 1
    )
    try legacyFile.save([event])

    let store = FilePersonalTimelineStore(paths: paths)
    #expect(try await store.load() == [event])
    #expect(FileManager.default.fileExists(atPath: paths.personalTimelineFile.path))
    #expect(FileManager.default.fileExists(atPath: paths.legacyCoupleTimelineFile.path))

    try await store.clear()
    let reopened = FilePersonalTimelineStore(paths: paths)
    #expect(try await reopened.load().isEmpty)
    #expect(FileManager.default.fileExists(atPath: paths.legacyCoupleTimelineFile.path))
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mino-persistence-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

private func makeCommand(idempotencyKey: UUID = UUID()) -> InteractionCommand {
    InteractionCommand(
        idempotencyKey: idempotencyKey,
        kind: .kiss,
        senderPetID: PetProfileID(rawValue: "pet_local"),
        recipientPetID: PetProfileID(rawValue: "pet_partner"),
        clientCreatedAt: Date(timeIntervalSince1970: 1_000)
    )
}

private func makeSnapshot() -> CoupleSnapshot {
    let now = Date(timeIntervalSince1970: 1_000)
    let localAccountID = AccountID(rawValue: "account_local")
    let partnerAccountID = AccountID(rawValue: "account_partner")
    return CoupleSnapshot(
        context: CoupleContext(
            id: CoupleID(rawValue: "couple_1"),
            localAccountID: localAccountID,
            partnerAccountID: partnerAccountID,
            status: .active,
            pairedAt: now,
            updatedAt: now
        ),
        localAccount: AccountProfile(
            id: localAccountID,
            displayName: "奶糖主人",
            createdAt: now
        ),
        partnerAccount: AccountProfile(
            id: partnerAccountID,
            displayName: "团子主人",
            createdAt: now
        ),
        localPet: PetProfile(
            id: PetProfileID(rawValue: "pet_local"),
            ownerAccountID: localAccountID,
            displayName: "奶糖",
            avatar: .mine,
            revision: 1,
            updatedAt: now
        ),
        partnerPet: PetProfile(
            id: PetProfileID(rawValue: "pet_partner"),
            ownerAccountID: partnerAccountID,
            displayName: "团子",
            avatar: .partner,
            revision: 2,
            updatedAt: now
        ),
        serverCursor: "cursor_1",
        syncedAt: now
    )
}
