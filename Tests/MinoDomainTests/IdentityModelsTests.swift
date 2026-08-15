import Foundation
import Testing

@testable import MinoDomain

@Test
func strongIdentifiersEncodeAsStrings() throws {
    let accountID = AccountID(rawValue: "account_123")
    let coupleID = CoupleID(rawValue: "couple_456")

    #expect(String(data: try JSONEncoder().encode(accountID), encoding: .utf8) == "\"account_123\"")
    #expect(String(data: try JSONEncoder().encode(coupleID), encoding: .utf8) == "\"couple_456\"")
}

@Test
func retryPolicyUsesBoundedExponentialBackoff() {
    let policy = OutboxRetryPolicy(baseDelay: 2, maximumDelay: 10)

    #expect(policy.delay(afterAttempt: 1) == 2)
    #expect(policy.delay(afterAttempt: 2) == 4)
    #expect(policy.delay(afterAttempt: 3) == 8)
    #expect(policy.delay(afterAttempt: 4) == 10)
    #expect(policy.delay(afterAttempt: 100) == 10)
}
