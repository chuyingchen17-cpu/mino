import Foundation
import MinoDomain
import Testing

@testable import MinoPersistence

@Test
func friendshipEventCursorsPersistIndependently() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(rootDirectory: directory)
    let aliceFriendship = FriendshipID(rawValue: "friendship_alice")
    let bobFriendship = FriendshipID(rawValue: "friendship_bob")
    let first = FileFriendshipEventCursorStore(paths: paths)

    #expect(try await first.load(for: aliceFriendship) == nil)
    try await first.save("event_7", for: aliceFriendship)
    try await first.save("event_bob", for: bobFriendship)
    try await first.save("event_8", for: aliceFriendship)

    let reloaded = FileFriendshipEventCursorStore(paths: paths)
    #expect(try await reloaded.load(for: aliceFriendship) == "event_8")
    #expect(try await reloaded.load(for: bobFriendship) == "event_bob")
    try await reloaded.clear(for: aliceFriendship)
    #expect(try await reloaded.load(for: aliceFriendship) == nil)
    #expect(try await reloaded.load(for: bobFriendship) == "event_bob")
}
