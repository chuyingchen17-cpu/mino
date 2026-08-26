import Foundation
import MinoDomain

enum AccountEventSyncStatus: Equatable, Sendable {
    case stopped
    case bootstrapping
    case catchingUp
    case realtime
    case polling
    case unavailable
}

@MainActor
final class AccountEventSyncCoordinator {
    typealias BootstrapHandler = @MainActor @Sendable (SyncBootstrap) async throws -> Void
    /// Return true when the event schema/type is unknown and an authoritative
    /// bootstrap reconciliation is required after advancing its cursor.
    typealias EventHandler = @MainActor @Sendable (AccountEvent) async throws -> Bool
    typealias StatusHandler = @MainActor @Sendable (AccountEventSyncStatus) -> Void

    private let accountID: AccountID
    private let backend: any AccountEventSource
    private let realtime: (any AccountEventSignalService)?
    private let cursorStore: any AccountEventCursorStore
    private let fallbackInterval: Duration
    private let recoveryInterval: Duration
    private var task: Task<Void, Never>?
    private var bootstrapHandler: BootstrapHandler?
    private var eventHandler: EventHandler?
    private var statusHandler: StatusHandler?

    init(
        accountID: AccountID,
        backend: any AccountEventSource,
        realtime: (any AccountEventSignalService)?,
        cursorStore: any AccountEventCursorStore,
        fallbackInterval: Duration = .seconds(60),
        recoveryInterval: Duration = .seconds(2)
    ) {
        self.accountID = accountID
        self.backend = backend
        self.realtime = realtime
        self.cursorStore = cursorStore
        self.fallbackInterval = fallbackInterval
        self.recoveryInterval = recoveryInterval
    }

    func start(
        onBootstrap: @escaping BootstrapHandler,
        onEvent: @escaping EventHandler,
        onStatusChange: @escaping StatusHandler = { _ in }
    ) {
        bootstrapHandler = onBootstrap
        eventHandler = onEvent
        statusHandler = onStatusChange
        launch()
    }

    /// Wake/network observers may request an immediate authoritative pass.
    /// Restarting the serialized loop is safe because event and command paths
    /// are independently idempotent.
    func requestCatchUp() {
        guard bootstrapHandler != nil, eventHandler != nil, statusHandler != nil else { return }
        launch()
    }

    private func launch() {
        guard let onBootstrap = bootstrapHandler,
              let onEvent = eventHandler,
              let onStatusChange = statusHandler
        else { return }
        task?.cancel()
        task = Task { [weak self] in
            await self?.run(
                onBootstrap: onBootstrap,
                onEvent: onEvent,
                onStatusChange: onStatusChange
            )
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        bootstrapHandler = nil
        eventHandler = nil
        statusHandler = nil
    }

    private func run(
        onBootstrap: @escaping BootstrapHandler,
        onEvent: @escaping EventHandler,
        onStatusChange: @escaping StatusHandler
    ) async {
        var cursor = (try? await cursorStore.load(for: accountID)) ?? 0

        // Bootstrap is the authoritative account snapshot. Do not silently
        // fall through to an apparently healthy event loop when it is
        // unavailable; keep retrying while cached local state remains usable.
        while !Task.isCancelled {
            do {
                onStatusChange(.bootstrapping)
                let bootstrap = try await backend.fetchSyncBootstrap()
                try await onBootstrap(bootstrap)
                cursor = bootstrap.cursor
                try await cursorStore.save(cursor, for: accountID)
                break
            } catch {
                onStatusChange(.unavailable)
                guard await pause(for: recoveryInterval) else {
                    onStatusChange(.stopped)
                    return
                }
            }
        }

        while !Task.isCancelled {
            do {
                onStatusChange(.catchingUp)
                cursor = try await drain(
                    after: cursor,
                    onBootstrap: onBootstrap,
                    onEvent: onEvent
                )
            } catch {
                onStatusChange(.unavailable)
                guard await pause(for: recoveryInterval) else { break }
                continue
            }

            guard let realtime else {
                onStatusChange(.polling)
                guard await pause() else { break }
                continue
            }

            do {
                let signals = try await realtime.signals()
                onStatusChange(.realtime)
                // Catch events committed between the REST drain and WS ready.
                cursor = try await drain(
                    after: cursor,
                    onBootstrap: onBootstrap,
                    onEvent: onEvent
                )
                let triggers = fallbackTriggers(from: signals)
                for await signal in triggers {
                    guard !Task.isCancelled else { break }
                    if signal == .ready || signal == .eventsAvailable {
                        cursor = try await drain(
                            after: cursor,
                            onBootstrap: onBootstrap,
                            onEvent: onEvent
                        )
                    }
                }
            } catch {
                // The next REST drain closes every best-effort WebSocket gap.
            }
            guard !Task.isCancelled else { break }
            onStatusChange(.polling)
            guard await pause(for: .seconds(2)) else { break }
        }
        onStatusChange(.stopped)
    }

    /// Durable Object messages are only hints. A timer feeds the same drain
    /// path so a live-but-silent socket can never suppress REST recovery.
    private func fallbackTriggers(
        from signals: AsyncThrowingStream<AccountRealtimeSignal, Error>
    ) -> AsyncStream<AccountRealtimeSignal> {
        AsyncStream { continuation in
            let signalTask = Task {
                do {
                    for try await signal in signals {
                        guard !Task.isCancelled else { break }
                        continuation.yield(signal)
                    }
                } catch {
                    // Stream completion reconnects through the outer loop.
                }
                continuation.finish()
            }
            let timerTask = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: fallbackInterval)
                        continuation.yield(.eventsAvailable)
                    } catch {
                        break
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                signalTask.cancel()
                timerTask.cancel()
            }
        }
    }

    private func drain(
        after initialCursor: Int64,
        onBootstrap: @escaping BootstrapHandler,
        onEvent: @escaping EventHandler
    ) async throws -> Int64 {
        var cursor = initialCursor
        let pageSize = 100
        while !Task.isCancelled {
            let page = try await backend.fetchAccountEvents(
                after: cursor,
                limit: pageSize,
                timelineVisible: nil
            )
            let events = page.events.sorted {
                $0.sequence == $1.sequence ? $0.id < $1.id : $0.sequence < $1.sequence
            }
            for event in events where event.sequence > cursor {
                let needsBootstrap = try await onEvent(event)
                // Cursor advancement is deliberately after successful handling.
                try await cursorStore.save(event.sequence, for: accountID)
                cursor = event.sequence
                if needsBootstrap {
                    let bootstrap = try await backend.fetchSyncBootstrap()
                    try await onBootstrap(bootstrap)
                    cursor = max(cursor, bootstrap.cursor)
                    try await cursorStore.save(cursor, for: accountID)
                }
            }
            guard events.count == pageSize else { break }
        }
        return cursor
    }

    private func pause(for duration: Duration? = nil) async -> Bool {
        do {
            try await Task.sleep(for: duration ?? fallbackInterval)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
