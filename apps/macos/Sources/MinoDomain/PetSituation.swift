import Foundation

/// Coarse owner presence. Unknown means no sensor has reported yet — not “away”.
public enum OwnerPresence: String, Codable, Sendable {
    case unknown
    case present
    case away
}

/// What the owner is doing on this Mac. Enumerated so future activities do not
/// become a pile of `isListening` / `isInCall` booleans.
public enum OwnerActivity: Equatable, Sendable {
    case idle
    case listeningToMusic(title: String?)
}

extension OwnerActivity: Codable {
    public var wireValue: String {
        switch self {
        case .idle: "idle"
        case .listeningToMusic: "listening_to_music"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
    }

    private enum Kind: String, Codable {
        case idle
        case listeningToMusic = "listening_to_music"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .idle:
            self = .idle
        case .listeningToMusic:
            self = .listeningToMusic(title: try container.decodeIfPresent(String.self, forKey: .title))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .type)
        case .listeningToMusic(let title):
            try container.encode(Kind.listeningToMusic, forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
        }
    }
}

/// Owner-side context that care rules, reactions and the Agent may read.
/// Detection (Now Playing, idle time, …) lives outside this type.
public struct OwnerContext: Equatable, Sendable {
    public var presence: OwnerPresence
    public var activity: OwnerActivity
    public var updatedAt: Date

    public init(
        presence: OwnerPresence = .unknown,
        activity: OwnerActivity = .idle,
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.presence = presence
        self.activity = activity
        self.updatedAt = updatedAt
    }

    public static let unknown = OwnerContext()
}

/// Visible situation of one desktop pet slot. This is the snapshot both
/// deterministic reactions and a later Agent turn should read — not a parallel
/// boolean machine in AppDelegate.
public struct PetSituation: Equatable, Sendable {
    public var slot: PetID
    public var care: PetCareState
    public var activity: PetActivity
    public var emotion: PetEmotion
    public var owner: OwnerContext
    public var companionPresent: Bool

    public init(
        slot: PetID,
        care: PetCareState,
        activity: PetActivity = .idle,
        emotion: PetEmotion = .content,
        owner: OwnerContext = .unknown,
        companionPresent: Bool = false
    ) {
        self.slot = slot
        self.care = care
        self.activity = activity
        self.emotion = emotion
        self.owner = owner
        self.companionPresent = companionPresent
    }
}
