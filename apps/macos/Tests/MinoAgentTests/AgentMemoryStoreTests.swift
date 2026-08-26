import CryptoKit
import Foundation
import MinoAgent
import MinoDomain
import Testing

@Test
func inMemoryStoreFiltersAndEvictsLeastImportantMemory() async throws {
    let store = InMemoryAgentMemoryStore(capacity: 2)
    let lowID = UUID()
    let highID = UUID()
    let newID = UUID()
    try await store.save(
        makeMemory(
            id: lowID,
            summary: "普通的一天",
            importance: 0.1,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    )
    try await store.save(
        makeMemory(
            id: highID,
            summary: "团子喜欢草莓",
            importance: 0.9,
            createdAt: Date(timeIntervalSince1970: 2)
        )
    )
    try await store.save(
        makeMemory(
            id: newID,
            summary: "团子想一起玩",
            importance: 0.5,
            createdAt: Date(timeIntervalSince1970: 3)
        )
    )

    let all = try await store.allMemories(for: PetProfileID(rawValue: "pet_local"))
    #expect(Set(all.map(\.id)) == [highID, newID])

    let matches = try await store.memories(
        matching: AgentMemoryQuery(
            petID: PetProfileID(rawValue: "pet_local"),
            relatedPetID: PetProfileID(rawValue: "pet_partner"),
            categories: [.friendPet],
            terms: ["草莓"],
            limit: 5
        )
    )
    #expect(matches.map(\.id) == [highID])
}

@Test
func inMemoryStoreUpdatesAndDeletesWithoutCrossingPetBoundary() async throws {
    let store = InMemoryAgentMemoryStore(capacity: 5)
    let memoryID = UUID()
    let otherPetID = PetProfileID(rawValue: "pet_other")
    try await store.save(makeMemory(id: memoryID, summary: "旧内容"))
    try await store.save(makeMemory(id: memoryID, summary: "新内容"))
    try await store.save(makeMemory(id: UUID(), petID: otherPetID))

    let local = try await store.allMemories(for: PetProfileID(rawValue: "pet_local"))
    #expect(local.count == 1)
    #expect(local.first?.summary == "新内容")

    try await store.removeAll(for: PetProfileID(rawValue: "pet_local"))
    #expect(try await store.allMemories(for: PetProfileID(rawValue: "pet_local")).isEmpty)
    #expect(try await store.allMemories(for: otherPetID).count == 1)
}

@Test
func encryptedFileStoreHidesPlaintextAndReloads() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mino-agent-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("memory.enc")
    let key = SymmetricKey(data: Data(repeating: 0xA5, count: 32))
    let memory = makeMemory(id: UUID(), summary: "不能出现在磁盘上的草莓秘密")

    let writer = EncryptedFileAgentMemoryStore(fileURL: fileURL, key: key)
    try await writer.save(memory)

    let raw = try Data(contentsOf: fileURL)
    #expect(raw.range(of: Data("草莓秘密".utf8)) == nil)
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    let reader = EncryptedFileAgentMemoryStore(fileURL: fileURL, key: key)
    #expect(try await reader.allMemories(for: memory.petID) == [memory])
}

@Test
func encryptedFileStoreRejectsWrongKeyWithoutDeletingFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mino-agent-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("memory.enc")
    let writer = EncryptedFileAgentMemoryStore(
        fileURL: fileURL,
        key: SymmetricKey(data: Data(repeating: 0x11, count: 32))
    )
    try await writer.save(makeMemory(id: UUID()))

    let wrongReader = EncryptedFileAgentMemoryStore(
        fileURL: fileURL,
        key: SymmetricKey(data: Data(repeating: 0x22, count: 32))
    )
    await #expect(throws: AgentMemoryStoreError.decryptionFailed) {
        try await wrongReader.allMemories(for: PetProfileID(rawValue: "pet_local"))
    }
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
}
