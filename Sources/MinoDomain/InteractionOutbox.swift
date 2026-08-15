import Foundation

public struct InteractionOutboxEntry: Codable, Equatable, Sendable {
    public let command: InteractionCommand
    public let enqueuedAt: Date
    public var attemptCount: Int
    public var nextAttemptAt: Date
    public var lastErrorCode: String?

    public init(
        command: InteractionCommand,
        enqueuedAt: Date,
        attemptCount: Int = 0,
        nextAttemptAt: Date,
        lastErrorCode: String? = nil
    ) {
        self.command = command
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastErrorCode = lastErrorCode
    }
}

public struct OutboxRetryPolicy: Equatable, Sendable {
    public let baseDelay: TimeInterval
    public let maximumDelay: TimeInterval

    public init(baseDelay: TimeInterval = 2, maximumDelay: TimeInterval = 300) {
        self.baseDelay = max(0, baseDelay)
        self.maximumDelay = max(self.baseDelay, maximumDelay)
    }

    public func delay(afterAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, min(attempt - 1, 20))
        return min(maximumDelay, baseDelay * pow(2, Double(exponent)))
    }
}

public enum InteractionOutboxError: Error, Equatable, Sendable {
    case full(limit: Int)
}

public protocol InteractionOutboxStore: Sendable {
    @discardableResult
    func enqueue(_ command: InteractionCommand, at date: Date) async throws -> Bool
    func dueEntries(at date: Date, limit: Int) async throws -> [InteractionOutboxEntry]
    func markDelivered(idempotencyKey: UUID) async throws
    func markFailed(idempotencyKey: UUID, errorCode: String, at date: Date) async throws
    func pendingCount() async throws -> Int
    func clear() async throws
}
