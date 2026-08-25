import Foundation
import Testing
@testable import MinoApp
@testable import MinoDomain
import MinoInfrastructure

private actor StubEventSource: AccountEventSource {
    private let bootstraps: [SyncBootstrap]
    private var pages: [AccountEventPage]
    private(set) var bootstrapCallCount = 0
    private(set) var eventCallCount = 0

    init(bootstraps: [SyncBootstrap], pages: [AccountEventPage]) {
        self.bootstraps = bootstraps
        self.pages = pages
    }

    func fetchSyncBootstrap() async throws -> SyncBootstrap {
        let index = min(bootstrapCallCount, bootstraps.count - 1)
        bootstrapCallCount += 1
        return bootstraps[index]
    }

    func fetchAccountEvents(
        after cursor: Int64,
        limit: Int,
        timelineVisible: Bool?
    ) async throws -> AccountEventPage {
        _ = limit
        _ = timelineVisible
        eventCallCount += 1
        guard !pages.isEmpty else { return AccountEventPage(events: [], nextCursor: cursor) }
        return pages.removeFirst()
    }
}

private actor RecordingCursorStore: AccountEventCursorStore {
    private(set) var values: [Int64] = []

    func load(for accountID: AccountID) async throws -> Int64? {
        _ = accountID
        return values.last
    }

    func save(_ cursor: Int64, for accountID: AccountID) async throws {
        _ = accountID
        values.append(cursor)
    }

    func clear(for accountID: AccountID) async throws {
        _ = accountID
        values.removeAll()
    }
}

private actor EventRecorder {
    private(set) var sequences: [Int64] = []
    func append(_ sequence: Int64) { sequences.append(sequence) }
}

private actor FlakyBootstrapSource: AccountEventSource {
    let bootstrap: SyncBootstrap
    private(set) var bootstrapCallCount = 0

    init(bootstrap: SyncBootstrap) {
        self.bootstrap = bootstrap
    }

    func fetchSyncBootstrap() async throws -> SyncBootstrap {
        bootstrapCallCount += 1
        if bootstrapCallCount == 1 {
            throw BackendClientError.transport("offline")
        }
        return bootstrap
    }

    func fetchAccountEvents(
        after cursor: Int64,
        limit: Int,
        timelineVisible: Bool?
    ) async throws -> AccountEventPage {
        _ = limit
        _ = timelineVisible
        return AccountEventPage(events: [], nextCursor: cursor)
    }
}

@MainActor
private final class SyncStatusRecorder {
    var values: [AccountEventSyncStatus] = []
}

private final class SilentSignalService: AccountEventSignalService, @unchecked Sendable {
    private let stream: AsyncThrowingStream<AccountRealtimeSignal, Error>
    private let continuation: AsyncThrowingStream<AccountRealtimeSignal, Error>.Continuation

    init() {
        let pair = AsyncThrowingStream<AccountRealtimeSignal, Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    deinit { continuation.finish() }

    func signals() async throws -> AsyncThrowingStream<AccountRealtimeSignal, Error> { stream }
}

@Test func socialOutboxRetriesOnlyTransientFailures() {
    #expect(shouldRetrySocialMutation(BackendClientError.transport("offline")))
    #expect(shouldRetrySocialMutation(BackendClientError.httpStatus(statusCode: 429, code: "rate_limited")))
    #expect(shouldRetrySocialMutation(BackendClientError.httpStatus(statusCode: 503, code: nil)))
    #expect(!shouldRetrySocialMutation(BackendClientError.invalidRequest))
    #expect(!shouldRetrySocialMutation(BackendClientError.httpStatus(statusCode: 400, code: "invalid_request")))
    #expect(!shouldRetrySocialMutation(BackendClientError.httpStatus(statusCode: 409, code: "host_busy")))
}

private actor RecordingMutationOutbox: SocialMutationOutboxStore {
    private var values: [SocialMutation] = []

    func enqueue(_ mutation: SocialMutation) async throws { values.append(mutation) }
    func due(at date: Date) async throws -> [SocialMutation] {
        values.filter { $0.nextAttemptAt <= date }
    }
    func markSucceeded(_ id: UUID) async throws { values.removeAll { $0.id == id } }
    func markFailed(_ id: UUID, retryAt: Date) async throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].attemptCount += 1
        values[index].nextAttemptAt = retryAt
    }
    func clear() async throws { values.removeAll() }
}

@Test func offlineCareInteractionRemainsInThePersistentMutationBoundary() async throws {
    let outbox = RecordingMutationOutbox()
    let coordinator = VisitCoordinator(
        backend: OfflineBackendService(),
        outbox: outbox
    )
    let interactionID = UUID()

    do {
        _ = try await coordinator.interactWithPet(
            petID: PetProfileID(rawValue: "pet-a"),
            kind: .feed,
            idempotencyKey: interactionID
        )
        Issue.record("Offline backend should defer delivery")
    } catch {
        #expect(error as? BackendServiceError == .offline)
    }

    let pending = try await outbox.due(at: .distantFuture)
    #expect(pending.count == 1)
    #expect(pending.first?.kind == .petInteraction)
    #expect(pending.first?.idempotencyKey == interactionID)
}

@Test func offlineCharacterSelectionRemainsInThePersistentMutationBoundary() async throws {
    let outbox = RecordingMutationOutbox()
    let coordinator = VisitCoordinator(
        backend: OfflineBackendService(),
        outbox: outbox
    )
    let selectionID = UUID()

    do {
        _ = try await coordinator.updateOwnPetAppearance(
            characterID: .malteseWhite,
            idempotencyKey: selectionID
        )
        Issue.record("Offline backend should defer character selection")
    } catch {
        #expect(error as? BackendServiceError == .offline)
    }

    let pending = try await outbox.due(at: .distantFuture)
    #expect(pending.count == 1)
    #expect(pending.first?.kind == .petAppearanceSelection)
    #expect(pending.first?.idempotencyKey == selectionID)
    #expect(pending.first?.body["appearance"]?["body"]?.stringValue == "maltese-white")
}

