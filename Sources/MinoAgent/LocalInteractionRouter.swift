import Foundation
import MinoDomain

public struct LocalInteractionRoute: Equatable, Sendable {
    public let immediateSpeech: String?
    public let emotion: PetEmotion?
    public let activity: PetActivity?
    public let startsWalk: Bool
    public let modelObservation: AgentObservation?

    public init(
        immediateSpeech: String? = nil,
        emotion: PetEmotion? = nil,
        activity: PetActivity? = nil,
        startsWalk: Bool = false,
        modelObservation: AgentObservation? = nil
    ) {
        self.immediateSpeech = immediateSpeech
        self.emotion = emotion
        self.activity = activity
        self.startsWalk = startsWalk
        self.modelObservation = modelObservation
    }
}

/// Keeps tactile pet interactions responsive while batching the few moments that
/// are worth asking the model about.
public actor LocalInteractionRouter {
    public struct Configuration: Equatable, Sendable {
        public let ownerMessageDebounceInterval: TimeInterval
        public let ownerMessageMinimumModelInterval: TimeInterval
        public let localContextWindow: TimeInterval
        public let localInteractionSummaryCooldown: TimeInterval
        public let maximumBufferedInteractions: Int
        public let periodicWakeQuietWindow: TimeInterval
        public let periodicWakeMinimumInterval: TimeInterval

        public init(
            ownerMessageDebounceInterval: TimeInterval = 0.6,
            ownerMessageMinimumModelInterval: TimeInterval = 3,
            localContextWindow: TimeInterval = 300,
            localInteractionSummaryCooldown: TimeInterval = 300,
            maximumBufferedInteractions: Int = 12,
            periodicWakeQuietWindow: TimeInterval = 600,
            periodicWakeMinimumInterval: TimeInterval = 1_200
        ) {
            self.ownerMessageDebounceInterval = max(0, ownerMessageDebounceInterval)
            self.ownerMessageMinimumModelInterval = max(0, ownerMessageMinimumModelInterval)
            self.localContextWindow = max(1, localContextWindow)
            self.localInteractionSummaryCooldown = max(1, localInteractionSummaryCooldown)
            self.maximumBufferedInteractions = max(1, maximumBufferedInteractions)
            self.periodicWakeQuietWindow = max(0, periodicWakeQuietWindow)
            self.periodicWakeMinimumInterval = max(1, periodicWakeMinimumInterval)
        }
    }

    private enum BufferedKind: Equatable, Sendable {
        case feeding
        case play
    }

    private struct BufferedInteraction: Equatable, Sendable {
        let kind: BufferedKind
        let occurredAt: Date
        let summary: String
    }

    private struct PendingOwnerMessage: Equatable, Sendable {
        var text: String
        var deadline: Date
    }

    public let configuration: Configuration
    private let startedAt: Date
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID

    private var bufferedInteractions: [BufferedInteraction] = []
    private var pendingOwnerMessage: PendingOwnerMessage?
    private var lastModelSubmissionAt: Date?
    private var lastLocalInteractionSummaryAt: Date?
    private var lastPeriodicWakeAt: Date?
    private var touchCount = 0

    public init(
        configuration: Configuration = Configuration(),
        startedAt: Date = Date(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeUUID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.configuration = configuration
        self.startedAt = startedAt
        self.now = now
        self.makeUUID = makeUUID
    }

    public func routePetTouch(
        occurredAt: Date? = nil
    ) -> LocalInteractionRoute {
        _ = occurredAt ?? now()
        touchCount += 1
        return LocalInteractionRoute(
            immediateSpeech: touchCount % 5 == 0 ? "一直都在呢。" : "摸摸收到啦。",
            emotion: .happy,
            activity: .petting
        )
    }

    public func routeOwnerInteraction(
        _ stimulus: PetInteractionStimulus,
        occurredAt: Date? = nil
    ) -> LocalInteractionRoute {
        let eventDate = occurredAt ?? now()
        switch stimulus {
        case .feeding(let foodName):
            appendBufferedInteraction(
                .feeding,
                summary: foodName.map { "投喂了\($0)" } ?? "投喂了一次",
                at: eventDate
            )
            return LocalInteractionRoute(
                immediateSpeech: "好吃，先收下啦。",
                emotion: .happy,
                activity: .eating,
                modelObservation: dueLocalInteractionSummary(at: eventDate)
            )

        case .play:
            appendBufferedInteraction(.play, summary: "陪宠物玩了一会儿", at: eventDate)
            return LocalInteractionRoute(
                immediateSpeech: "来啦，一起动一动。",
                emotion: .playful,
                activity: .playing,
                modelObservation: dueLocalInteractionSummary(at: eventDate)
            )

        case .message(let text):
            return routeOwnerMessage(text, occurredAt: eventDate)
        }
    }

    public func routeOwnerMessage(
        _ text: String,
        occurredAt: Date? = nil
    ) -> LocalInteractionRoute {
        let eventDate = occurredAt ?? now()
        let normalized = sanitized(text)
        guard !normalized.isEmpty else {
            pendingOwnerMessage = nil
            return LocalInteractionRoute()
        }

        pendingOwnerMessage = PendingOwnerMessage(
            text: normalized,
            deadline: eventDate.addingTimeInterval(configuration.ownerMessageDebounceInterval)
        )
        return LocalInteractionRoute(
            immediateSpeech: "我听见啦，认真想想再回你。",
            emotion: .happy,
            activity: .celebrating
        )
    }

    public func nextOwnerMessageDeadline() -> Date? {
        pendingOwnerMessage?.deadline
    }

    public func flushDebouncedOwnerMessageIfDue(
        at date: Date? = nil
    ) -> AgentObservation? {
        let eventDate = date ?? now()
        guard var pending = pendingOwnerMessage else { return nil }
        guard eventDate >= pending.deadline else { return nil }
        if let lastModelSubmissionAt,
           eventDate.timeIntervalSince(lastModelSubmissionAt)
                < configuration.ownerMessageMinimumModelInterval {
            pending.deadline = lastModelSubmissionAt.addingTimeInterval(
                configuration.ownerMessageMinimumModelInterval
            )
            pendingOwnerMessage = pending
            return nil
        }

        pendingOwnerMessage = nil
        lastModelSubmissionAt = eventDate
        return AgentObservation(
            id: makeUUID(),
            occurredAt: eventDate,
            kind: .ownerMessage(text: pending.text)
        )
    }

    public func periodicWakeObservation(
        hasFriends: Bool,
        agentIsProcessing: Bool,
        at date: Date? = nil
    ) -> AgentObservation? {
        let eventDate = date ?? now()
        pruneInteractions(at: eventDate)
        guard hasFriends, !agentIsProcessing else { return nil }
        guard eventDate.timeIntervalSince(startedAt) >= configuration.periodicWakeQuietWindow else {
            return nil
        }
        if let lastPeriodicWakeAt,
           eventDate.timeIntervalSince(lastPeriodicWakeAt)
                < configuration.periodicWakeMinimumInterval {
            return nil
        }
        guard !bufferedInteractions.isEmpty || pendingOwnerMessage != nil else {
            return nil
        }

        lastPeriodicWakeAt = eventDate
        if !bufferedInteractions.isEmpty {
            let observation = makeLocalInteractionSummaryObservation(at: eventDate)
            bufferedInteractions.removeAll()
            lastLocalInteractionSummaryAt = eventDate
            lastModelSubmissionAt = eventDate
            return observation
        }

        lastModelSubmissionAt = eventDate
        return AgentObservation(
            id: makeUUID(),
            occurredAt: eventDate,
            kind: .periodicWake
        )
    }

    private func appendBufferedInteraction(
        _ kind: BufferedKind,
        summary: String,
        at date: Date
    ) {
        pruneInteractions(at: date)
        bufferedInteractions.append(
            BufferedInteraction(
                kind: kind,
                occurredAt: date,
                summary: sanitized(summary)
            )
        )
        if bufferedInteractions.count > configuration.maximumBufferedInteractions {
            bufferedInteractions.removeFirst(
                bufferedInteractions.count - configuration.maximumBufferedInteractions
            )
        }
    }

    private func dueLocalInteractionSummary(at date: Date) -> AgentObservation? {
        pruneInteractions(at: date)
        guard bufferedInteractions.count >= 2 else { return nil }
        if let lastLocalInteractionSummaryAt,
           date.timeIntervalSince(lastLocalInteractionSummaryAt)
                < configuration.localInteractionSummaryCooldown {
            return nil
        }
        if let lastModelSubmissionAt,
           date.timeIntervalSince(lastModelSubmissionAt)
                < configuration.ownerMessageMinimumModelInterval {
            return nil
        }

        let observation = makeLocalInteractionSummaryObservation(at: date)
        bufferedInteractions.removeAll()
        lastLocalInteractionSummaryAt = date
        lastModelSubmissionAt = date
        return observation
    }

    private func makeLocalInteractionSummaryObservation(at date: Date) -> AgentObservation {
        let summary = localInteractionSummary(at: date)
        return AgentObservation(
            id: makeUUID(),
            occurredAt: date,
            kind: .ownerInteraction(.message(text: summary))
        )
    }

    private func localInteractionSummary(at date: Date) -> String {
        let feedingCount = bufferedInteractions.filter { $0.kind == .feeding }.count
        let playCount = bufferedInteractions.filter { $0.kind == .play }.count
        let firstDate = bufferedInteractions.first?.occurredAt ?? date
        let minutes = max(1, Int(ceil(date.timeIntervalSince(firstDate) / 60)))
        var parts: [String] = []
        if feedingCount > 0 {
            parts.append("投喂 \(feedingCount) 次")
        }
        if playCount > 0 {
            parts.append("陪玩 \(playCount) 次")
        }
        let activityText = parts.isEmpty ? "轻量互动" : parts.joined(separator: "、")
        return "过去 \(minutes) 分钟主人和宠物进行了\(activityText)"
    }

    private func pruneInteractions(at date: Date) {
        let earliest = date.addingTimeInterval(-configuration.localContextWindow)
        bufferedInteractions.removeAll { $0.occurredAt < earliest }
    }

    private func sanitized(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(500))
    }
}
