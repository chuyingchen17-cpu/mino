import Foundation

public struct VisitProjection: Equatable, Sendable {
    public let accountID: AccountID
    public let ownPetID: PetProfileID
    public var ownPetIsVisible: Bool
    public var pendingVisits: [PetVisitID: Visit]
    public var activeOutgoingVisit: Visit?
    public var activeIncomingVisit: Visit?
    public var remotePet: PublicPetSnapshot?
    public var unresolvedVisitActions: [UUID: VisitAction]
    public var appearanceVersions: [PetProfileID: Int64]

    public init(accountID: AccountID, ownPetID: PetProfileID) {
        self.accountID = accountID
        self.ownPetID = ownPetID
        ownPetIsVisible = true
        pendingVisits = [:]
        activeOutgoingVisit = nil
        activeIncomingVisit = nil
        remotePet = nil
        unresolvedVisitActions = [:]
        appearanceVersions = [:]
    }
}

public enum VisitProjectionApplyResult: Equatable, Sendable {
    case applied
    case duplicate
    case requiresBootstrap
}

/// Pure, idempotent reconciliation of server Visit state. It emits no window,
/// scene, animation, network, or persistence side effects.
public struct VisitProjectionReducer: Sendable {
    public private(set) var projection: VisitProjection
    private var friendPets: [PetProfileID: PublicPetSnapshot] = [:]
    private var aggregateVersions: [String: Int64] = [:]
    private var recentEventIDs: Set<String> = []
    private var recentEventOrder: [String] = []

    public init(accountID: AccountID, ownPetID: PetProfileID) {
        projection = VisitProjection(accountID: accountID, ownPetID: ownPetID)
    }

    public mutating func reconcile(_ bootstrap: SyncBootstrap) {
        projection = VisitProjection(accountID: bootstrap.account.id, ownPetID: bootstrap.pet.petID)
        aggregateVersions.removeAll(keepingCapacity: true)
        friendPets = Dictionary(uniqueKeysWithValues: bootstrap.friendships.map {
            ($0.friend.pet.petID, $0.friend.pet)
        })
        projection.pendingVisits = Dictionary(uniqueKeysWithValues: bootstrap.pendingVisits.map { ($0.id, $0) })
        projection.unresolvedVisitActions = Dictionary(
            uniqueKeysWithValues: bootstrap.unresolvedVisitActions.map { ($0.id, $0) }
        )
        for friendship in bootstrap.friendships {
            projection.appearanceVersions[friendship.friend.pet.petID] = friendship.friend.pet.appearanceVersion
        }
        projection.appearanceVersions[bootstrap.pet.petID] = bootstrap.pet.appearanceVersion
        for visit in bootstrap.pendingVisits + bootstrap.activeVisits {
            aggregateVersions["visit:\(visit.id.rawValue)"] = visit.version
        }
        for visit in bootstrap.activeVisits { applyActiveVisit(visit) }
        recentEventIDs.removeAll(keepingCapacity: true)
        recentEventOrder.removeAll(keepingCapacity: true)
    }

    public mutating func apply(_ event: AccountEvent) -> VisitProjectionApplyResult {
        guard event.schemaVersion == 1 else { return .requiresBootstrap }
        guard !recentEventIDs.contains(event.id) else { return .duplicate }
        if let version = event.aggregateVersion {
            let key = "\(event.aggregateType):\(event.aggregateID)"
            if version <= (aggregateVersions[key] ?? 0) {
                remember(event.id)
                return .duplicate
            }
            aggregateVersions[key] = version
        }

        let result: VisitProjectionApplyResult
        switch event.type {
        case "visit.requested", "visit.activated", "visit.closed":
            guard let visit: Visit = decode(event.payload["visit"]) else {
                return .requiresBootstrap
            }
            if let pet: PublicPetSnapshot = decode(event.payload["publicPetSnapshot"]) {
                friendPets[pet.petID] = pet
                projection.appearanceVersions[pet.petID] = pet.appearanceVersion
            }
            applyVisit(visit)
            result = .applied

        case "visit.action.created", "visit.action.replied":
            guard let action: VisitAction = decode(event.payload["action"]) else {
                return .requiresBootstrap
            }
            if event.type == "visit.action.created", action.requiresResponse {
                projection.unresolvedVisitActions[action.id] = action
            }
            if let replyID = action.replyToActionID {
                projection.unresolvedVisitActions.removeValue(forKey: replyID)
            }
            result = .applied

        case "pet.appearance.updated":
            guard let pet: PublicPetSnapshot = decode(event.payload["publicPetSnapshot"]) else {
                return .requiresBootstrap
            }
            if pet.appearanceVersion > (projection.appearanceVersions[pet.petID] ?? 0) {
                friendPets[pet.petID] = pet
                projection.appearanceVersions[pet.petID] = pet.appearanceVersion
                if projection.remotePet?.petID == pet.petID { projection.remotePet = pet }
            }
            result = .applied

        case "friendship.requested", "friendship.accepted", "friendship.rejected",
             "friendship.closed", "letter.attached", "letter.delivered",
             "conversation.message.created", "conversation.ended",
             "agent.primary.changed", "pet.care.updated":
            result = .applied

        default:
            result = .requiresBootstrap
        }
        remember(event.id)
        return result
    }

    private mutating func applyVisit(_ visit: Visit) {
        projection.pendingVisits.removeValue(forKey: visit.id)
        if projection.activeOutgoingVisit?.id == visit.id { projection.activeOutgoingVisit = nil }
        if projection.activeIncomingVisit?.id == visit.id {
            projection.activeIncomingVisit = nil
            projection.remotePet = nil
        }
        switch visit.status {
        case .pending:
            projection.pendingVisits[visit.id] = visit
        case .active:
            applyActiveVisit(visit)
        case .closed:
            break
        }
        projection.ownPetIsVisible = projection.activeOutgoingVisit == nil
    }

    private mutating func applyActiveVisit(_ visit: Visit) {
        if visit.visitorOwnerAccountID == projection.accountID {
            projection.activeOutgoingVisit = visit
        }
        if visit.hostAccountID == projection.accountID {
            projection.activeIncomingVisit = visit
            projection.remotePet = friendPets[visit.visitorPetID]
        }
        projection.ownPetIsVisible = projection.activeOutgoingVisit == nil
    }

    private mutating func remember(_ eventID: String) {
        guard recentEventIDs.insert(eventID).inserted else { return }
        recentEventOrder.append(eventID)
        if recentEventOrder.count > 512 {
            recentEventIDs.remove(recentEventOrder.removeFirst())
        }
    }

    private func decode<Value: Decodable>(_ value: JSONValue?) -> Value? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(Value.self, from: data)
    }
}
