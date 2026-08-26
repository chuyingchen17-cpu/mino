import CryptoKit
import Foundation
import MinoDomain

public enum AgentMemoryStoreError: Error, Equatable, Sendable {
    case unsupportedSchema(expected: Int, actual: Int)
    case corruptFile
    case encryptionFailed
    case decryptionFailed
}

public protocol AgentMemoryStore: Sendable {
    func memories(matching query: AgentMemoryQuery) async throws -> [AgentMemory]
    func allMemories(for petID: PetProfileID) async throws -> [AgentMemory]
    func save(_ memory: AgentMemory) async throws
    func remove(id: UUID) async throws
    func removeAll(for petID: PetProfileID) async throws
}

public actor InMemoryAgentMemoryStore: AgentMemoryStore {
    private var collection: AgentMemoryCollection

    public init(capacity: Int = 200) {
        collection = AgentMemoryCollection(capacity: capacity)
    }

    public func memories(matching query: AgentMemoryQuery) async throws -> [AgentMemory] {
        collection.memories(matching: query)
    }

    public func allMemories(for petID: PetProfileID) async throws -> [AgentMemory] {
        collection.allMemories(for: petID)
    }

    public func save(_ memory: AgentMemory) async throws {
        collection.save(memory)
    }

    public func remove(id: UUID) async throws {
        _ = collection.remove(id: id)
    }

    public func removeAll(for petID: PetProfileID) async throws {
        _ = collection.removeAll(for: petID)
    }
}

/// A small encrypted JSON store for MVP pet memory. The encryption key is injected so the
/// application can own Keychain access without coupling this target to MinoSecurity.
public actor EncryptedFileAgentMemoryStore: AgentMemoryStore {
    private static let schemaVersion = 1

    private let fileURL: URL
    private let key: SymmetricKey
    private let capacity: Int
    private var cachedCollection: AgentMemoryCollection?

    public init(fileURL: URL, key: SymmetricKey, capacity: Int = 200) {
        self.fileURL = fileURL
        self.key = key
        self.capacity = max(0, capacity)
    }

    public func memories(matching query: AgentMemoryQuery) async throws -> [AgentMemory] {
        try loadCollection().memories(matching: query)
    }

    public func allMemories(for petID: PetProfileID) async throws -> [AgentMemory] {
        try loadCollection().allMemories(for: petID)
    }

    public func save(_ memory: AgentMemory) async throws {
        var collection = try loadCollection()
        collection.save(memory)
        try persist(collection)
    }

    public func remove(id: UUID) async throws {
        var collection = try loadCollection()
        guard collection.remove(id: id) else { return }
        try persist(collection)
    }

    public func removeAll(for petID: PetProfileID) async throws {
        var collection = try loadCollection()
        guard collection.removeAll(for: petID) else { return }
        try persist(collection)
    }

    private func loadCollection() throws -> AgentMemoryCollection {
        if let cachedCollection {
            return cachedCollection
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = AgentMemoryCollection(capacity: capacity)
            cachedCollection = empty
            return empty
        }

        let encryptedData: Data
        do {
            encryptedData = try Data(contentsOf: fileURL)
        } catch {
            throw AgentMemoryStoreError.corruptFile
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        } catch {
            throw AgentMemoryStoreError.corruptFile
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw AgentMemoryStoreError.decryptionFailed
        }

        let payload: FilePayload
        do {
            payload = try JSONDecoder().decode(FilePayload.self, from: plaintext)
        } catch {
            throw AgentMemoryStoreError.corruptFile
        }
        guard payload.schemaVersion == Self.schemaVersion else {
            throw AgentMemoryStoreError.unsupportedSchema(
                expected: Self.schemaVersion,
                actual: payload.schemaVersion
            )
        }

        var collection = AgentMemoryCollection(capacity: capacity)
        for memory in payload.memories.sorted(by: { $0.createdAt < $1.createdAt }) {
            collection.save(memory)
        }
        cachedCollection = collection
        return collection
    }

    private func persist(_ collection: AgentMemoryCollection) throws {
        let payload = FilePayload(
            schemaVersion: Self.schemaVersion,
            memories: collection.memories
        )
        let plaintext: Data
        do {
            plaintext = try JSONEncoder().encode(payload)
        } catch {
            throw AgentMemoryStoreError.encryptionFailed
        }

        let combined: Data
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let value = sealedBox.combined else {
                throw AgentMemoryStoreError.encryptionFailed
            }
            combined = value
        } catch let error as AgentMemoryStoreError {
            throw error
        } catch {
            throw AgentMemoryStoreError.encryptionFailed
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try combined.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw AgentMemoryStoreError.encryptionFailed
        }
        cachedCollection = collection
    }
}

private struct FilePayload: Codable, Sendable {
    let schemaVersion: Int
    let memories: [AgentMemory]
}

private struct AgentMemoryCollection: Sendable {
    let capacity: Int
    var memories: [AgentMemory]

    init(capacity: Int, memories: [AgentMemory] = []) {
        self.capacity = max(0, capacity)
        self.memories = Array(memories.prefix(max(0, capacity)))
    }

    mutating func save(_ memory: AgentMemory) {
        if let existingIndex = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[existingIndex] = memory
            return
        }
        guard capacity > 0 else { return }
        if memories.count == capacity {
            let evictionIndex = memories.indices.min { left, right in
                let leftMemory = memories[left]
                let rightMemory = memories[right]
                if leftMemory.importance == rightMemory.importance {
                    return leftMemory.createdAt < rightMemory.createdAt
                }
                return leftMemory.importance < rightMemory.importance
            }
            if let evictionIndex {
                memories.remove(at: evictionIndex)
            }
        }
        memories.append(memory)
    }

    mutating func remove(id: UUID) -> Bool {
        let oldCount = memories.count
        memories.removeAll { $0.id == id }
        return memories.count != oldCount
    }

    mutating func removeAll(for petID: PetProfileID) -> Bool {
        let oldCount = memories.count
        memories.removeAll { $0.petID == petID }
        return memories.count != oldCount
    }

    func allMemories(for petID: PetProfileID) -> [AgentMemory] {
        memories
            .filter { $0.petID == petID }
            .sorted {
                if $0.importance == $1.importance {
                    return $0.createdAt > $1.createdAt
                }
                return $0.importance > $1.importance
            }
    }

    func memories(matching query: AgentMemoryQuery) -> [AgentMemory] {
        guard query.limit > 0 else { return [] }
        let normalizedTerms = query.terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return memories
            .filter { memory in
                guard memory.petID == query.petID else { return false }
                if let relatedPetID = query.relatedPetID,
                   !memory.relatedPetIDs.contains(relatedPetID) {
                    return false
                }
                if !query.categories.isEmpty,
                   !query.categories.contains(memory.category) {
                    return false
                }
                if !normalizedTerms.isEmpty {
                    let haystack = "\(memory.summary) \(memory.reason)".lowercased()
                    guard normalizedTerms.contains(where: haystack.contains) else {
                        return false
                    }
                }
                return true
            }
            .sorted {
                if $0.importance == $1.importance {
                    return $0.createdAt > $1.createdAt
                }
                return $0.importance > $1.importance
            }
            .prefix(query.limit)
            .map { $0 }
    }
}
