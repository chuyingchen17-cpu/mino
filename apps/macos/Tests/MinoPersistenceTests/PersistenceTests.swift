import Foundation
import MinoDomain
import Testing
@testable import MinoPersistence

@Test
func livePathsIsolateDebugClientProfilesAndRejectTraversal() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let alice = try AppStoragePaths.live(storageNamespace: "alice", applicationSupportDirectory: root)
    let bob = try AppStoragePaths.live(storageNamespace: "bob", applicationSupportDirectory: root)
    #expect(alice.accountEventCursorFile != bob.accountEventCursorFile)
    #expect(throws: PersistenceError.invalidStorageNamespace("../bob")) {
        try AppStoragePaths.live(storageNamespace: "../bob", applicationSupportDirectory: root)
    }
}

@Test
func accountCursorPersistsIndependentlyAndNeverMovesBackward() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(rootDirectory: root)
    let alice = AccountID(rawValue: "alice")
    let bob = AccountID(rawValue: "bob")
    let writer = FileAccountEventCursorStore(paths: paths)
    try await writer.save(12, for: alice)
    try await writer.save(5, for: bob)
    try await writer.save(9, for: alice)
    let reader = FileAccountEventCursorStore(paths: paths)
    #expect(try await reader.load(for: alice) == 12)
    #expect(try await reader.load(for: bob) == 5)
}

@Test
func socialMutationOutboxPersistsDeduplicatesAndRetriesSameKey() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(rootDirectory: root)
    let id = UUID()
    let key = UUID()
    let now = Date(timeIntervalSince1970: 1_000)
    let mutation = SocialMutation(
        id: id, kind: .createVisit, idempotencyKey: key,
        body: .object(["friendshipID": .string("friendship_1")]),
        createdAt: now, nextAttemptAt: now
    )
    let writer = FileSocialMutationOutboxStore(paths: paths)
    try await writer.enqueue(mutation)
    try await writer.enqueue(mutation)
    let reader = FileSocialMutationOutboxStore(paths: paths)
    #expect(try await reader.due(at: now).count == 1)
    try await reader.markFailed(id, retryAt: now.addingTimeInterval(2))
    #expect(try await reader.due(at: now.addingTimeInterval(1)).isEmpty)
    let retry = try #require(try await reader.due(at: now.addingTimeInterval(2)).first)
    #expect(retry.idempotencyKey == key)
    #expect(retry.attemptCount == 1)
    try await reader.clear()
    #expect(try await reader.due(at: .distantFuture).isEmpty)
    try await reader.enqueue(mutation)
    try await reader.markSucceeded(id)
    #expect(try await reader.due(at: .distantFuture).isEmpty)
}

@Test
func unsupportedOutboxSchemaFailsWithoutDeletingData() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(rootDirectory: root)
    try Data("{\"schemaVersion\":99,\"payload\":[]}".utf8).write(to: paths.socialMutationOutboxFile)
    let store = FileSocialMutationOutboxStore(paths: paths)
    await #expect(throws: PersistenceError.unsupportedSchema(expected: 1, actual: 99)) {
        _ = try await store.due(at: Date())
    }
    #expect(FileManager.default.fileExists(atPath: paths.socialMutationOutboxFile.path))
}

@Test
func timelinePersistsOrdersAndDeduplicatesEvents() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(rootDirectory: root)
    let later = PersonalTimelineEvent(id: "event_2", kind: .visitArrived, occurredAt: Date(timeIntervalSince1970: 2))
    let earlier = PersonalTimelineEvent(id: "event_1", kind: .visitInvited, occurredAt: Date(timeIntervalSince1970: 1))
    let writer = FilePersonalTimelineStore(paths: paths)
    try await writer.merge([later, earlier, later])
    #expect(try await FilePersonalTimelineStore(paths: paths).load().map(\.id) == ["event_1", "event_2"])
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mino-persistence-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
