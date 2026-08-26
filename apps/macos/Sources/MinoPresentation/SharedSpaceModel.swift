import AppKit
import MinoDomain
import SwiftUI

package enum FriendDirectoryAction: Sendable {
    case refresh
    case addFriend(AccountID)
    case respondToRequest(FriendRequestID, FriendRequestDecision)
    case selectFriend(FriendshipID)
    case inviteFriendPet(FriendshipID)
    case sendOwnPet(FriendshipID)
    case respondToVisit(VisitResponse)
    case endVisit
}

package enum ProfileAction: Sendable {
    case signInWithGitHub
    case cancelSignIn
    case signOut
    case saveProfile(accountName: String, petName: String)
    case selectPetCharacter(PetCharacterID)
    case acknowledgePetCharacterSelection
}

/// Presentation-only state for the one-time, permanently locked character choice.
/// The app owns persistence and moves this state after local/outbox/server results.
package enum PetCharacterSelectionState: Equatable, Sendable {
    case hidden
    case required(preselected: PetCharacterID? = nil)
    case saving(PetCharacterID)
    case pendingSync(PetCharacterID)
    case confirmed(PetCharacterID)
    case conflict(authoritative: PetCharacterID)
    case failed(preselected: PetCharacterID?, message: String)

    package var isPresented: Bool {
        self != .hidden
    }
}

package enum SharedSpaceAuthenticationState: Equatable, Sendable {
    case offline
    case signedOut
    case waitingForGitHub(userCode: String, verificationURL: URL)
    case signedIn
}

package enum CloudSyncState: Equatable, Sendable {
    case localOnly
    case connecting
    case synced
    case pending
    case unavailable

    package var statusText: String {
        switch self {
        case .localOnly: "仅保存在此 Mac"
        case .connecting: "正在同步"
        case .synced: "已同步"
        case .pending: "稍后同步"
        case .unavailable: "暂时离线"
        }
    }

    package var systemImage: String {
        switch self {
        case .localOnly: "macbook"
        case .connecting: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.circle.fill"
        case .pending: "clock.arrow.circlepath"
        case .unavailable: "wifi.slash"
        }
    }

    package var allowsAuthoritativeClaim: Bool {
        self == .synced
    }
}

package enum AddFriendAccountIDValidationError: Error, Equatable, Sendable {
    case empty
    case invalidFormat
    case ownAccount

    package var message: String {
        switch self {
        case .empty: "请粘贴好友的账号 ID"
        case .invalidFormat: "账号 ID 格式不完整，请从好友个人页重新复制"
        case .ownAccount: "这是你自己的账号 ID"
        }
    }
}

package enum AddFriendAccountIDValidator {
    package static func validate(
        _ rawValue: String,
        localAccountID: AccountID?
    ) -> Result<AccountID, AddFriendAccountIDValidationError> {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let uuid = UUID(uuidString: trimmed) else { return .failure(.invalidFormat) }

        if let localAccountID {
            if let localUUID = UUID(uuidString: localAccountID.rawValue), localUUID == uuid {
                return .failure(.ownAccount)
            }
            if localAccountID.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame {
                return .failure(.ownAccount)
            }
        }
        return .success(AccountID(rawValue: uuid.uuidString.lowercased()))
    }
}

package struct SharedSpaceIdentity: Equatable, Sendable {
    package let localPetName: String
    package let fallbackFriendPetName: String

    package init(localPetName: String, fallbackFriendPetName: String) {
        self.localPetName = localPetName
        self.fallbackFriendPetName = fallbackFriendPetName
    }

    package static let localDefault = SharedSpaceIdentity(
        localPetName: "奶糖",
        fallbackFriendPetName: "好友宠物"
    )
}

package enum FriendVisitState: Equatable, Sendable {
    case away
    case sendingInvitation
    case invitationSent
    case consideringInvitation
    case visiting
    case ownPetVisiting
    case returning
}

/// Presentation store for the shared-space window. Views observe properties they
/// read; AppDelegate remains the only writer of account facts.
@Observable
@MainActor
package final class SharedSpaceModel {
    package var localAccountID: AccountID?
    package var visitState: FriendVisitState = .away
    package var timelineEvents: [PersonalTimelineEvent] = []
    package var friends: [FriendProfile] = []
    package var friendRequests: [FriendRequest] = []
    package var selectedFriendshipID: FriendshipID?
    package var activeVisitFriendshipID: FriendshipID?
    package var friendOperationInProgress = false
    package var friendErrorMessage: String?
    package var visitErrorMessage: String?
    package var agentMessage: String?
    package var cloudSyncState: CloudSyncState = .localOnly
    package var currentProfile: CurrentProfile?
    package var authenticationState: SharedSpaceAuthenticationState = .offline
    package var githubDeviceCodeWasAutoCopied = false
    package var authenticationOperationInProgress = false
    package var authenticationErrorMessage: String?
    package var friendTimelineEvents: [FriendshipID: [PersonalTimelineEvent]] = [:]
    package var friendTimelineLoading: Set<FriendshipID> = []
    package var friendTimelineError: [FriendshipID: String] = [:]
    package var profileOperationInProgress = false
    package var profileErrorMessage: String?
    package var profileSuccessMessage: String?
    package var ownPetCare = PetCareState()
    package var ownPetCharacterID: PetCharacterID?
    package var friendCharacterIDs: [PetProfileID: PetCharacterID] = [:]
    package var petCharacterSelectionState: PetCharacterSelectionState = .hidden

    package var selectedFriend: FriendProfile? {
        guard let selectedFriendshipID else { return nil }
        return friends.first { $0.friendshipID == selectedFriendshipID }
    }

    package var selectedFriendEvents: [PersonalTimelineEvent] {
        guard let friendshipID = selectedFriend?.friendshipID else { return [] }
        return (friendTimelineEvents[friendshipID] ?? [])
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    package var reversedTimelineEvents: [PersonalTimelineEvent] {
        Array(timelineEvents.reversed())
    }

    package func identity(fallingBackTo fallback: SharedSpaceIdentity) -> SharedSpaceIdentity {
        SharedSpaceIdentity(
            localPetName: currentProfile?.petName ?? fallback.localPetName,
            fallbackFriendPetName: fallback.fallbackFriendPetName
        )
    }

    package func characterID(for friend: FriendProfile) -> PetCharacterID {
        friendCharacterIDs[friend.petID] ?? friend.characterID ?? .retrieverYellow
    }

    package func isFriendTimelineLoading(_ friendshipID: FriendshipID) -> Bool {
        friendTimelineLoading.contains(friendshipID)
    }

    /// Enters the browser hand-off state and copies the complete matching code
    /// exactly once. Keeping both operations together prevents a rendered view
    /// from repeatedly replacing the user's clipboard.
    @discardableResult
    package func beginGitHubAuthorization(
        userCode rawUserCode: String,
        verificationURL: URL,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let userCode = GitHubDeviceCodeClipboard.normalizedCode(rawUserCode) ?? rawUserCode
        let didCopy = GitHubDeviceCodeClipboard.copy(userCode, to: pasteboard)
        githubDeviceCodeWasAutoCopied = didCopy
        authenticationState = .waitingForGitHub(
            userCode: userCode,
            verificationURL: verificationURL
        )
        return didCopy
    }
}
