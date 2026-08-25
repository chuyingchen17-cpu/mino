import AppKit
import Foundation
import MinoDomain
import Testing
@testable import MinoPresentation

@Test(arguments: [
    (CloudSyncState.localOnly, "仅保存在此 Mac", "macbook", false),
    (CloudSyncState.connecting, "正在同步", "arrow.triangle.2.circlepath", false),
    (CloudSyncState.synced, "已同步", "checkmark.circle.fill", true),
    (CloudSyncState.pending, "稍后同步", "clock.arrow.circlepath", false),
    (CloudSyncState.unavailable, "暂时离线", "wifi.slash", false)
])
func cloudSyncStateUsesTruthfulStatusCopy(
    state: CloudSyncState,
    statusText: String,
    symbol: String,
    allowsAuthoritativeClaim: Bool
) {
    #expect(state.statusText == statusText)
    #expect(state.systemImage == symbol)
    #expect(state.allowsAuthoritativeClaim == allowsAuthoritativeClaim)
}

@MainActor
@Test func sharedSpaceStartsInLocalOnlyMode() {
    let model = SharedSpaceModel()

    #expect(model.authenticationState == .offline)
    #expect(model.cloudSyncState == .localOnly)
    #expect(!model.cloudSyncState.allowsAuthoritativeClaim)
}

@MainActor
@Test func githubAuthorizationCopiesTheCompleteMatchingCodeBeforeWaiting() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("mino-tests-\(UUID().uuidString)"))
    let model = SharedSpaceModel()
    let verificationURL = try #require(URL(string: "https://github.com/login/device"))

    let didCopy = model.beginGitHubAuthorization(
        userCode: " 0370-88DC\n",
        verificationURL: verificationURL,
        pasteboard: pasteboard
    )

    #expect(didCopy)
    #expect(model.githubDeviceCodeWasAutoCopied)
    #expect(pasteboard.string(forType: .string) == "0370-88DC")
    #expect(model.authenticationState == .waitingForGitHub(
        userCode: "0370-88DC",
        verificationURL: verificationURL
    ))
}

@MainActor
@Test func emptyGitHubMatchingCodeDoesNotReplaceExistingClipboardContent() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("mino-tests-\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.setString("keep-me", forType: .string)

    let didCopy = GitHubDeviceCodeClipboard.copy(" \n\t ", to: pasteboard)

    #expect(!didCopy)
    #expect(pasteboard.string(forType: .string) == "keep-me")
}

@MainActor
@Test func githubMatchingCodeRequiresAllEightCharactersAndCanonicalizesTheSeparator() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("mino-tests-\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.setString("keep-me", forType: .string)

    #expect(GitHubDeviceCodeClipboard.normalizedCode("037088dc") == "0370-88DC")
    #expect(GitHubDeviceCodeClipboard.normalizedCode("0") == nil)
    #expect(!GitHubDeviceCodeClipboard.copy("0", to: pasteboard))
    #expect(pasteboard.string(forType: .string) == "keep-me")

    #expect(GitHubDeviceCodeClipboard.copy("037088dc", to: pasteboard))
    #expect(pasteboard.string(forType: .string) == "0370-88DC")
}

@Test func addFriendAccountIDValidationTrimsAndCanonicalizesUUID() throws {
    let validated = try AddFriendAccountIDValidator.validate(
        "  00000000-0000-4000-8000-00000000000B\n",
        localAccountID: AccountID(rawValue: "00000000-0000-4000-8000-00000000000a")
    ).get()

    #expect(validated.rawValue == "00000000-0000-4000-8000-00000000000b")
}

@Test(arguments: [
    ("", AddFriendAccountIDValidationError.empty),
    ("not-an-account-id", AddFriendAccountIDValidationError.invalidFormat),
    ("00000000-0000-4000-8000-00000000000A", AddFriendAccountIDValidationError.ownAccount)
])
func addFriendAccountIDValidationRejectsInvalidInput(
    rawValue: String,
    expectedError: AddFriendAccountIDValidationError
) {
    let result = AddFriendAccountIDValidator.validate(
        rawValue,
        localAccountID: AccountID(rawValue: "00000000-0000-4000-8000-00000000000a")
    )

    switch result {
    case .success:
        Issue.record("Expected validation to fail")
    case .failure(let error):
        #expect(error == expectedError)
        #expect(!error.message.isEmpty)
    }
}
