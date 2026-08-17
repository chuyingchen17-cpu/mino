import AppKit
import MinoAgent
import MinoDomain
import MinoInfrastructure
import MinoPersistence
import MinoPresentation
import MinoRuntime
import MinoSecurity

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services: ServiceContainer
    private var world: PetWorld?
    private var petWindows: [PetID: PetWindowController] = [:]
    private var sharedSpaceWindow: SharedSpaceWindowController?
    private let effectWindows = EffectWindowController()
    private let demoSequence = DemoSequenceController()
    private var statusItem: NSStatusItem?
    private var visitMenuItem: NSMenuItem?
    private var backendHealthTask: Task<Void, Never>?
    private var localStateBootstrapTask: Task<Void, Never>?
    private var visitTransitionTask: Task<Void, Never>?
    private var socialBootstrapTask: Task<Void, Never>?
    private var agentWakeTask: Task<Void, Never>?
    private var eventSyncCoordinators: [FriendshipID: EventSyncCoordinator] = [:]
    private var conversationCoordinator: ConversationCoordinator?
    private var socialVisitCoordinator: VisitCoordinator?
    private var agentCoordinator: AgentCoordinator?
    private var agentMemoryStore: (any AgentMemoryStore)?
    private var developmentProfile: DevBootstrapProfile?
    private var activeIncomingVisit: MVPVisit?
    private var activeOutgoingVisit: MVPVisit?
    private var pendingLetterDraft: String?

    init(services: ServiceContainer) {
        self.services = services
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let endpoint = services.configuration.backend.baseURL?.absoluteString ?? "none"
        MinoLog.lifecycle.info(
            "Mino launching with backend mode: \(self.services.configuration.backend.mode.rawValue, privacy: .public), profile: \(self.services.configuration.clientProfile.id, privacy: .public), endpoint: \(endpoint, privacy: .public), storage: \(self.services.storageMode.rawValue, privacy: .public)"
        )
        let fullVisibleFrame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let screenRegion = services.configuration.clientProfile.screenRegion
        let runtimeIdentity = self.runtimeIdentity
        let visibleFrame = Self.visibleFrame(fullVisibleFrame, constrainedTo: screenRegion)
        let baseline = visibleFrame.minY + 105
        let initialPets = [
            PetRuntimeState(
                id: .mine,
                displayName: runtimeIdentity.localPetName,
                position: CGPoint(x: visibleFrame.midX, y: baseline),
                facing: .right,
                activity: .idle,
                emotion: .content,
                avatar: runtimeIdentity.localAvatar
            )
        ]

        let world = PetWorld(pets: initialPets) { point in
            let fullFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? fullVisibleFrame
            return Self.visibleFrame(fullFrame, constrainedTo: screenRegion)
        }

        petWindows[.mine] = PetWindowController(
            id: .mine,
            displayName: runtimeIdentity.localPetName,
            onMoved: { [weak self, weak world] position in
                self?.demoSequence.stop()
                world?.movePet(.mine, to: position)
            },
            onClicked: { [weak self, weak world] in
                self?.demoSequence.stop()
                world?.triggerKiss()
            },
            onHoverChanged: { [weak world] isHovering in
                world?.setPetHovering(.mine, isHovering: isHovering)
            },
            onContextAction: { [weak self] action in
                self?.handlePetContextAction(action, for: .mine)
            }
        )
        // `.partner` is the legacy second render slot; it now always represents
        // whichever accepted friend's pet is currently visiting this desktop.
        petWindows[.partner] = PetWindowController(
            id: .partner,
            displayName: runtimeIdentity.fallbackFriendPetName,
            onMoved: { [weak self, weak world] position in
                self?.demoSequence.stop()
                world?.movePet(.partner, to: position)
            },
            onClicked: { [weak self, weak world] in
                self?.demoSequence.stop()
                world?.triggerKiss()
            },
            onHoverChanged: { [weak world] isHovering in
                world?.setPetHovering(.partner, isHovering: isHovering)
            },
            onContextAction: { [weak self] action in
                self?.handlePetContextAction(action, for: .partner)
            }
        )

        world.onStateChange = { [weak self] states in
            guard let self else { return }
            for id in PetID.allCases {
                if let state = states[id] {
                    self.petWindows[id]?.render(state)
                    self.petWindows[id]?.show()
                } else {
                    self.petWindows[id]?.hide()
                }
            }
            if self.isSocialMVPConfigured {
                if self.activeIncomingVisit?.status == .active {
                    self.visitMenuItem?.title = "请来访宠物回家"
                } else if self.activeOutgoingVisit?.status == .active {
                    self.visitMenuItem?.title = "喊\(runtimeIdentity.localPetName)回家"
                } else if self.activeIncomingVisit != nil || self.activeOutgoingVisit != nil {
                    self.visitMenuItem?.title = "串门提议正在处理中"
                } else {
                    self.visitMenuItem?.title = "选择好友串门"
                }
            } else {
                self.visitMenuItem?.title = states[.partner] == nil
                    ? "模拟\(runtimeIdentity.fallbackFriendPetName)来串门"
                    : "让\(runtimeIdentity.fallbackFriendPetName)回家"
            }
        }
        world.onInteractionCue = { [weak self] cue in
            switch cue {
            case .kissHeart(let position):
                self?.effectWindows.showKissHeart(at: position)
            case .flowerGift(let position):
                self?.effectWindows.showFlowerGift(at: position)
            }
        }

        self.world = world
        world.start()
        setupSharedSpaceWindow()
        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        bootstrapLocalState()
        checkRemoteBackendIfConfigured()
        startSocialMVPIfConfigured()
    }

    func applicationWillTerminate(_ notification: Notification) {
        localStateBootstrapTask?.cancel()
        backendHealthTask?.cancel()
        visitTransitionTask?.cancel()
        socialBootstrapTask?.cancel()
        agentWakeTask?.cancel()
        eventSyncCoordinators.values.forEach { $0.stop() }
        demoSequence.stop()
        world?.stop()
        NotificationCenter.default.removeObserver(self)
        MinoLog.lifecycle.info("Mino terminated")
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "♡"
        statusItem.button?.toolTip = "Mino 个人桌宠"

        let menu = NSMenu()
        if let debugIdentityLabel {
            let profileItem = NSMenuItem(
                title: "Debug 当前实例 · \(debugIdentityLabel)",
                action: nil,
                keyEquivalent: ""
            )
            profileItem.isEnabled = false
            menu.addItem(profileItem)
            menu.addItem(.separator())
            statusItem.button?.toolTip = "Mino · \(debugIdentityLabel)"
        }
        let identityItem = NSMenuItem(
            title: "我的宠物 · \(runtimeIdentity.localPetName)",
            action: nil,
            keyEquivalent: ""
        )
        identityItem.isEnabled = false
        menu.addItem(identityItem)

        let openItem = NSMenuItem(title: "打开好友与事件", action: #selector(openSharedSpace), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        if !isSocialMVPConfigured {
            let demoItem = NSMenuItem(
                title: "播放完整 Demo",
                action: #selector(playDemo),
                keyEquivalent: "d"
            )
            demoItem.target = self
            menu.addItem(demoItem)
        }

        let visitItem = NSMenuItem(
            title: isSocialMVPConfigured
                ? "选择好友串门"
                : "模拟\(runtimeIdentity.fallbackFriendPetName)来串门",
            action: #selector(togglePartnerVisit),
            keyEquivalent: "v"
        )
        visitItem.target = self
        menu.addItem(visitItem)
        visitMenuItem = visitItem
        menu.addItem(.separator())

        let kissItem = NSMenuItem(title: "亲亲", action: #selector(kissPets), keyEquivalent: "k")
        kissItem.target = self
        menu.addItem(kissItem)

        let flowerItem = NSMenuItem(title: "送花", action: #selector(giveFlower), keyEquivalent: "f")
        flowerItem.target = self
        menu.addItem(flowerItem)

        let walkItem = NSMenuItem(title: "一起散步", action: #selector(walkPets), keyEquivalent: "w")
        walkItem.target = self
        menu.addItem(walkItem)

        let avatarItem = NSMenuItem(
            title: "宠物形象",
            action: #selector(togglePartnerAppearance),
            keyEquivalent: "a"
        )
        avatarItem.target = self
        menu.addItem(avatarItem)

        let resetItem = NSMenuItem(title: "重置位置", action: #selector(resetDemo), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Mino", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func setupSharedSpaceWindow() {
        sharedSpaceWindow = SharedSpaceWindowController(
            debugIdentityLabel: debugIdentityLabel,
            identity: SharedSpaceIdentity(
                localPetName: runtimeIdentity.localPetName,
                fallbackFriendPetName: runtimeIdentity.fallbackFriendPetName
            ),
            onInteraction: { [weak self] action in
                self?.demoSequence.stop()
                switch action {
                case .kiss:
                    self?.world?.triggerKiss()
                    self?.recordInteractionEvent(.kiss)
                case .flower:
                    self?.world?.triggerFlowerGift()
                    self?.recordInteractionEvent(.flowerGift)
                case .walk:
                    self?.world?.walkAll()
                    self?.recordInteractionEvent(.walk)
                }
            },
            onFriendAction: { [weak self] action in
                self?.handleFriendDirectoryAction(action)
            },
            onSendChatMessage: { [weak self] message in
                guard let self else { return }
                if let visit = self.activeIncomingVisit, visit.status == .active {
                    self.sendVisitInteraction(.message, text: message, visitID: visit.id)
                } else if let agentCoordinator = self.agentCoordinator {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let joined: Bool
                            if let friendshipID = sharedSpaceWindow?.model.selectedFriendshipID {
                                joined = try await agentCoordinator
                                    .sendOwnerMessageToActiveConversation(
                                        message,
                                        friendshipID: friendshipID
                                    )
                            } else {
                                joined = false
                            }
                            if !joined {
                                await agentCoordinator.observe(
                                    AgentObservation(kind: .ownerMessage(text: message))
                                )
                            }
                        } catch {
                            sharedSpaceWindow?.model.visitErrorMessage =
                                "消息没有送达，请稍后重试"
                        }
                    }
                } else {
                    self.submitOwnerObservation(.ownerMessage(text: message))
                }
            },
            onOpenLetter: { [weak self] letterID in
                self?.openLetter(letterID)
            },
            onVisibilityChange: { [weak self] isVisible in
                guard let self else { return }
                for (id, controller) in self.petWindows {
                    controller.setCovered(by: isVisible ? self.sharedSpaceWindow?.window : nil)
                    if !isVisible, self.world?.pets[id] != nil {
                        controller.show()
                    }
                }
            }
        )
        sharedSpaceWindow?.show()
    }

    @objc
    private func openSharedSpace() {
        sharedSpaceWindow?.show()
    }

    private func handlePetContextAction(_ action: PetContextAction, for id: PetID) {
        demoSequence.stop()
        switch action {
        case .pet:
            break
        case .speak:
            guard let text = promptForText(
                title: "说句话",
                message: id == .partner
                    ? "这句话会作为真人消息送给来访宠物。"
                    : "告诉你的宠物，它会自己决定如何回应。",
                placeholder: "想说什么？"
            ) else { return }
            if id == .partner, let visit = activeIncomingVisit, visit.status == .active {
                sendVisitInteraction(.message, text: text, visitID: visit.id)
            } else {
                submitOwnerObservation(.ownerMessage(text: text))
            }
        case .feed:
            if id == .partner, let visit = activeIncomingVisit, visit.status == .active {
                sendVisitInteraction(.feed, visitID: visit.id)
            } else {
                submitOwnerObservation(.ownerInteraction(.feeding(foodName: nil)))
            }
        case .play:
            if id == .partner, let visit = activeIncomingVisit, visit.status == .active {
                sendVisitInteraction(.play, visitID: visit.id)
            } else {
                world?.walkAll()
                submitOwnerObservation(.ownerInteraction(.play))
            }
        case .requestVisit:
            guard id == .mine else { return }
            requestOwnPetVisit()
        case .viewMemory:
            guard id == .mine else { return }
            showAgentMemories()
        case .leaveLetter:
            guard
                id == .partner,
                let visit = activeIncomingVisit,
                visit.status == .active
            else { return }
            guard let body = promptForText(
                title: "托付一封信",
                message: "正文只会交给收件人，不会进入宠物 Agent 或模型上下文。",
                placeholder: "写下想让它带回去的话…",
                initialText: pendingLetterDraft
            ) else { return }
            leaveLetter(body, on: visit.id)
        case .kiss:
            world?.triggerKiss()
            recordInteractionEvent(.kiss)
        case .flower:
            world?.triggerFlowerGift()
            recordInteractionEvent(.flowerGift)
        case .walk:
            world?.walkAll()
            recordInteractionEvent(.walk)
        case .changeAppearance:
            guard id == .partner else { return }
            world?.togglePartnerAppearance()
        case .sendHome:
            guard id == .partner else { return }
            if isSocialMVPConfigured {
                guard activeIncomingVisit?.status == .active else {
                    sharedSpaceWindow?.model.visitErrorMessage = "来访状态还未同步，请稍后再试"
                    return
                }
                handleFriendDirectoryAction(.endVisit)
                return
            }
            world?.setVisiblePet(nil, for: .partner)
            sharedSpaceWindow?.model.visitState = .away
            recordTimelineEvent(PersonalTimelineEvent(kind: .visitReturned))
        case .resetPosition:
            world?.resetForDemo()
        }
    }

    private func submitOwnerObservation(_ kind: AgentObservationKind) {
        guard let agentCoordinator else {
            sharedSpaceWindow?.model.agentMessage = "宠物的大脑还在连接中"
            return
        }
        Task { await agentCoordinator.observe(AgentObservation(kind: kind)) }
    }

    private func sendVisitInteraction(
        _ kind: VisitInteractionKind,
        text: String? = nil,
        visitID: PetVisitID
    ) {
        guard let socialVisitCoordinator else { return }
        world?.setWaitingForRemoteAgent(.partner, isWaiting: true)
        sharedSpaceWindow?.model.agentMessage = "来访宠物在打盹，等自己的 Agent 回应"
        Task { @MainActor [weak self] in
            do {
                _ = try await socialVisitCoordinator.interact(
                    visitID: visitID,
                    kind: kind,
                    text: text
                )
                self?.sharedSpaceWindow?.model.agentMessage = switch kind {
                case .feed: "投喂已经送到来访宠物那里"
                case .play: "来访宠物开心地玩了起来"
                case .message: "真人消息已经交给来访宠物"
                }
            } catch {
                self?.world?.setWaitingForRemoteAgent(.partner, isWaiting: false)
                self?.sharedSpaceWindow?.model.visitErrorMessage = "互动没有送达，请稍后重试"
            }
        }
    }

    private func requestOwnPetVisit() {
        guard
            let profile = developmentProfile,
            let friend = selectedFriendProfile,
            let socialVisitCoordinator,
            activeOutgoingVisit == nil,
            activeIncomingVisit == nil
        else {
            sharedSpaceWindow?.model.visitErrorMessage = "当前还不能发起新的串门"
            return
        }
        sharedSpaceWindow?.model.activeVisitFriendshipID = friend.friendshipID
        sharedSpaceWindow?.model.visitState = .sendingInvitation
        Task { @MainActor [weak self] in
            do {
                let visit = try await socialVisitCoordinator.invite(
                    friendshipID: friend.friendshipID,
                    visitorPetID: profile.petID,
                    hostAccountID: friend.accountID,
                    reason: "主人想让宠物过去串门"
                )
                self?.activeOutgoingVisit = visit
                self?.sharedSpaceWindow?.model.visitState = .invitationSent
            } catch {
                self?.sharedSpaceWindow?.model.visitState = .away
                self?.sharedSpaceWindow?.model.activeVisitFriendshipID = nil
                self?.sharedSpaceWindow?.model.visitErrorMessage = "串门请求没有送达"
            }
        }
    }

    private func leaveLetter(_ body: String, on visitID: PetVisitID) {
        guard let socialVisitCoordinator else { return }
        Task { @MainActor [weak self] in
            do {
                _ = try await socialVisitCoordinator.leaveLetter(
                    visitID: visitID,
                    body: body
                )
                self?.pendingLetterDraft = nil
                self?.sharedSpaceWindow?.model.agentMessage = "信已经封好，会随宠物回家"
            } catch {
                self?.pendingLetterDraft = body
                self?.sharedSpaceWindow?.model.visitErrorMessage = "信暂时保留在输入框，请稍后重试"
            }
        }
    }

    private func openLetter(_ letterID: LetterID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let friendshipID = sharedSpaceWindow?.model.timelineEvents.first(where: {
                    $0.letterID == letterID
                })?.friendshipID else {
                    throw BackendClientError.invalidRequest
                }
                let letter = try await services.backend.fetchLetter(
                    friendshipID: friendshipID,
                    letterID
                )
                let alert = NSAlert()
                alert.messageText = "宠物带回来的信"
                alert.informativeText = letter.body
                alert.addButton(withTitle: "收好")
                alert.runModal()
            } catch {
                sharedSpaceWindow?.model.visitErrorMessage = "暂时打不开这封信，请稍后重试"
            }
        }
    }

    private func showAgentMemories() {
        guard
            let memoryStore = agentMemoryStore,
            let petID = developmentProfile?.petID
        else {
            sharedSpaceWindow?.model.agentMessage = "记忆库还没有准备好"
            return
        }
        Task { @MainActor in
            do {
                let memories = try await memoryStore.allMemories(for: petID)
                let alert = NSAlert()
                alert.messageText = "宠物的长期记忆"
                alert.informativeText = memories.isEmpty
                    ? "目前还没有长期记忆。"
                    : memories.prefix(12).map { "• \($0.summary)" }.joined(separator: "\n")
                alert.addButton(withTitle: "完成")
                if !memories.isEmpty {
                    alert.addButton(withTitle: "删除全部记忆")
                }
                if alert.runModal() == .alertSecondButtonReturn {
                    try await memoryStore.removeAll(for: petID)
                    sharedSpaceWindow?.model.agentMessage = "长期记忆已删除"
                }
            } catch {
                sharedSpaceWindow?.model.visitErrorMessage = "暂时无法读取记忆"
            }
        }
    }

    private func promptForText(
        title: String,
        message: String,
        placeholder: String,
        initialText: String? = nil
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 360, height: 28))
        field.placeholderString = placeholder
        field.stringValue = initialText ?? ""
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let normalized = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    @objc
    private func playDemo() {
        guard let world else { return }
        hostVisitingFriendPetIfNeeded(in: world)
        demoSequence.play(in: world)
    }

    @objc
    private func togglePartnerVisit() {
        if isSocialMVPConfigured {
            if activeIncomingVisit?.status == .active || activeOutgoingVisit?.status == .active {
                requestRemoteVisitReturn()
            } else if activeIncomingVisit != nil || activeOutgoingVisit != nil {
                sharedSpaceWindow?.model.agentMessage = "串门提议正在等待宠物作决定"
            } else {
                requestOwnPetVisit()
            }
            return
        }
        guard let world else { return }
        demoSequence.stop()
        if world.pets[.partner] == nil {
            hostVisitingFriendPetIfNeeded(in: world)
            sharedSpaceWindow?.model.visitState = .visiting
            recordTimelineEvent(PersonalTimelineEvent(kind: .visitArrived))
        } else {
            world.setVisiblePet(nil, for: .partner)
            sharedSpaceWindow?.model.visitState = .away
            recordTimelineEvent(PersonalTimelineEvent(kind: .visitReturned))
        }
    }

    private func handleFriendDirectoryAction(_ action: FriendDirectoryAction) {
        switch action {
        case .refresh:
            guard services.configuration.backend.mode == .remote else {
                sharedSpaceWindow?.model.friendErrorMessage = "离线模式不能刷新好友列表"
                return
            }
            sharedSpaceWindow?.model.friendOperationInProgress = true
            sharedSpaceWindow?.model.friendErrorMessage = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { sharedSpaceWindow?.model.friendOperationInProgress = false }
                do {
                    try await refreshFriendDirectory()
                } catch {
                    sharedSpaceWindow?.model.friendErrorMessage = "好友列表刷新失败，请稍后重试"
                }
            }

        case .addFriend(let accountID):
            submitFriendRequest(to: accountID)

        case .respondToRequest(let requestID, let decision):
            respondToFriendRequest(requestID, decision: decision)

        case .selectFriend(let friendshipID):
            sharedSpaceWindow?.model.selectedFriendshipID = friendshipID

        case .inviteFriend(let friendshipID):
            guard sharedSpaceWindow?.model.visitState == .away else { return }
            guard let friend = friendProfile(id: friendshipID) else {
                sharedSpaceWindow?.model.friendErrorMessage = "这位好友已不在列表中，请刷新后重试"
                return
            }
            sharedSpaceWindow?.model.visitErrorMessage = nil
            sharedSpaceWindow?.model.selectedFriendshipID = friendshipID
            sharedSpaceWindow?.model.activeVisitFriendshipID = friendshipID
            if services.configuration.backend.mode == .remote {
                sendRemoteVisitInvitation(to: friend)
            } else {
                simulatePartnerVisitInvitation()
            }

        case .endVisit:
            guard let visitState = sharedSpaceWindow?.model.visitState,
                  visitState == .visiting || visitState == .ownPetVisiting else { return }
            sharedSpaceWindow?.model.visitErrorMessage = nil
            if services.configuration.backend.mode == .remote {
                requestRemoteVisitReturn()
            } else {
                finishSimulatedPartnerVisit()
            }
        }
    }

    private func friendProfile(id: FriendshipID) -> FriendProfile? {
        sharedSpaceWindow?.model.friends.first { $0.friendshipID == id }
    }

    private var selectedFriendProfile: FriendProfile? {
        guard let id = sharedSpaceWindow?.model.selectedFriendshipID else {
            return sharedSpaceWindow?.model.friends.first
        }
        return friendProfile(id: id)
    }

    private func friendProfile(for visit: MVPVisit) -> FriendProfile? {
        if visit.visitorOwnerAccountID == developmentProfile?.accountID {
            return sharedSpaceWindow?.model.friends.first {
                $0.accountID == visit.hostAccountID
            }
        }
        return sharedSpaceWindow?.model.friends.first {
            $0.accountID == visit.visitorOwnerAccountID || $0.petID == visit.visitorPetID
        }
    }

    private func friendPetID(
        for visit: MVPVisit,
        localPetID: PetProfileID
    ) -> PetProfileID? {
        if visit.visitorPetID != localPetID {
            return visit.visitorPetID
        }
        return friendProfile(for: visit)?.petID
    }

    private func submitFriendRequest(to accountID: AccountID) {
        guard services.configuration.backend.mode == .remote else {
            sharedSpaceWindow?.model.friendErrorMessage = "离线模式不能发送好友申请"
            return
        }
        sharedSpaceWindow?.model.friendOperationInProgress = true
        sharedSpaceWindow?.model.friendErrorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { sharedSpaceWindow?.model.friendOperationInProgress = false }
            do {
                _ = try await services.backend.createFriendRequest(
                    CreateFriendRequestCommand(addresseeAccountID: accountID)
                )
                try await refreshFriendDirectory()
            } catch {
                sharedSpaceWindow?.model.friendErrorMessage =
                    "好友申请没有送达，请检查账号 ID 后重试"
            }
        }
    }

    private func respondToFriendRequest(
        _ requestID: FriendRequestID,
        decision: FriendRequestDecision
    ) {
        sharedSpaceWindow?.model.friendOperationInProgress = true
        sharedSpaceWindow?.model.friendErrorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { sharedSpaceWindow?.model.friendOperationInProgress = false }
            do {
                _ = try await services.backend.respondToFriendRequest(
                    requestID: requestID,
                    command: RespondFriendRequestCommand(response: decision)
                )
                try await refreshFriendDirectory()
            } catch {
                sharedSpaceWindow?.model.friendErrorMessage = "好友申请状态更新失败，请稍后重试"
            }
        }
    }

    private func refreshFriendDirectory() async throws {
        async let friendsRequest = services.backend.fetchFriends()
        async let requestsRequest = services.backend.fetchFriendRequests(status: .pending)
        let (friends, requests) = try await (friendsRequest, requestsRequest)
        let sortedFriends = friends.sorted {
            if $0.accountName == $1.accountName {
                return $0.petName < $1.petName
            }
            return $0.accountName < $1.accountName
        }
        sharedSpaceWindow?.model.friends = sortedFriends
        sharedSpaceWindow?.model.friendRequests = requests.sorted {
            $0.createdAt > $1.createdAt
        }
        let agentFriends = sortedFriends.map {
            AgentFriend(
                friendshipID: $0.friendshipID,
                accountID: $0.accountID,
                petID: $0.petID
            )
        }
        if let agentCoordinator {
            await agentCoordinator.updateFriends(agentFriends)
            reconcileEventSyncCoordinators()
        }
        if let selected = sharedSpaceWindow?.model.selectedFriendshipID,
           friends.contains(where: { $0.friendshipID == selected }) {
            return
        }
        sharedSpaceWindow?.model.selectedFriendshipID = sortedFriends.first?.friendshipID
    }

    private func simulatePartnerVisitInvitation() {
        visitTransitionTask?.cancel()
        sharedSpaceWindow?.model.visitState = .sendingInvitation
        visitTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let invitationID = PetVisitInvitationID(rawValue: UUID().uuidString)
            await persistTimelineEvent(
                PersonalTimelineEvent(
                    kind: .visitInvited,
                    invitationID: invitationID
                )
            )
            sharedSpaceWindow?.model.visitState = .invitationSent
            guard await pauseVisitTask(for: .milliseconds(1_100)) else { return }
            guard let world else { return }
            hostVisitingFriendPetIfNeeded(in: world)
            sharedSpaceWindow?.model.visitState = .visiting
            await persistTimelineEvent(
                PersonalTimelineEvent(
                    kind: .visitArrived,
                    invitationID: invitationID
                )
            )
        }
    }

    private func finishSimulatedPartnerVisit() {
        visitTransitionTask?.cancel()
        sharedSpaceWindow?.model.visitState = .returning
        world?.setVisiblePet(nil, for: .partner)
        visitTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await pauseVisitTask(for: .milliseconds(650)) else { return }
            await persistTimelineEvent(PersonalTimelineEvent(kind: .visitReturned))
            sharedSpaceWindow?.model.visitState = .away
        }
    }

    private func sendRemoteVisitInvitation(to friend: FriendProfile) {
        visitTransitionTask?.cancel()
        sharedSpaceWindow?.model.visitState = .sendingInvitation
        guard let profile = developmentProfile,
              let visits = socialVisitCoordinator else {
            sharedSpaceWindow?.model.visitState = .away
            sharedSpaceWindow?.model.visitErrorMessage = "好友服务还没有准备好"
            return
        }
        visitTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await visits.invite(
                    friendshipID: friend.friendshipID,
                    visitorPetID: friend.petID,
                    hostAccountID: profile.accountID,
                    reason: "好友邀请宠物过来玩"
                )
                sharedSpaceWindow?.model.visitState = .invitationSent
            } catch {
                sharedSpaceWindow?.model.visitState = .away
                sharedSpaceWindow?.model.activeVisitFriendshipID = nil
                sharedSpaceWindow?.model.visitErrorMessage = visitErrorMessage(for: error)
            }
        }
    }

    private func requestRemoteVisitReturn() {
        visitTransitionTask?.cancel()
        if let visits = socialVisitCoordinator,
           let activeVisit = activeIncomingVisit ?? activeOutgoingVisit {
            let wasIncoming = activeIncomingVisit?.id == activeVisit.id
            sharedSpaceWindow?.model.visitState = .returning
            if wasIncoming {
                world?.setVisiblePet(nil, for: .partner)
            } else {
                world?.setVisiblePet(nil, for: .mine)
            }
            visitTransitionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = try await visits.end(visitID: activeVisit.id)
                } catch {
                    if wasIncoming, let world {
                        hostVisitingFriendPetIfNeeded(in: world)
                        sharedSpaceWindow?.model.visitState = .visiting
                    } else {
                        ensureLocalPetVisible()
                        sharedSpaceWindow?.model.visitState = .ownPetVisiting
                    }
                    sharedSpaceWindow?.model.visitErrorMessage = visitErrorMessage(for: error)
                }
            }
            return
        }
        sharedSpaceWindow?.model.visitErrorMessage = "没有可结束的串门"
    }

    private func recordTimelineEvent(_ event: PersonalTimelineEvent) {
        Task { @MainActor [weak self] in
            await self?.persistTimelineEvent(event)
        }
    }

    private func recordInteractionEvent(_ kind: PetInteractionKind) {
        guard world?.pets[.partner] != nil else { return }
        if let visit = activeIncomingVisit, visit.status == .active {
            let description = switch kind {
            case .kiss: "两只宠物亲亲了一下"
            case .flowerGift: "主人和宠物送给来访宠物一朵花"
            case .walk: "两只宠物一起散步"
            }
            sendVisitInteraction(.play, text: description, visitID: visit.id)
            return
        }
        if isSocialMVPConfigured {
            guard let profile = developmentProfile,
                  let friend = selectedFriendProfile else {
                sharedSpaceWindow?.model.visitErrorMessage = "请先在好友页选择一位好友"
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = try await services.backend.sendInteraction(
                        InteractionCommand(
                            kind: kind,
                            senderPetID: profile.petID,
                            recipientPetID: friend.petID
                        )
                    )
                } catch {
                    sharedSpaceWindow?.model.visitErrorMessage = "互动没有送达，请稍后重试"
                }
            }
            return
        }
        recordTimelineEvent(
            PersonalTimelineEvent(
                kind: .interaction,
                interactionKind: kind
            )
        )
    }

    private func persistTimelineEvent(_ event: PersonalTimelineEvent) async {
        do {
            try await services.personalTimelineStore.append(event)
            sharedSpaceWindow?.model.timelineEvents = try await services.personalTimelineStore.load()
        } catch {
            MinoLog.lifecycle.error(
                "Timeline persistence failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func pauseVisitTask(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func visitErrorMessage(for error: Error) -> String {
        "网络暂时没有送达，请稍后重试"
    }

    @objc
    private func walkPets() {
        demoSequence.stop()
        world?.walkAll()
        recordInteractionEvent(.walk)
    }

    @objc
    private func togglePartnerAppearance() {
        demoSequence.stop()
        world?.togglePartnerAppearance()
    }

    @objc
    private func kissPets() {
        demoSequence.stop()
        world?.triggerKiss()
        recordInteractionEvent(.kiss)
    }

    @objc
    private func giveFlower() {
        demoSequence.stop()
        world?.triggerFlowerGift()
        recordInteractionEvent(.flowerGift)
    }

    @objc
    private func resetDemo() {
        demoSequence.stop()
        world?.resetForDemo()
    }

    private func hostVisitingFriendPetIfNeeded(in world: PetWorld) {
        guard world.pets[.partner] == nil else { return }
        let identity = runtimeIdentity
        let anchor = world.pets[.mine]?.position
            ?? CGPoint(x: NSScreen.main?.visibleFrame.midX ?? 720, y: 105)
        world.setVisiblePet(
            PetRuntimeState(
                id: .partner,
                displayName: selectedFriendProfile?.petName
                    ?? identity.fallbackFriendPetName,
                position: CGPoint(x: anchor.x + 190, y: anchor.y),
                facing: .left,
                activity: .idle,
                emotion: .content,
                avatar: identity.fallbackFriendAvatar
            ),
            for: .partner
        )
    }

    private func ensureLocalPetVisible() {
        guard let world, world.pets[.mine] == nil else { return }
        let fullFrame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = Self.visibleFrame(
            fullFrame,
            constrainedTo: services.configuration.clientProfile.screenRegion
        )
        let identity = runtimeIdentity
        world.setVisiblePet(
            PetRuntimeState(
                id: .mine,
                displayName: identity.localPetName,
                position: CGPoint(x: frame.midX, y: frame.minY + 105),
                facing: .right,
                activity: .idle,
                emotion: .content,
                avatar: identity.localAvatar
            ),
            for: .mine
        )
    }

    private var runtimeIdentity: RuntimePetIdentity {
        switch services.configuration.clientProfile.id {
        case "bob":
            RuntimePetIdentity(
                localPetName: "团子",
                fallbackFriendPetName: "奶糖",
                localAvatar: .partner,
                fallbackFriendAvatar: .mine
            )
        default:
            RuntimePetIdentity(
                localPetName: "奶糖",
                fallbackFriendPetName: "团子",
                localAvatar: .mine,
                fallbackFriendAvatar: .partner
            )
        }
    }

    private var debugIdentityLabel: String? {
#if DEBUG
        let profile = services.configuration.clientProfile
        return profile == .standard ? nil : profile.debugDisplayName
#else
        nil
#endif
    }

    private var isSocialMVPConfigured: Bool {
        services.configuration.backend.mode == .remote
            && services.configuration.clientProfile != .standard
    }

    private static func visibleFrame(
        _ fullFrame: CGRect,
        constrainedTo screenRegion: ScreenRegion
    ) -> CGRect {
        switch screenRegion {
        case .full:
            fullFrame
        case .leftHalf:
            CGRect(
                x: fullFrame.minX,
                y: fullFrame.minY,
                width: fullFrame.width / 2,
                height: fullFrame.height
            )
        case .rightHalf:
            CGRect(
                x: fullFrame.midX,
                y: fullFrame.minY,
                width: fullFrame.width / 2,
                height: fullFrame.height
            )
        }
    }

    @objc
    private func screenConfigurationChanged() {
        demoSequence.stop()
        world?.restorePetsToVisibleScreens()
    }

    private func startSocialMVPIfConfigured() {
        guard services.configuration.backend.mode == .remote else { return }
        let runtimeProfile = services.configuration.clientProfile
        guard runtimeProfile != .standard else {
            // Normal account sign-in is outside this internal MVP. Never fall
            // back to the removed fixed-relationship presence model.
            return
        }

        socialBootstrapTask?.cancel()
        socialBootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let profile = try await services.backend.bootstrapDevelopmentProfile(
                    runtimeProfile.id
                )
                developmentProfile = profile
                try await services.sessionStore.save(
                    SessionCredential(
                        accountID: profile.accountID,
                        accessToken: profile.token,
                        refreshToken: nil,
                        accessTokenExpiresAt: .distantFuture,
                        issuedAt: Date()
                    )
                )
                sharedSpaceWindow?.model.localAccountID = profile.accountID
                try await refreshFriendDirectory()
                let agentFriends = (sharedSpaceWindow?.model.friends ?? []).map {
                    AgentFriend(
                        friendshipID: $0.friendshipID,
                        accountID: $0.accountID,
                        petID: $0.petID
                    )
                }

                let memoryStore: any AgentMemoryStore
                if let fileURL = services.agentMemoryFileURL {
                    let key = try await services.agentMemoryKeyStore.loadOrCreateKey()
                    memoryStore = EncryptedFileAgentMemoryStore(
                        fileURL: fileURL,
                        key: key,
                        capacity: 200
                    )
                } else {
                    memoryStore = InMemoryAgentMemoryStore(capacity: 200)
                }
                agentMemoryStore = memoryStore

                let modelClient = HTTPManagedModelClient(
                    endpoint: try modelDecisionEndpoint(),
                    tokenProvider: AgentSessionTokenProvider(store: services.sessionStore)
                )
                let identity = AgentIdentity(
                    petID: profile.petID,
                    ownerAccountID: profile.accountID,
                    displayName: profile.petName,
                    friends: agentFriends
                )
                let localAgent = LocalPetAgent(
                    identity: identity,
                    modelClient: modelClient,
                    memoryStore: memoryStore
                )
                let conversations = ConversationCoordinator(backend: services.backend)
                let visits = VisitCoordinator(backend: services.backend)
                let agent = AgentCoordinator(
                    identity: identity,
                    agent: localAgent,
                    conversations: conversations,
                    visits: visits,
                    onOwnerSpeech: { [weak self] text in
                        self?.sharedSpaceWindow?.model.agentMessage = text
                    },
                    onReaction: { [weak self] reaction in
                        self?.applyAgentReaction(reaction)
                    },
                    onFailure: { error in
                        MinoLog.backend.error(
                            "Agent action delivery failed: \(String(describing: error), privacy: .public)"
                        )
                    }
                )
                conversationCoordinator = conversations
                socialVisitCoordinator = visits
                agentCoordinator = agent

                try await restoreSocialConversationState(agent: agent)
                try await restoreSocialVisitState(
                    profile: profile,
                    visits: visits,
                    agent: agent
                )

                reconcileEventSyncCoordinators()
                startAgentWakeLoop(agent)
            } catch {
                sharedSpaceWindow?.model.visitErrorMessage = "MVP 初始化失败，请确认本地服务已启动"
                MinoLog.backend.error(
                    "Social MVP bootstrap failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func modelDecisionEndpoint() throws -> URL {
        guard let baseURL = services.configuration.backend.baseURL else {
            throw BackendClientError.invalidRequest
        }
        return baseURL
            .appendingPathComponent(services.configuration.backend.apiVersion, isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("decision", isDirectory: false)
    }

    private func startAgentWakeLoop(_ agent: AgentCoordinator) {
        agentWakeTask?.cancel()
        let profileID = services.configuration.clientProfile.id
        let initialDelay: Duration = profileID == "bob" ? .seconds(48) : .seconds(15)
        let repeatDelay: Duration = .seconds(90)
        agentWakeTask = Task {
            do {
                try await Task.sleep(for: initialDelay)
            } catch {
                return
            }
            while !Task.isCancelled {
                await agent.observe(AgentObservation(kind: .periodicWake))
                do {
                    try await Task.sleep(for: repeatDelay)
                } catch {
                    return
                }
            }
        }
    }

    /// Rehydrates logical presence before event catch-up starts. The server is
    /// authoritative, so a pet that was already visiting stays hidden at home
    /// even when the last `visit_arrived` event is behind the persisted cursor.
    private func restoreSocialVisitState(
        profile: DevBootstrapProfile,
        visits: VisitCoordinator,
        agent: AgentCoordinator
    ) async throws {
        let activeVisits = try await fetchVisitsAcrossFriends(status: .active)
        for visit in activeVisits {
            await visits.apply(visit)
            await agent.applyVisit(visit)
        }

        if let active = activeVisits.first(where: {
            $0.visitorPetID == profile.petID || $0.hostAccountID == profile.accountID
        }) {
            sharedSpaceWindow?.model.activeVisitFriendshipID =
                friendProfile(for: active)?.friendshipID
            if active.visitorPetID == profile.petID {
                activeOutgoingVisit = active
                activeIncomingVisit = nil
                world?.setVisiblePet(nil, for: .mine)
                sharedSpaceWindow?.model.visitState = .ownPetVisiting
                await agent.observe(
                    AgentObservation(
                        id: visitStartedObservationID(active.id),
                        occurredAt: active.startedAt ?? active.createdAt,
                        kind: .visitStarted(
                            visitID: active.id,
                            hostAccountID: active.hostAccountID
                        )
                    )
                )
            } else {
                activeIncomingVisit = active
                activeOutgoingVisit = nil
                if let world { hostVisitingFriendPetIfNeeded(in: world) }
                world?.setWaitingForRemoteAgent(.partner, isWaiting: true)
                sharedSpaceWindow?.model.visitState = .visiting
            }
            return
        }

        let pendingVisits = try await fetchVisitsAcrossFriends(status: .pending)
        guard let pending = pendingVisits.first(where: {
            $0.visitorPetID == profile.petID || $0.hostAccountID == profile.accountID
        }) else {
            return
        }
        await visits.apply(pending)
        sharedSpaceWindow?.model.activeVisitFriendshipID =
            friendProfile(for: pending)?.friendshipID
        if pending.visitorPetID == profile.petID {
            activeOutgoingVisit = pending
        } else {
            activeIncomingVisit = pending
        }

        let responderAccountID = pending.requestedByAccountID == pending.visitorOwnerAccountID
            ? pending.hostAccountID
            : pending.visitorOwnerAccountID
        guard responderAccountID == profile.accountID else {
            sharedSpaceWindow?.model.visitState = .invitationSent
            return
        }

        sharedSpaceWindow?.model.visitState = .consideringInvitation
        guard let senderPetID = friendPetID(for: pending, localPetID: profile.petID) else {
            return
        }
        await agent.observe(
            AgentObservation(
                id: UUID(uuidString: pending.id.rawValue) ?? UUID(),
                occurredAt: pending.createdAt,
                kind: .visitInvitation(
                    invitationID: PetVisitInvitationID(rawValue: pending.id.rawValue),
                    senderPetID: senderPetID,
                    reason: pending.reason
                )
            )
        )
    }

    private func fetchVisitsAcrossFriends(
        status: MVPVisitStatus
    ) async throws -> [MVPVisit] {
        let backend = services.backend
        let friendshipIDs = Array(acceptedFriendshipIDs)
        return try await withThrowingTaskGroup(of: [MVPVisit].self) { group in
            for friendshipID in friendshipIDs {
                group.addTask {
                    try await backend.fetchVisitInvitations(
                        friendshipID: friendshipID,
                        status: status
                    )
                }
            }
            var visits: [MVPVisit] = []
            for try await result in group {
                visits.append(contentsOf: result)
            }
            return visits
        }
    }

    /// Restores each friend's active conversation and bounded transcript before
    /// missed events are replayed.
    private func restoreSocialConversationState(
        agent: AgentCoordinator
    ) async throws {
        for friendshipID in acceptedFriendshipIDs {
            let active = try await services.backend.fetchConversations(
                friendshipID: friendshipID,
                status: .active
            )
            .sorted { $0.createdAt > $1.createdAt }
            .first
            guard let active else { continue }
            let messages = try await services.backend.fetchConversationMessages(
                friendshipID: friendshipID,
                conversationID: active.id
            )
            await agent.restoreConversation(active, messages: messages)
        }
    }

    private func reconcileEventSyncCoordinators() {
        let acceptedIDs = acceptedFriendshipIDs
        for friendshipID in Array(eventSyncCoordinators.keys)
        where !acceptedIDs.contains(friendshipID) {
            eventSyncCoordinators.removeValue(forKey: friendshipID)?.stop()
        }
        for friendshipID in acceptedIDs where eventSyncCoordinators[friendshipID] == nil {
            let coordinator = EventSyncCoordinator(
                backend: services.backend,
                realtime: services.realtimeEvents,
                cursorStore: services.friendshipEventCursorStore,
                friendshipID: friendshipID
            )
            eventSyncCoordinators[friendshipID] = coordinator
            coordinator.start(
                onEvent: { [weak self] event in
                    guard let self else { return }
                    try await self.handleFriendshipEvent(event)
                },
                onStatusChange: { [weak self] status in
                    self?.sharedSpaceWindow?.model.eventSyncStatusText = switch status {
                    case .stopped: "事件同步已暂停"
                    case .catchingUp: "正在同步刚刚发生的事"
                    case .realtime: "事件通道已连接"
                    case .polling: "连接不稳，正在补收事件"
                    }
                }
            )
        }
    }

    private var acceptedFriendshipIDs: Set<FriendshipID> {
        Set(sharedSpaceWindow?.model.friends.map(\.friendshipID) ?? [])
    }

    private func handleFriendshipEvent(_ event: FriendshipEvent) async throws {
        guard acceptedFriendshipIDs.contains(event.friendshipID) else { return }
        if let timelineEvent = event.timelineEvent() {
            await persistTimelineEvent(timelineEvent)
        }
        guard let profile = developmentProfile else { return }

        switch event.type {
        case "conversation_message":
            guard
                payloadString(event, "recipientPetID") == profile.petID.rawValue,
                let text = payloadString(event, "text"),
                let conversationID = payloadString(event, "conversationID")
            else { return }
            let observation: AgentObservation
            if event.actorType == .human,
               let actorID = event.actorID {
                observation = AgentObservation(
                    id: observationID(for: event),
                    occurredAt: event.occurredAt,
                    kind: .remoteHumanMessage(
                        senderAccountID: AccountID(rawValue: actorID),
                        text: text
                    )
                )
            } else if event.actorType == .pet,
                      let actorID = event.actorID,
                      actorID != profile.petID.rawValue {
                observation = AgentObservation(
                    id: observationID(for: event),
                    occurredAt: event.occurredAt,
                    kind: .petMessage(
                        senderPetID: PetProfileID(rawValue: actorID),
                        text: text
                    )
                )
            } else {
                return
            }
            if let agentCoordinator {
                let typedConversationID = ConversationID(rawValue: conversationID)
                let turnIndex = event.payload["turnIndex"]?.numberValue.map(Int.init)
                await agentCoordinator.recordConversationMessage(
                    conversationID: typedConversationID,
                    actorType: event.actorType,
                    actorID: event.actorID ?? "unknown",
                    recipientPetID: profile.petID,
                    turnIndex: turnIndex,
                    text: text
                )
                if event.actorType == .pet,
                   (turnIndex ?? -1) >= 5 {
                    try await agentCoordinator.finishConversation(
                        friendshipID: event.friendshipID,
                        conversationID: typedConversationID,
                        occurredAt: event.occurredAt
                    )
                    return
                }
                await agentCoordinator.setActiveConversationID(
                    typedConversationID,
                    for: event.friendshipID
                )
                try await agentCoordinator.observeEvent(observation)
            }

        case "conversation_summary":
            if let summary = payloadString(event, "summary") {
                sharedSpaceWindow?.model.agentMessage = summary
            }
            if let agentCoordinator {
                await agentCoordinator.setActiveConversationID(
                    nil,
                    for: event.friendshipID
                )
            }

        case "visit_invited":
            guard let visit = makeVisit(from: event, status: .pending, profile: profile) else {
                return
            }
            await socialVisitCoordinator?.apply(visit)
            sharedSpaceWindow?.model.activeVisitFriendshipID =
                friendProfile(for: visit)?.friendshipID
            if visit.visitorPetID == profile.petID {
                activeOutgoingVisit = visit
            } else if visit.hostAccountID == profile.accountID {
                activeIncomingVisit = visit
            }

            let responderAccountID = payloadString(event, "responderAccountID")
                .map(AccountID.init(rawValue:))
                ?? (visit.requestedByAccountID == visit.visitorOwnerAccountID
                    ? visit.hostAccountID
                    : visit.visitorOwnerAccountID)
            if responderAccountID == profile.accountID,
               let agentCoordinator,
               let senderPetID = friendPetID(for: visit, localPetID: profile.petID) {
                sharedSpaceWindow?.model.visitState = .consideringInvitation
                sharedSpaceWindow?.model.agentMessage =
                    "\(profile.petName) 正在考虑这个串门提议"
                let observation = AgentObservation(
                    id: UUID(uuidString: visit.id.rawValue) ?? observationID(for: event),
                    occurredAt: event.occurredAt,
                    kind: .visitInvitation(
                        invitationID: PetVisitInvitationID(rawValue: visit.id.rawValue),
                        senderPetID: senderPetID,
                        reason: visit.reason
                    )
                )
                await agentCoordinator.applyVisit(visit)
                try await agentCoordinator.observeEvent(observation)
            } else {
                sharedSpaceWindow?.model.visitState = .invitationSent
            }

        case "visit_arrived":
            guard let visit = makeVisit(from: event, status: .active, profile: profile) else {
                return
            }
            await socialVisitCoordinator?.apply(visit)
            sharedSpaceWindow?.model.activeVisitFriendshipID =
                friendProfile(for: visit)?.friendshipID
            if visit.visitorPetID == profile.petID {
                activeOutgoingVisit = visit
                world?.setVisiblePet(nil, for: .mine)
                sharedSpaceWindow?.model.visitState = .ownPetVisiting
                if let agentCoordinator {
                    let observation = AgentObservation(
                        id: visitStartedObservationID(visit.id),
                        occurredAt: event.occurredAt,
                        kind: .visitStarted(
                            visitID: visit.id,
                            hostAccountID: visit.hostAccountID
                        )
                    )
                    await agentCoordinator.applyVisit(visit)
                    try await agentCoordinator.observeEvent(observation)
                }
            } else if visit.hostAccountID == profile.accountID {
                activeIncomingVisit = visit
                if let world { hostVisitingFriendPetIfNeeded(in: world) }
                world?.setWaitingForRemoteAgent(.partner, isWaiting: true)
                sharedSpaceWindow?.model.visitState = .visiting
            }

        case "visit_declined":
            guard let visit = makeVisit(from: event, status: .cancelled, profile: profile) else {
                return
            }
            await socialVisitCoordinator?.apply(visit)
            if visit.visitorPetID == profile.petID {
                activeOutgoingVisit = nil
                ensureLocalPetVisible()
            }
            if activeIncomingVisit?.id == visit.id {
                activeIncomingVisit = nil
            }
            sharedSpaceWindow?.model.visitState = .away
            sharedSpaceWindow?.model.activeVisitFriendshipID = nil
            if let agentCoordinator {
                await agentCoordinator.applyVisit(visit)
            }

        case "visit_interaction":
            guard
                payloadString(event, "visitorPetID") == profile.petID.rawValue,
                let rawKind = payloadString(event, "kind"),
                let kind = VisitInteractionKind(rawValue: rawKind),
                let visitID = payloadString(event, "visitID")
            else { return }
            let stimulus: PetInteractionStimulus
            switch kind {
            case .feed: stimulus = .feeding(foodName: nil)
            case .play: stimulus = .play
            case .message:
                guard let text = payloadString(event, "text") else { return }
                stimulus = .message(text: text)
            }
            let actorID = event.actorID.map(AccountID.init(rawValue:))
                ?? selectedFriendProfile?.accountID
                ?? profile.accountID
            let observation = AgentObservation(
                id: observationID(for: event),
                occurredAt: event.occurredAt,
                kind: .visitInteraction(
                    visitID: PetVisitID(rawValue: visitID),
                    actorAccountID: actorID,
                    stimulus: stimulus
                )
            )
            if let agentCoordinator {
                try await agentCoordinator.observeEvent(observation)
            }

        case "visit_reaction":
            guard
                payloadString(event, "visitorPetID") == activeIncomingVisit?.visitorPetID.rawValue,
                let rawReaction = payloadString(event, "reaction"),
                let reaction = PetReaction(rawValue: rawReaction)
            else { return }
            let remainsSleepy = reaction == .sleepy || reaction == .resting
            world?.setWaitingForRemoteAgent(.partner, isWaiting: remainsSleepy)
            switch reaction {
            case .happy, .excited, .grateful, .playful:
                world?.setPetEmotion(.partner, emotion: .happy)
            case .shy:
                world?.setPetEmotion(.partner, emotion: .shy)
            case .sleepy, .resting:
                world?.setPetEmotion(.partner, emotion: .content)
            }
            sharedSpaceWindow?.model.agentMessage = payloadString(event, "text")
                ?? (remainsSleepy ? "来访宠物安心地睡着了" : "来访宠物回应了你的互动")

        case "visit_returned":
            guard let visit = makeVisit(from: event, status: .ended, profile: profile) else {
                return
            }
            await socialVisitCoordinator?.apply(visit)
            if visit.visitorPetID == profile.petID {
                activeOutgoingVisit = nil
                ensureLocalPetVisible()
                if let agentCoordinator {
                    let observation = AgentObservation(
                        id: observationID(for: event),
                        occurredAt: event.occurredAt,
                        kind: .visitEnded(visitID: visit.id)
                    )
                    await agentCoordinator.applyVisit(visit)
                    try await agentCoordinator.observeEvent(observation)
                }
            } else {
                activeIncomingVisit = nil
                world?.setVisiblePet(nil, for: .partner)
            }
            sharedSpaceWindow?.model.visitState = .away
            sharedSpaceWindow?.model.activeVisitFriendshipID = nil

        case "letter_received":
            guard
                payloadString(event, "recipientAccountID") == profile.accountID.rawValue,
                payloadString(event, "letterID") != nil
            else {
                return
            }
            sharedSpaceWindow?.model.agentMessage =
                "\(profile.petName) 带回了一封只给你看的信，可在事件线中打开"
            if let actorID = payloadString(event, "authorAccountID"),
               let agentCoordinator {
                let observation = AgentObservation(
                    id: observationID(for: event),
                    occurredAt: event.occurredAt,
                    kind: .sealedHumanLetterAvailable(
                        senderAccountID: AccountID(rawValue: actorID)
                    )
                )
                try await agentCoordinator.observeEvent(observation)
            }

        default:
            break
        }
    }

    private func makeVisit(
        from event: FriendshipEvent,
        status: MVPVisitStatus,
        profile: DevBootstrapProfile
    ) -> MVPVisit? {
        guard
            let rawVisitID = payloadString(event, "visitID"),
            let rawVisitorPetID = payloadString(event, "visitorPetID")
        else { return nil }
        let visitID = PetVisitID(rawValue: rawVisitID)
        let previous = activeIncomingVisit?.id == visitID
            ? activeIncomingVisit
            : (activeOutgoingVisit?.id == visitID ? activeOutgoingVisit : nil)
        let visitorPetID = PetProfileID(rawValue: rawVisitorPetID)
        let ownerAccountID = payloadString(event, "visitorOwnerAccountID")
            .map(AccountID.init(rawValue:))
            ?? (visitorPetID == profile.petID
                ? profile.accountID
                : sharedSpaceWindow?.model.friends.first(where: { $0.petID == visitorPetID })?.accountID)
        guard let ownerAccountID else { return nil }
        let hostAccountID = payloadString(event, "hostAccountID")
            .map(AccountID.init(rawValue:))
            ?? previous?.hostAccountID
            ?? (ownerAccountID == profile.accountID ? selectedFriendProfile?.accountID : profile.accountID)
        guard let hostAccountID else { return nil }
        let requestedBy = payloadString(event, "requestedByAccountID")
            .map(AccountID.init(rawValue:))
            ?? previous?.requestedByAccountID
            ?? event.actorID.map(AccountID.init(rawValue:))
            ?? hostAccountID
        return MVPVisit(
            id: visitID,
            friendshipID: event.friendshipID,
            visitorPetID: visitorPetID,
            visitorOwnerAccountID: ownerAccountID,
            hostAccountID: hostAccountID,
            requestedByAccountID: requestedBy,
            status: status,
            reason: payloadString(event, "reason") ?? previous?.reason,
            createdAt: previous?.createdAt ?? event.occurredAt,
            startedAt: status == .active ? (previous?.startedAt ?? event.occurredAt) : previous?.startedAt,
            endedAt: status == .ended || status == .cancelled ? event.occurredAt : nil
        )
    }

    private func payloadString(_ event: FriendshipEvent, _ key: String) -> String? {
        event.payload[key]?.stringValue
    }

    private func observationID(for event: FriendshipEvent) -> UUID {
        UUID(uuidString: event.id) ?? UUID()
    }

    private func visitStartedObservationID(_ visitID: PetVisitID) -> UUID {
        guard var value = UUID(uuidString: visitID.rawValue)?.uuidString else {
            return UUID()
        }
        let last = value.removeLast()
        value.append(last == "0" ? "1" : "0")
        return UUID(uuidString: value) ?? UUID()
    }

    private func applyAgentReaction(_ reaction: PetReaction) {
        switch reaction {
        case .excited, .playful:
            world?.walkAll()
        case .happy, .grateful:
            sharedSpaceWindow?.model.agentMessage = "宠物看起来很开心"
        case .shy:
            sharedSpaceWindow?.model.agentMessage = "宠物有点害羞地靠近了一点"
        case .sleepy, .resting:
            sharedSpaceWindow?.model.agentMessage = "宠物安心地打起了盹"
        }
    }

    private func checkRemoteBackendIfConfigured() {
        guard services.configuration.backend.mode == .remote else { return }
        let backend = services.backend
        backendHealthTask = Task {
            do {
                let health = try await backend.checkHealth()
                MinoLog.backend.info(
                    "Backend health: \(health.status.rawValue, privacy: .public), API \(health.apiVersion, privacy: .public)"
                )
            } catch {
                MinoLog.backend.error(
                    "Backend health check failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func bootstrapLocalState() {
        let sessionStore = services.sessionStore
        let interactionOutbox = services.interactionOutbox
        let personalTimelineStore = services.personalTimelineStore
        localStateBootstrapTask = Task {
            do {
                async let credential = sessionStore.load()
                async let pendingCount = interactionOutbox.pendingCount()
                async let timeline = personalTimelineStore.load()
                let state = try await (credential, pendingCount, timeline)
                self.sharedSpaceWindow?.model.timelineEvents = state.2
                MinoLog.lifecycle.info(
                    "Local state ready; signed in: \(state.0 != nil), pending interactions: \(state.1)"
                )
            } catch {
                MinoLog.lifecycle.error(
                    "Local state bootstrap failed without deleting data: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}

private struct RuntimePetIdentity {
    let localPetName: String
    let fallbackFriendPetName: String
    let localAvatar: AvatarRecipe
    let fallbackFriendAvatar: AvatarRecipe
}

private struct AgentSessionTokenProvider: ManagedModelTokenProvider {
    let store: any SessionCredentialStore

    func accessToken() async throws -> String? {
        guard let credential = try await store.load(), !credential.needsRefresh() else {
            return nil
        }
        return credential.accessToken
    }
}