@MainActor
@Test func accountSyncSortsEventsAndAdvancesCursorOnlyAfterEachHandler() async throws {
    let fixture = makeBootstrap(cursor: 0)
    let source = StubEventSource(
        bootstraps: [fixture],
        pages: [AccountEventPage(events: [makeEvent(sequence: 2), makeEvent(sequence: 1)], nextCursor: 2)]
    )
    let cursor = RecordingCursorStore()
    let recorder = EventRecorder()
    let coordinator = AccountEventSyncCoordinator(
        accountID: fixture.account.id,
        backend: source,
        realtime: nil,
        cursorStore: cursor,
        fallbackInterval: .seconds(1)
    )

    coordinator.start(
        onBootstrap: { _ in },
        onEvent: { event in
            await recorder.append(event.sequence)
            return false
        }
    )
    for _ in 0..<100 {
        if await recorder.sequences.count == 2 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    coordinator.stop()

    let handled = await recorder.sequences
    let saved = await cursor.values
    #expect(handled == [1, 2])
    #expect(saved == [0, 1, 2])
}

@MainActor
@Test func unknownEventAdvancesThenBootstrapsAndSilentSocketStillPolls() async throws {
    let initial = makeBootstrap(cursor: 0)
    let reconciled = makeBootstrap(cursor: 5)
    let source = StubEventSource(
        bootstraps: [initial, reconciled],
        pages: [AccountEventPage(events: [makeEvent(sequence: 1, type: "future.event")], nextCursor: 1)]
    )
    let cursor = RecordingCursorStore()
    let coordinator = AccountEventSyncCoordinator(
        accountID: initial.account.id,
        backend: source,
        realtime: SilentSignalService(),
        cursorStore: cursor,
        fallbackInterval: .milliseconds(10)
    )

    coordinator.start(
        onBootstrap: { _ in },
        onEvent: { event in event.type == "future.event" }
    )
    for _ in 0..<100 {
        if await source.bootstrapCallCount >= 2, await source.eventCallCount >= 3 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    coordinator.stop()

    let bootstrapCalls = await source.bootstrapCallCount
    let eventCalls = await source.eventCallCount
    let saved = await cursor.values
    #expect(bootstrapCalls == 2)
    #expect(eventCalls >= 3)
    #expect(saved.prefix(3) == [0, 1, 5])
}

@MainActor
@Test func failedBootstrapStaysUnavailableAndRetriesBeforeReportingHealthy() async throws {
    let fixture = makeBootstrap(cursor: 7)
    let source = FlakyBootstrapSource(bootstrap: fixture)
    let cursor = RecordingCursorStore()
    let statuses = SyncStatusRecorder()
    let coordinator = AccountEventSyncCoordinator(
        accountID: fixture.account.id,
        backend: source,
        realtime: nil,
        cursorStore: cursor,
        fallbackInterval: .seconds(1),
        recoveryInterval: .milliseconds(10)
    )

    coordinator.start(
        onBootstrap: { _ in },
        onEvent: { _ in false },
        onStatusChange: { statuses.values.append($0) }
    )
    for _ in 0..<100 {
        if await source.bootstrapCallCount >= 2 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    coordinator.stop()

    #expect(await source.bootstrapCallCount >= 2)
    #expect(statuses.values.contains(.unavailable))
    #expect(statuses.values.first == .bootstrapping)
    #expect(statuses.values.firstIndex(of: .unavailable) != nil)
    #expect(statuses.values.lastIndex(of: .bootstrapping)! > statuses.values.firstIndex(of: .unavailable)!)
}

private func makeBootstrap(cursor: Int64) -> SyncBootstrap {
    let accountID = AccountID(rawValue: "account-a")
    let pet = PublicPetSnapshot(
        petID: PetProfileID(rawValue: "pet-a"),
        displayName: "Mino",
        appearanceSchemaVersion: 1,
        appearanceCatalogVersion: 1,
        appearanceVersion: 1,
        appearance: ["rigID": "mino-default"]
    )
    return SyncBootstrap(
        account: AccountSummary(
            id: accountID,
            displayName: "Alice",
            primaryAgentDeviceID: DeviceID(rawValue: "device-a"),
            createdAt: .distantPast,
            updatedAt: .distantPast
        ),
        currentDevice: Device(
            id: DeviceID(rawValue: "device-a"),
            accountID: accountID,
            displayName: "Mac",
            platform: "macos",
            appVersion: "test",
            createdAt: .distantPast,
            revokedAt: nil
        ),
        isPrimaryAgentDevice: true,
        pet: pet,
        ownPetCare: PetCareState(evaluatedAt: .distantPast),
        petFamiliarities: [],
        friendships: [],
        pendingVisits: [],
        activeVisits: [],
        unresolvedVisitActions: [],
        activeConversations: [],
        cursor: cursor,
        serverTime: .distantPast
    )
}

private func makeEvent(sequence: Int64, type: String = "friendship.accepted") -> AccountEvent {
    AccountEvent(
        sequence: sequence,
        id: "event-\(sequence)",
        schemaVersion: 1,
        recipientAccountID: AccountID(rawValue: "account-a"),
        friendshipID: nil,
        type: type,
        aggregateType: "friendship",
        aggregateID: "friendship-a",
        aggregateVersion: sequence,
        payload: .object([:]),
        timelineVisible: false,
        occurredAt: Date(timeIntervalSince1970: TimeInterval(sequence))
    )
}
