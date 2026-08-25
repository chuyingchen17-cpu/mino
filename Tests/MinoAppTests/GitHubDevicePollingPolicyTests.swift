import Foundation
import MinoInfrastructure
import Testing

@testable import MinoApp

private let pollingNow = Date(timeIntervalSince1970: 1_000)
private let pollingExpiry = Date(timeIntervalSince1970: 1_600)

@Test func githubDevicePollingRetriesTransientFailuresBeforeExpiry() {
    #expect(githubDevicePollingDecision(
        for: BackendClientError.transport("network lost"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .retry(afterSeconds: 4))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 429, code: "rate_limited"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .retry(afterSeconds: 9))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 500, code: nil),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .retry(afterSeconds: 4))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 503, code: "github_unavailable"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .retry(afterSeconds: 4))
}

@Test func githubDevicePollingNeverWaitsPastTheAuthorizationDeadline() {
    #expect(githubDevicePollingDecision(
        for: BackendClientError.transport("network lost"),
        currentInterval: 10,
        now: pollingExpiry.addingTimeInterval(-3),
        expiresAt: pollingExpiry
    ) == .retry(afterSeconds: 3))
}

@Test func githubDevicePollingStopsTransientFailuresAtExpiry() {
    #expect(githubDevicePollingDecision(
        for: BackendClientError.transport("network lost"),
        currentInterval: 4,
        now: pollingExpiry,
        expiresAt: pollingExpiry
    ) == .stop(.expired))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 503, code: "github_unavailable"),
        currentInterval: 4,
        now: pollingExpiry.addingTimeInterval(1),
        expiresAt: pollingExpiry
    ) == .stop(.expired))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.transport("network lost"),
        currentInterval: 4,
        now: pollingExpiry.addingTimeInterval(-0.5),
        expiresAt: pollingExpiry
    ) == .stop(.expired))
}

@Test func githubDevicePollingMapsExplicitTerminalOutcomes() {
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 400, code: "github_access_denied"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .stop(.denied))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 400, code: "github_device_expired"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .stop(.expired))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 400, code: "github_device_code_invalid"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .stop(.expired))
}

@Test func githubDevicePollingDoesNotRetryPermanentOrMalformedResponses() {
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 400, code: "github_authorization_failed"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .stop(.failed))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.httpStatus(statusCode: 401, code: "unauthorized"),
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .stop(.failed))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.invalidResponse,
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .stop(.failed))
    #expect(githubDevicePollingDecision(
        for: BackendClientError.decoding,
        currentInterval: 4,
        now: pollingNow,
        expiresAt: pollingExpiry
    ) == .stop(.failed))
}

@Test func githubDevicePollingFailureMessagesDescribeTheActualOutcome() {
    #expect(GitHubDevicePollingFailure.expired.userMessage == "匹配码已过期，请重新获取")
    #expect(GitHubDevicePollingFailure.denied.userMessage == "你已取消 GitHub 授权，可以重新登录")
    #expect(GitHubDevicePollingFailure.failed.userMessage == "无法完成 GitHub 登录，请重新尝试")
}
