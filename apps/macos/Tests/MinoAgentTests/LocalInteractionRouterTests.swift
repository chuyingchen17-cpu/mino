import Foundation
import MinoAgent
import MinoDomain
import Testing

@Test
func localInteractionsProduceImmediateReactionsWithoutSingleModelCalls() async {
    let router = LocalInteractionRouter()

    let touch = await router.routePetTouch()
    #expect(touch.immediateSpeech != nil)
    #expect(touch.emotion == .happy)
    #expect(!touch.startsWalk)
    #expect(touch.activity == .petting)
    #expect(touch.modelObservation == nil)

    let feeding = await router.routeOwnerInteraction(.feeding(foodName: nil))
    #expect(feeding.immediateSpeech != nil)
    #expect(feeding.emotion == .happy)
    #expect(!feeding.startsWalk)
    #expect(feeding.activity == .eating)
    #expect(feeding.modelObservation == nil)

    let play = await LocalInteractionRouter().routeOwnerInteraction(.play)
    #expect(play.immediateSpeech != nil)
    #expect(play.emotion == .playful)
    #expect(!play.startsWalk)
    #expect(play.activity == .playing)
    #expect(play.modelObservation == nil)
}

@Test
func ownerMessagesDebounceToTheLatestText() async {
    let start = Date(timeIntervalSince1970: 10_000)
    let router = LocalInteractionRouter(
        configuration: LocalInteractionRouter.Configuration(
            ownerMessageDebounceInterval: 0.6
        ),
        startedAt: start
    )

    _ = await router.routeOwnerMessage("第一句", occurredAt: start)
    _ = await router.routeOwnerMessage(
        "第二句",
        occurredAt: start.addingTimeInterval(0.2)
    )

    let early = await router.flushDebouncedOwnerMessageIfDue(
        at: start.addingTimeInterval(0.7)
    )
    #expect(early == nil)

    let flushed = await router.flushDebouncedOwnerMessageIfDue(
        at: start.addingTimeInterval(0.9)
    )
    guard case .ownerMessage(let text) = flushed?.kind else {
        Issue.record("Expected a debounced owner message observation")
        return
    }
    #expect(text == "第二句")
}

@Test
func ownerMessageFlushRespectsMinimumModelInterval() async {
    let start = Date(timeIntervalSince1970: 20_000)
    let router = LocalInteractionRouter(
        configuration: LocalInteractionRouter.Configuration(
            ownerMessageDebounceInterval: 0.1,
            ownerMessageMinimumModelInterval: 3
        ),
        startedAt: start
    )

    _ = await router.routeOwnerMessage("one", occurredAt: start)
    let first = await router.flushDebouncedOwnerMessageIfDue(
        at: start.addingTimeInterval(0.2)
    )
    #expect(first != nil)

    _ = await router.routeOwnerMessage("two", occurredAt: start.addingTimeInterval(0.5))
    let throttled = await router.flushDebouncedOwnerMessageIfDue(
        at: start.addingTimeInterval(0.8)
    )
    #expect(throttled == nil)

    let second = await router.flushDebouncedOwnerMessageIfDue(
        at: start.addingTimeInterval(3.3)
    )
    guard case .ownerMessage(let text) = second?.kind else {
        Issue.record("Expected the delayed owner message after the minimum interval")
        return
    }
    #expect(text == "two")
}

@Test
func localInteractionSummariesAreCooledDownWithinFiveMinutes() async {
    let start = Date(timeIntervalSince1970: 30_000)
    let router = LocalInteractionRouter(startedAt: start)

    let first = await router.routeOwnerInteraction(.feeding(foodName: nil), occurredAt: start)
    let second = await router.routeOwnerInteraction(
        .play,
        occurredAt: start.addingTimeInterval(10)
    )
    let third = await router.routeOwnerInteraction(
        .feeding(foodName: nil),
        occurredAt: start.addingTimeInterval(20)
    )
    let fourth = await router.routeOwnerInteraction(
        .play,
        occurredAt: start.addingTimeInterval(30)
    )

    let modelObservations = [first, second, third, fourth].compactMap(\.modelObservation)
    #expect(modelObservations.count == 1)
    guard case .ownerInteraction(.message(let summary)) = modelObservations.first?.kind else {
        Issue.record("Expected an aggregated local interaction summary")
        return
    }
    #expect(summary.contains("投喂 1 次"))
    #expect(summary.contains("陪玩 1 次"))
}

@Test
func periodicWakeUsesQuietWindowFriendsBusyStateAndTwentyMinuteBudget() async {
    let start = Date(timeIntervalSince1970: 40_000)
    let router = LocalInteractionRouter(startedAt: start)

    _ = await router.routeOwnerInteraction(
        .feeding(foodName: nil),
        occurredAt: start.addingTimeInterval(590)
    )

    let beforeQuietWindow = await router.periodicWakeObservation(
        hasFriends: true,
        agentIsProcessing: false,
        at: start.addingTimeInterval(599)
    )
    #expect(beforeQuietWindow == nil)

    let noFriends = await router.periodicWakeObservation(
        hasFriends: false,
        agentIsProcessing: false,
        at: start.addingTimeInterval(600)
    )
    #expect(noFriends == nil)

    let busy = await router.periodicWakeObservation(
        hasFriends: true,
        agentIsProcessing: true,
        at: start.addingTimeInterval(600)
    )
    #expect(busy == nil)

    let firstWake = await router.periodicWakeObservation(
        hasFriends: true,
        agentIsProcessing: false,
        at: start.addingTimeInterval(600)
    )
    #expect(firstWake != nil)

    _ = await router.routeOwnerInteraction(
        .play,
        occurredAt: start.addingTimeInterval(1_489)
    )
    let withinBudget = await router.periodicWakeObservation(
        hasFriends: true,
        agentIsProcessing: false,
        at: start.addingTimeInterval(1_500)
    )
    #expect(withinBudget == nil)

    _ = await router.routeOwnerInteraction(
        .feeding(foodName: nil),
        occurredAt: start.addingTimeInterval(1_790)
    )
    let afterBudget = await router.periodicWakeObservation(
        hasFriends: true,
        agentIsProcessing: false,
        at: start.addingTimeInterval(1_801)
    )
    #expect(afterBudget != nil)
}
