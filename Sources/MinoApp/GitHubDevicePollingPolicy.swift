import Foundation
import MinoInfrastructure

enum GitHubDevicePollingFailure: Error, Equatable, Sendable {
    case expired
    case denied
    case failed

    var userMessage: String {
        switch self {
        case .expired:
            "匹配码已过期，请重新获取"
        case .denied:
            "你已取消 GitHub 授权，可以重新登录"
        case .failed:
            "无法完成 GitHub 登录，请重新尝试"
        }
    }
}

enum GitHubDevicePollingDecision: Equatable, Sendable {
    case retry(afterSeconds: Int)
    case stop(GitHubDevicePollingFailure)
}

/// Separates recoverable polling failures from terminal Device Flow outcomes.
///
/// The caller owns the polling interval and cancellation. A retry never extends
/// the authorization deadline supplied by GitHub.
func githubDevicePollingDecision(
    for error: Error,
    currentInterval: Int,
    now: Date = Date(),
    expiresAt: Date
) -> GitHubDevicePollingDecision {
    if let backendError = error as? BackendClientError,
       case .httpStatus(_, let code) = backendError {
        switch code {
        case "github_access_denied":
            return .stop(.denied)
        case "github_device_expired", "github_device_code_invalid":
            return .stop(.expired)
        default:
            break
        }
    }

    // Poll requests are scheduled in whole seconds. If less than one second is
    // left, another request would necessarily outlive GitHub's authorization.
    guard expiresAt.timeIntervalSince(now) >= 1 else { return .stop(.expired) }
    guard let backendError = error as? BackendClientError else {
        return .stop(.failed)
    }

    switch backendError {
    case .transport:
        return .retry(afterSeconds: retryDelay(
            currentInterval: currentInterval,
            increasesForRateLimit: false,
            now: now,
            expiresAt: expiresAt
        ))
    case .httpStatus(let statusCode, _) where statusCode == 429:
        return .retry(afterSeconds: retryDelay(
            currentInterval: currentInterval,
            increasesForRateLimit: true,
            now: now,
            expiresAt: expiresAt
        ))
    case .httpStatus(let statusCode, _) where (500...599).contains(statusCode):
        return .retry(afterSeconds: retryDelay(
            currentInterval: currentInterval,
            increasesForRateLimit: false,
            now: now,
            expiresAt: expiresAt
        ))
    case .invalidRequest, .invalidResponse, .decoding, .httpStatus:
        return .stop(.failed)
    }
}

private func retryDelay(
    currentInterval: Int,
    increasesForRateLimit: Bool,
    now: Date,
    expiresAt: Date
) -> Int {
    let normalizedInterval = min(30, max(1, currentInterval))
    let proposedInterval = increasesForRateLimit
        ? min(30, normalizedInterval + 5)
        : normalizedInterval
    let remainingSeconds = max(1, Int(expiresAt.timeIntervalSince(now).rounded(.down)))
    return min(proposedInterval, remainingSeconds)
}
