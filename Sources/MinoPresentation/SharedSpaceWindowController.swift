import AppKit
import MinoDomain
import SwiftUI

@MainActor
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

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

@MainActor
package final class SharedSpaceModel: ObservableObject {
    @Published package var localAccountID: AccountID?
    @Published package var visitState: FriendVisitState = .away
    @Published package var timelineEvents: [PersonalTimelineEvent] = []
    @Published package var friends: [FriendProfile] = []
    @Published package var friendRequests: [FriendRequest] = []
    @Published package var selectedFriendshipID: FriendshipID?
    @Published package var activeVisitFriendshipID: FriendshipID?
    @Published package var friendOperationInProgress = false
    @Published package var friendErrorMessage: String?
    @Published package var visitErrorMessage: String?
    @Published package var agentMessage: String?
    @Published package var cloudSyncState: CloudSyncState = .localOnly
    @Published package var currentProfile: CurrentProfile?
    @Published package var authenticationState: SharedSpaceAuthenticationState = .offline
    @Published package var githubDeviceCodeWasAutoCopied = false
    @Published package var authenticationOperationInProgress = false
    @Published package var authenticationErrorMessage: String?
    @Published package var friendTimelineEvents: [FriendshipID: [PersonalTimelineEvent]] = [:]
    @Published package var friendTimelineLoading: Set<FriendshipID> = []
    @Published package var friendTimelineError: [FriendshipID: String] = [:]
    @Published package var profileOperationInProgress = false
    @Published package var profileErrorMessage: String?
    @Published package var profileSuccessMessage: String?
    @Published package var ownPetCare = PetCareState()
    @Published package var ownPetCharacterID: PetCharacterID?
    @Published package var friendCharacterIDs: [PetProfileID: PetCharacterID] = [:]
    @Published package var petCharacterSelectionState: PetCharacterSelectionState = .hidden

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

@MainActor
package final class SharedSpaceWindowController: NSWindowController, NSWindowDelegate {
    private let onVisibilityChange: (Bool) -> Void
    package let model = SharedSpaceModel()

    package init(
        debugIdentityLabel: String? = nil,
        identity: SharedSpaceIdentity = .localDefault,
        onFriendAction: @escaping (FriendDirectoryAction) -> Void,
        onProfileAction: @escaping (ProfileAction) -> Void,
        onOpenLetter: @escaping (LetterID) -> Void = { _ in },
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.onVisibilityChange = onVisibilityChange
        let rootView = SharedSpaceView(
            model: model,
            debugIdentityLabel: debugIdentityLabel,
            identity: identity,
            onFriendAction: onFriendAction,
            onProfileAction: onProfileAction,
            onOpenLetter: onOpenLetter
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1_080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = debugIdentityLabel.map { "Mino — \($0)" } ?? "Mino"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Color.minoCanvas)
        window.minSize = CGSize(width: 900, height: 640)
        window.setContentSize(CGSize(width: 1_080, height: 760))
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.fullScreenPrimary]

        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    package func show() {
        guard let window else { return }
        onVisibilityChange(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    package func windowWillClose(_ notification: Notification) {
        onVisibilityChange(false)
    }

    package func windowDidMiniaturize(_ notification: Notification) {
        onVisibilityChange(false)
    }

    package func windowDidDeminiaturize(_ notification: Notification) {
        onVisibilityChange(true)
    }
}
