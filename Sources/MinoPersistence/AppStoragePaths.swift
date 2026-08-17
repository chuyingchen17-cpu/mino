import Foundation

public struct AppStoragePaths: Equatable, Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public var coupleSnapshotFile: URL {
        rootDirectory.appendingPathComponent("couple-snapshot.json", isDirectory: false)
    }

    public var interactionOutboxFile: URL {
        rootDirectory.appendingPathComponent("interaction-outbox.json", isDirectory: false)
    }

    public var personalTimelineFile: URL {
        rootDirectory.appendingPathComponent("personal-timeline.json", isDirectory: false)
    }

    public var legacyCoupleTimelineFile: URL {
        rootDirectory.appendingPathComponent("couple-timeline.json", isDirectory: false)
    }

    @available(*, deprecated, renamed: "personalTimelineFile")
    public var coupleTimelineFile: URL {
        personalTimelineFile
    }

    public static func live(
        storageNamespace: String = "",
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) throws -> AppStoragePaths {
        guard isValidNamespace(storageNamespace) else {
            throw PersistenceError.invalidStorageNamespace(storageNamespace)
        }

        let applicationSupport: URL
        if let applicationSupportDirectory {
            applicationSupport = applicationSupportDirectory
        } else {
            applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }

        var root = applicationSupport.appendingPathComponent("Mino", isDirectory: true)
        if !storageNamespace.isEmpty {
            root.appendPathComponent(storageNamespace, isDirectory: true)
        }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        return AppStoragePaths(rootDirectory: root)
    }

    private static func isValidNamespace(_ value: String) -> Bool {
        guard value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 95:
                true
            default:
                false
            }
        }
    }
}

public enum PersistenceError: Error, Equatable, Sendable {
    case invalidStorageNamespace(String)
    case unsupportedSchema(expected: Int, actual: Int)
    case encoding
    case decoding
    case fileOperation(operation: String, code: Int)
}

package struct AtomicJSONFile<Value: Codable & Sendable>: Sendable {
    package let url: URL
    package let schemaVersion: Int

    package init(url: URL, schemaVersion: Int) {
        self.url = url
        self.schemaVersion = schemaVersion
    }

    package func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw fileError(operation: "read", error: error)
        }

        let header: SchemaHeader
        do {
            header = try Self.decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw PersistenceError.decoding
        }
        guard header.schemaVersion == schemaVersion else {
            throw PersistenceError.unsupportedSchema(
                expected: schemaVersion,
                actual: header.schemaVersion
            )
        }

        let envelope: VersionedEnvelope<Value>
        do {
            envelope = try Self.decoder.decode(VersionedEnvelope<Value>.self, from: data)
        } catch {
            throw PersistenceError.decoding
        }
        return envelope.payload
    }

    package func save(_ value: Value) throws {
        let envelope = VersionedEnvelope(schemaVersion: schemaVersion, payload: value)
        let data: Data
        do {
            data = try Self.encoder.encode(envelope)
        } catch {
            throw PersistenceError.encoding
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw fileError(operation: "write", error: error)
        }
    }

    package func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw fileError(operation: "delete", error: error)
        }
    }

    private func fileError(operation: String, error: Error) -> PersistenceError {
        let code = (error as NSError).code
        return .fileOperation(operation: operation, code: code)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private struct VersionedEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let payload: Payload
}

private struct SchemaHeader: Decodable {
    let schemaVersion: Int
}
