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
    private var visitInvitationWindow: VisitInvitationWindowController?
    private let effectWindows = EffectWindowController()
    private var statusItem: NSStatusItem?
    private var visitMenuItem: NSMenuItem?
    private var identityMenuItem: NSMenuItem?
    private var ownPetOperationsItem: NSMenuItem?
    private var visitingPetOperationsItem: NSMenuItem?
    private var backendHealthTask: Task<Void, Never>?
    private var localStateBootstrapTask: Task<Void, Never>?
    private var visitTransitionTask: Task<Void, Never>?
    private var socialBootstrapTask: Task<Void, Never>?
    private var githubSignInTask: Task<Void, Never>?
    private var socialOutboxRetryTask: Task<Void, Never>?
    private let careSession = PetCareSession()
    private var accountEventSyncCoordinator: AccountEventSyncCoordinator?
    private var visitProjectionReducer: VisitProjectionReducer?
    private var conversationCoordinator: ConversationCoordinator?
    private var socialVisitCoordinator: VisitCoordinator?
    private var agentCoordinator: AgentCoordinator?
    private var agentMemoryStore: (any AgentMemoryStore)?
    private var isPrimaryAgentDevice = false
    private var developmentProfile: DevBootstrapProfile?
    private var activeIncomingVisit: Visit?
    private var activeOutgoingVisit: Visit?
    private var pendingVisits: [PetVisitID: Visit] = [:]
    private var optimisticallyReturningVisitIDs: Set<PetVisitID> = []
    private var departingOwnPetVisitID: PetVisitID?
    private var pendingLetterDraft: String?
    private var currentProfile: CurrentProfile
    private let interactionResponseProvider = DeterministicInteractionResponseProvider()
    private var familiarities: [FriendshipID: PetFamiliarity] = [:]
    private var announcedIncomingVisitID: PetVisitID?

    init(services: ServiceContainer) {
        self.services = services
        currentProfile = LocalProfilePreferences.load(
            for: services.configuration.clientProfile
        ) ?? Self.defaultProfile(for: services.configuration.clientProfile)
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
                avatar: runtimeIdentity.localAvatar,
                characterID: runtimeDefaultCharacter
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
            onMoved: { [weak world] position in
                world?.movePet(.mine, to: position)
            },
            onClicked: { [weak self] in
                self?.handlePetTouch(for: .mine)
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
            onMoved: { [weak world] position in
                world?.movePet(.partner, to: position)
            },
            onClicked: { [weak self] in
                self?.handlePetTouch(for: .partner)
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
            if self.activeIncomingVisit?.status == .active {
                self.visitMenuItem?.title = "请来访宠物回家"
            } else if self.activeOutgoingVisit?.status == .active {
                self.visitMenuItem?.title = "喊\(runtimeIdentity.localPetName)回家"
            } else if !self.pendingVisits.isEmpty {
                self.visitMenuItem?.title = "串门提议正在处理中"
            } else {
                self.visitMenuItem?.title = "选择好友串门"
            }
            self.refreshPetOperationsMenus()
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
        careSession.updateOwner(
            OwnerContext(presence: .present, activity: .idle, updatedAt: Date())
        )
        setupSharedSpaceWindow()
        setupVisitInvitationWindow()
        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
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
        githubSignInTask?.cancel()
        socialOutboxRetryTask?.cancel()
        accountEventSyncCoordinator?.stop()
        visitInvitationWindow?.dismissAll()
        world?.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
        identityMenuItem = identityItem

        let openItem = NSMenuItem(title: "打开好友与事件", action: #selector(openSharedSpace), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let ownPetOperationsItem = makePetOperationsItem(for: .mine)
        menu.addItem(ownPetOperationsItem)
        self.ownPetOperationsItem = ownPetOperationsItem
        let visitingPetOperationsItem = makePetOperationsItem(for: .partner)
        visitingPetOperationsItem.isEnabled = false
        menu.addItem(visitingPetOperationsItem)
        self.visitingPetOperationsItem = visitingPetOperationsItem
        menu.addItem(.separator())

        if isSocialMVPConfigured {
            let visitItem = NSMenuItem(
                title: "选择好友串门",
                action: #selector(togglePartnerVisit),
                keyEquivalent: "v"
            )
            visitItem.target = self
            menu.addItem(visitItem)
            visitMenuItem = visitItem
            menu.addItem(.separator())
        }

        let resetItem = NSMenuItem(
            title: "重置位置",
            action: #selector(resetPetPositions),
            keyEquivalent: "r"
        )
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Mino", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func makePetOperationsItem(for petID: PetID) -> NSMenuItem {
        let root = NSMenuItem(title: petOperationsTitle(for: petID), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: root.title)
        let actions: [(String, PetContextAction)] = if petID == .mine {
            [
                ("摸摸", .pet), ("投喂", .feed), ("陪玩", .play), ("散步", .walk),
                ("休息", .rest), ("查看状态", .viewMemory), ("请求串门", .requestVisit),
                ("重置位置", .resetPosition)
            ]
        } else {
            [
                ("摸摸", .pet), ("投喂", .feed), ("陪玩", .play), ("散步", .walk),
                ("贴贴", .kiss), ("送花", .flower), ("托付文字信", .leaveLetter),
                ("让它回家", .sendHome)
            ]
        }
        for (title, action) in actions {
            let item = NSMenuItem(
                title: title,
                action: #selector(performStatusPetAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = action.rawValue
            item.representedObject = petID.rawValue
            submenu.addItem(item)
        }
        root.submenu = submenu
        return root
    }

    private func petOperationsTitle(for petID: PetID) -> String {
        if petID == .mine {
            return "操作 \(currentProfile.petName)"
        }
        return "操作 \(selectedFriendProfile?.petName ?? runtimeIdentity.fallbackFriendPetName)"
    }

    private func refreshPetOperationsMenus() {
        ownPetOperationsItem?.title = petOperationsTitle(for: .mine)
        visitingPetOperationsItem?.title = petOperationsTitle(for: .partner)
        ownPetOperationsItem?.isEnabled = world?.pets[.mine] != nil
        visitingPetOperationsItem?.isEnabled = world?.pets[.partner] != nil
    }

    @objc
    private func performStatusPetAction(_ sender: NSMenuItem) {
        guard let action = PetContextAction(rawValue: sender.tag),
              let rawPetID = sender.representedObject as? String,
              let petID = PetID(rawValue: rawPetID) else { return }
        handlePetContextAction(action, for: petID)
    }

    private func setupSharedSpaceWindow() {
        sharedSpaceWindow = SharedSpaceWindowController(
            debugIdentityLabel: debugIdentityLabel,
            identity: SharedSpaceIdentity(
                localPetName: runtimeIdentity.localPetName,
                fallbackFriendPetName: runtimeIdentity.fallbackFriendPetName
            ),
            onFriendAction: { [weak self] action in
                self?.handleFriendDirectoryAction(action)
            },
            onProfileAction: { [weak self] action in
                self?.handleProfileAction(action)
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
        sharedSpaceWindow?.model.currentProfile = currentProfile
        sharedSpaceWindow?.model.localAccountID = currentProfile.accountID
        sharedSpaceWindow?.model.ownPetCare = careSession.care(for: .mine)
        if services.configuration.clientProfile != .standard {
            sharedSpaceWindow?.model.ownPetCharacterID = runtimeDefaultCharacter
        }
        if services.configuration.backend.mode == .offline {
            sharedSpaceWindow?.model.authenticationState = .offline
            sharedSpaceWindow?.model.cloudSyncState = .localOnly
        } else if services.configuration.clientProfile == .standard {
            sharedSpaceWindow?.model.authenticationState = .signedOut
            sharedSpaceWindow?.model.cloudSyncState = .localOnly
        } else {
            sharedSpaceWindow?.model.authenticationState = .signedIn
            sharedSpaceWindow?.model.cloudSyncState = .connecting
        }
        sharedSpaceWindow?.show()
    }

    private func setupVisitInvitationWindow() {
        visitInvitationWindow = VisitInvitationWindowController { [weak self] invitation, response in
            self?.respondToPendingVisit(invitationID: invitation.id, response: response)
        }
    }

    @objc
    private func openSharedSpace() {
        sharedSpaceWindow?.show()
    }

    private func handlePetContextAction(_ action: PetContextAction, for id: PetID) {
        switch action {
        case .pet:
            performCareInteraction(.pet, for: id)
        case .feed:
            performCareInteraction(.feed, for: id)
        case .play:
            performCareInteraction(.play, for: id)
        case .requestVisit:
            guard id == .mine else { return }
            requestOwnPetVisit()
        case .viewMemory:
            guard id == .mine else { return }
            sharedSpaceWindow?.show()
        case .rest:
            guard id == .mine else { return }
            performCareInteraction(.rest, for: id)
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
            guard id == .partner else { return }
            performCareInteraction(.cuddle, for: id)
        case .flower:
            guard id == .partner else { return }
            performCareInteraction(.flower, for: id)
        case .walk:
            performCareInteraction(.walk, for: id)
        case .sendHome:
            guard id == .partner else { return }
            guard activeIncomingVisit?.status == .active else {
                sharedSpaceWindow?.model.visitErrorMessage = "来访状态还未同步，请稍后再试"
                return
            }
            handleFriendDirectoryAction(.endVisit)
        case .resetPosition:
            world?.resetPetPositions()
        }
    }

    private func handlePetTouch(for id: PetID) {
        performCareInteraction(.pet, for: id)
    }

    private func performCareInteraction(_ kind: PetCareInteractionKind, for id: PetID) {
        guard id == .mine || activeIncomingVisit?.status == .active else {
            sharedSpaceWindow?.model.visitErrorMessage = "这只 Mino 已经回家了"
            return
        }
        if kind == .rest, id != .mine { return }

        let occurredAt = Date()
        let interactionID = UUID()
        let relationship: PetInteractionActorRelationship = id == .mine ? .owner : .friend
        let friendshipID = id == .partner ? activeIncomingVisit?.friendshipID : nil
        let companionPresent = world?.pets[.mine] != nil && world?.pets[.partner] != nil
        let applied = careSession.applyLocal(
            kind,
            for: id,
            relationship: relationship,
            familiarityTier: friendshipID.flatMap { familiarities[$0]?.tier },
            companionPresent: companionPresent,
            partnerPublicCare: id == .partner ? selectedFriendProfile?.publicCare : nil,
            at: occurredAt,
            interactionID: interactionID
        )
        publishOwnCare(from: id)
        publishSituationToAgent(for: id)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let plan = await interactionResponseProvider.response(for: applied.context)
            applyReactionPlan(plan, to: id)
        }

        guard services.configuration.backend.mode == .remote,
              let coordinator = socialVisitCoordinator else { return }
        let targetPetID = id == .mine
            ? currentProfile.petID
            : (activeIncomingVisit?.visitorPetID ?? selectedFriendProfile?.petID)
        guard let targetPetID else { return }
        let visitID = id == .partner ? activeIncomingVisit?.id : nil
        sharedSpaceWindow?.model.cloudSyncState = .pending
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await coordinator.interactWithPet(
                    petID: targetPetID,
                    kind: kind,
                    visitID: visitID,
                    occurredAt: occurredAt,
                    idempotencyKey: interactionID
                )
                reconcileCareReceipt(receipt, applying: applied)
            } catch {
                if shouldRetrySocialMutation(error) {
                    // The persistent social outbox owns retryable delivery. The
                    // immediate animation is never blocked or rolled back.
                    sharedSpaceWindow?.model.cloudSyncState = .pending
                    sharedSpaceWindow?.model.agentMessage = "互动已完成，稍后同步"
                } else if careSession.rollback(applied) {
                    // A definitive server rejection must not leave optimistic
                    // care values pretending they were accepted.
                    publishOwnCare(from: id)
                    if sharedSpaceWindow?.model.cloudSyncState != .unavailable {
                        sharedSpaceWindow?.model.cloudSyncState = .synced
                    }
                    sharedSpaceWindow?.model.agentMessage = "互动反馈已保留，这次状态没有保存"
                }
            }
        }
    }

    private func publishOwnCare(from slot: PetID) {
        guard slot == .mine else { return }
        sharedSpaceWindow?.model.ownPetCare = careSession.care(for: .mine)
    }

    private func publishSituationToAgent(for slot: PetID) {
        guard slot == .mine else { return }
        let pet = world?.pets[.mine]
        let situation = careSession.situation(
            for: .mine,
            activity: pet?.activity ?? .idle,
            emotion: pet?.emotion ?? .content,
            companionPresent: world?.pets[.partner] != nil
        )
        Task { await agentCoordinator?.updateVisibleSituation(situation) }
    }

    private func applyReactionPlan(_ plan: PetReactionPlan, to id: PetID) {
        if plan.activity == .walking {
            world?.walkAll()
        } else {
            world?.performLocalActivity(
                id,
                activity: plan.activity,
                emotion: plan.emotion,
                duration: plan.duration,
                motionClip: plan.motionClip
            )
        }
        if let paired = plan.effect.pairedInteraction {
            world?.performPairedInteraction(paired.choreography)
        }
        petWindows[id]?.showSpeech(plan.speech, duration: plan.duration)
        sharedSpaceWindow?.model.agentMessage = plan.speech
    }

    private func reconcileCareReceipt(
        _ receipt: PetInteractionReceipt,
        applying applied: PetCareSession.AppliedInteraction
    ) {
        if careSession.reconcile(receipt, applying: applied) {
            publishOwnCare(from: applied.petSlot)
        }
        if let familiarity = receipt.familiarity {
            familiarities[familiarity.friendshipID] = familiarity
        }
        if sharedSpaceWindow?.model.cloudSyncState != .unavailable {
            sharedSpaceWindow?.model.cloudSyncState = .synced
        }
        if let friendshipID = receipt.friendshipID {
            updateFriendCare(
                friendshipID: friendshipID,
                publicCare: receipt.publicCare,
                familiarity: receipt.familiarity
            )
        }
    }

    private func updateFriendCare(
        friendshipID: FriendshipID,
        publicCare: PublicPetCareSummary,
        familiarity: PetFamiliarity?
    ) {
        guard let model = sharedSpaceWindow?.model else { return }
        model.friends = model.friends.map { friend in
            guard friend.friendshipID == friendshipID else { return friend }
            return FriendProfile(
                friendshipID: friend.friendshipID,
                accountID: friend.accountID,
                accountName: friend.accountName,
                petID: friend.petID,
                petName: friend.petName,
                friendsSince: friend.friendsSince,
                publicCare: publicCare,
                familiarity: familiarity ?? friend.familiarity,
                characterID: friend.characterID
            )
        }
    }

    private func requestOwnPetVisit(_ friendshipID: FriendshipID? = nil) {
        if let friendshipID {
            sharedSpaceWindow?.model.selectedFriendshipID = friendshipID
        }
        guard
            let profile = developmentProfile,
            let friend = selectedFriendProfile,
            let socialVisitCoordinator,
            activeOutgoingVisit == nil,
            activeIncomingVisit == nil,
            pendingVisits.isEmpty
        else {
            sharedSpaceWindow?.model.visitErrorMessage = "当前还不能发起新的串门"
            return
        }
        sharedSpaceWindow?.model.activeVisitFriendshipID = friend.friendshipID
        sharedSpaceWindow?.model.visitState = .sendingInvitation
        sharedSpaceWindow?.model.cloudSyncState = .pending
        Task { @MainActor [weak self] in
            do {
                let visit = try await socialVisitCoordinator.invite(
                    friendshipID: friend.friendshipID,
                    visitorPetID: profile.petID,
                    hostAccountID: friend.accountID,
                    reason: "主人想让宠物过去串门"
                )
                self?.pendingVisits[visit.id] = visit
                self?.refreshVisitInvitationQueue()
                self?.sharedSpaceWindow?.model.visitState = .invitationSent
                if self?.sharedSpaceWindow?.model.cloudSyncState != .unavailable {
                    self?.sharedSpaceWindow?.model.cloudSyncState = .synced
                }
            } catch {
                if shouldRetrySocialMutation(error) {
                    self?.sharedSpaceWindow?.model.visitState = .invitationSent
                    self?.sharedSpaceWindow?.model.cloudSyncState = .pending
                    self?.sharedSpaceWindow?.model.visitErrorMessage = "串门请求已排队，网络恢复后自动送达"
                } else {
                    self?.sharedSpaceWindow?.model.visitState = .away
                    self?.sharedSpaceWindow?.model.activeVisitFriendshipID = nil
                    self?.sharedSpaceWindow?.model.visitErrorMessage = "这次串门请求无法发送"
                }
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
                self?.world?.performLocalActivity(
                    .partner,
                    activity: .offeringGift,
                    emotion: .grateful,
                    duration: 1.4,
                    motionClip: .letterGive
                )
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
                guard sharedSpaceWindow?.model.timelineEvents.contains(where: {
                    $0.letterID == letterID
                }) == true else {
                    throw BackendClientError.invalidRequest
                }
                let letter = try await services.backend.fetchLetter(letterID)
                let alert = NSAlert()
                alert.messageText = "宠物带回来的信"
                alert.informativeText = letter.body ?? "信件正文暂不可用"
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
    private func togglePartnerVisit() {
        guard isSocialMVPConfigured else { return }
        if activeIncomingVisit?.status == .active || activeOutgoingVisit?.status == .active {
            requestRemoteVisitReturn()
        } else if !pendingVisits.isEmpty {
            sharedSpaceWindow?.model.agentMessage = "串门邀请正在等待好友回应"
        } else {
            requestOwnPetVisit()
        }
    }

    private func handleFriendDirectoryAction(_ action: FriendDirectoryAction) {
        switch action {
        case .refresh:
            guard services.configuration.backend.mode == .remote else {
                sharedSpaceWindow?.model.friendErrorMessage = "好友服务当前不可用，请稍后重试"
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
            loadFriendTimeline(friendshipID)

        case .inviteFriendPet(let friendshipID):
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

        case .sendOwnPet(let friendshipID):
            guard sharedSpaceWindow?.model.visitState == .away else { return }
            guard friendProfile(id: friendshipID) != nil else {
                sharedSpaceWindow?.model.friendErrorMessage = "这位好友已不在列表中，请刷新后重试"
                return
            }
            sharedSpaceWindow?.model.visitErrorMessage = nil
            sharedSpaceWindow?.model.activeVisitFriendshipID = friendshipID
            requestOwnPetVisit(friendshipID)

        case .respondToVisit(let response):
            respondToPendingVisit(response)

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

    private func respondToPendingVisit(_ response: VisitResponse) {
        guard let visitID = visitInvitationWindow?.currentInvitation?.id
            ?? pendingVisits.values
                .filter({ $0.responderAccountID == developmentProfile?.accountID })
                .sorted(by: { $0.createdAt < $1.createdAt })
                .first?.id
        else {
            sharedSpaceWindow?.model.visitErrorMessage = "这次串门请求已经处理，请刷新后查看"
            accountEventSyncCoordinator?.requestCatchUp()
            return
        }
        respondToPendingVisit(invitationID: visitID, response: response)
    }

    private func respondToPendingVisit(
        invitationID: PetVisitID,
        response: VisitResponse
    ) {
        guard services.configuration.backend.mode == .remote,
              let profile = developmentProfile,
              let visits = socialVisitCoordinator,
              let pending = pendingVisits[invitationID],
              pending.status == .pending,
              pending.responderAccountID == profile.accountID else {
            visitInvitationWindow?.resolve(invitationID)
            sharedSpaceWindow?.model.visitErrorMessage = "这次串门请求已经处理，请刷新后查看"
            accountEventSyncCoordinator?.requestCatchUp()
            return
        }

        sharedSpaceWindow?.model.friendOperationInProgress = true
        sharedSpaceWindow?.model.visitErrorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { sharedSpaceWindow?.model.friendOperationInProgress = false }
            do {
                let updated = try await visits.respond(
                    visitID: pending.id,
                    response: response,
                    actorType: .human
                )
                await visits.apply(updated)
                pendingVisits[updated.id] = nil
                visitInvitationWindow?.resolve(updated.id)

                if response == .decline {
                    sharedSpaceWindow?.model.activeVisitFriendshipID = nil
                    sharedSpaceWindow?.model.visitState = .away
                } else if updated.visitorPetID == profile.petID {
                    activeOutgoingVisit = updated
                    activeIncomingVisit = nil
                    animateOwnPetLeavingForVisit()
                    sharedSpaceWindow?.model.visitState = .ownPetVisiting
                } else {
                    activeIncomingVisit = updated
                    activeOutgoingVisit = nil
                    announceVisitArrival()
                    sharedSpaceWindow?.model.visitState = .visiting
                }
                if sharedSpaceWindow?.model.cloudSyncState != .unavailable {
                    sharedSpaceWindow?.model.cloudSyncState = .synced
                }
                accountEventSyncCoordinator?.requestCatchUp()
            } catch {
                if shouldRetrySocialMutation(error) {
                    sharedSpaceWindow?.model.cloudSyncState = .pending
                    visitInvitationWindow?.failResponse(
                        for: invitationID,
                        message: "网络暂时没有送达，请重试"
                    )
                } else {
                    pendingVisits[invitationID] = nil
                    visitInvitationWindow?.resolve(invitationID)
                    sharedSpaceWindow?.model.visitErrorMessage = "这次邀请已经失效"
                }
                accountEventSyncCoordinator?.requestCatchUp()
            }
        }
    }

    private func loadFriendTimeline(_ friendshipID: FriendshipID) {
        guard let model = sharedSpaceWindow?.model else { return }
        let localEvents = model.timelineEvents.filter {
            $0.friendshipID == friendshipID
        }
        model.friendTimelineEvents[friendshipID] = deduplicatedTimeline(localEvents)
        model.friendTimelineError[friendshipID] = nil

        guard services.configuration.backend.mode == .remote else { return }
        model.friendTimelineLoading.insert(friendshipID)
        Task { @MainActor [weak self] in
            guard let self, let model = sharedSpaceWindow?.model else { return }
            defer { model.friendTimelineLoading.remove(friendshipID) }
            do {
                var cursor: Int64 = 0
                var fetched: [PersonalTimelineEvent] = []
                while true {
                    let page = try await services.backend.fetchAccountEvents(
                        after: cursor,
                        limit: 100,
                        timelineVisible: true
                    )
                    let converted = page.events
                        .filter { $0.friendshipID == friendshipID }
                        .compactMap { $0.timelineEvent() }
                    fetched.append(contentsOf: converted)
                    guard page.events.count == 100, page.nextCursor > cursor else { break }
                    cursor = page.nextCursor
                }
                let latestLocalEvents = model.timelineEvents.filter {
                    $0.friendshipID == friendshipID
                }
                model.friendTimelineEvents[friendshipID] = deduplicatedTimeline(
                    latestLocalEvents + fetched
                )
                model.friendTimelineError[friendshipID] = nil
            } catch {
                model.friendTimelineError[friendshipID] = localEvents.isEmpty
                    ? "暂时无法加载这位好友的事件，请稍后重试"
                    : "远端事件暂时未同步，当前显示本地记录"
            }
        }
    }

    private func deduplicatedTimeline(
        _ events: [PersonalTimelineEvent]
    ) -> [PersonalTimelineEvent] {
        var seen = Set<String>()
        return events
            .sorted { $0.occurredAt > $1.occurredAt }
            .filter { seen.insert($0.id).inserted }
    }

    private func handleProfileAction(_ action: ProfileAction) {
        switch action {
        case .signInWithGitHub:
            startGitHubSignIn()
        case .cancelSignIn:
            cancelGitHubSignIn()
        case .signOut:
            signOut()
        case .saveProfile(let accountName, let petName):
            saveCurrentProfile(accountName: accountName, petName: petName)
        case .selectPetCharacter(let characterID):
            selectPetCharacter(characterID)
        case .acknowledgePetCharacterSelection:
            sharedSpaceWindow?.model.petCharacterSelectionState = .hidden
        }
    }

    private func selectPetCharacter(_ characterID: PetCharacterID) {
        guard let model = sharedSpaceWindow?.model else { return }
        switch model.petCharacterSelectionState {
        case .required, .failed:
            break
        case .hidden, .saving, .pendingSync, .confirmed, .conflict:
            return
        }

        let idempotencyKey = UUID()
        applyOwnPetCharacter(characterID)
        model.petCharacterSelectionState = .saving(characterID)
        model.cloudSyncState = .pending

        guard let coordinator = socialVisitCoordinator else {
            model.petCharacterSelectionState = .pendingSync(characterID)
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let model = self.sharedSpaceWindow?.model else { return }
            do {
                let snapshot = try await coordinator.updateOwnPetAppearance(
                    characterID: characterID,
                    idempotencyKey: idempotencyKey
                )
                guard let authoritative = PetCharacterID(appearance: snapshot.appearance) else {
                    throw BackendClientError.invalidResponse
                }
                applyOwnPetCharacter(authoritative)
                model.petCharacterSelectionState = authoritative == characterID
                    ? .confirmed(authoritative)
                    : .conflict(authoritative: authoritative)
                model.cloudSyncState = .synced
            } catch BackendClientError.httpStatus(let statusCode, let code)
                where statusCode == 409 && code == "appearance_locked" {
                do {
                    let bootstrap = try await services.backend.fetchSyncBootstrap()
                    guard let authoritative = PetCharacterID(
                        appearance: bootstrap.pet.appearance
                    ) else { throw BackendClientError.invalidResponse }
                    applyOwnPetCharacter(authoritative)
                    model.petCharacterSelectionState = .conflict(
                        authoritative: authoritative
                    )
                    model.cloudSyncState = .synced
                } catch {
                    model.petCharacterSelectionState = .failed(
                        preselected: characterID,
                        message: "账号已有角色，但暂时无法取回。请重新连接后再试。"
                    )
                }
            } catch {
                if shouldRetrySocialMutation(error) {
                    model.petCharacterSelectionState = .pendingSync(characterID)
                    model.cloudSyncState = .pending
                } else {
                    model.petCharacterSelectionState = .failed(
                        preselected: characterID,
                        message: "角色没有确认成功，请检查账号状态后重试。"
                    )
                    if model.cloudSyncState != .unavailable {
                        model.cloudSyncState = .synced
                    }
                }
            }
        }
    }

    private func startGitHubSignIn() {
        guard services.configuration.backend.mode == .remote,
              services.configuration.clientProfile == .standard else {
            sharedSpaceWindow?.model.authenticationErrorMessage = "账号服务当前不可用，请稍后重试"
            return
        }
        githubSignInTask?.cancel()
        sharedSpaceWindow?.model.authenticationOperationInProgress = true
        sharedSpaceWindow?.model.authenticationErrorMessage = nil
        sharedSpaceWindow?.model.githubDeviceCodeWasAutoCopied = false
        sharedSpaceWindow?.model.cloudSyncState = .connecting
        githubSignInTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let authorization = try await services.backend.startGitHubDeviceAuthorization()
                sharedSpaceWindow?.model.beginGitHubAuthorization(
                    userCode: authorization.userCode,
                    verificationURL: authorization.verificationURI
                )
                NSWorkspace.shared.open(authorization.verificationURI)
                let deviceID = DeviceID(rawValue: UUID().uuidString)
                let device = DeviceMetadata(
                    id: deviceID,
                    displayName: Host.current().localizedName ?? "Mino Mac",
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                )
                let expiresAt = Date().addingTimeInterval(TimeInterval(authorization.expiresIn))
                var retryAfter = max(1, authorization.interval)
                while Date() < expiresAt {
                    try await Task.sleep(for: .seconds(retryAfter))
                    let completion: GitHubDeviceCompletion
                    do {
                        completion = try await services.backend.completeGitHubDeviceAuthorization(
                            deviceCode: authorization.deviceCode,
                            device: device
                        )
                    } catch {
                        switch githubDevicePollingDecision(
                            for: error,
                            currentInterval: retryAfter,
                            expiresAt: expiresAt
                        ) {
                        case .retry(let afterSeconds):
                            retryAfter = afterSeconds
                            continue
                        case .stop(let failure):
                            throw failure
                        }
                    }
                    if completion.status == .pending {
                        retryAfter = max(1, completion.retryAfterSeconds ?? retryAfter)
                        continue
                    }
                    guard let session = completion.session else {
                        throw GitHubDevicePollingFailure.failed
                    }
                    do {
                        try await services.sessionStore.save(sessionCredential(from: session))
                    } catch {
                        sharedSpaceWindow?.model.authenticationState = .signedOut
                        sharedSpaceWindow?.model.githubDeviceCodeWasAutoCopied = false
                        sharedSpaceWindow?.model.cloudSyncState = .localOnly
                        sharedSpaceWindow?.model.authenticationOperationInProgress = false
                        sharedSpaceWindow?.model.authenticationErrorMessage =
                            "GitHub 授权已完成，但 Mino 无法写入本地安全存储。请检查磁盘权限后重试"
                        MinoLog.lifecycle.error(
                            "GitHub session persistence failed: \(String(describing: error), privacy: .public)"
                        )
                        return
                    }
                    sharedSpaceWindow?.model.authenticationState = .signedIn
                    sharedSpaceWindow?.model.githubDeviceCodeWasAutoCopied = false
                    sharedSpaceWindow?.model.cloudSyncState = .connecting
                    sharedSpaceWindow?.model.authenticationOperationInProgress = false
                    startSocialMVPIfConfigured()
                    return
                }
                throw GitHubDevicePollingFailure.expired
            } catch is CancellationError {
                return
            } catch let failure as GitHubDevicePollingFailure {
                sharedSpaceWindow?.model.authenticationState = .signedOut
                sharedSpaceWindow?.model.githubDeviceCodeWasAutoCopied = false
                sharedSpaceWindow?.model.cloudSyncState = .localOnly
                sharedSpaceWindow?.model.authenticationOperationInProgress = false
                sharedSpaceWindow?.model.authenticationErrorMessage = failure.userMessage
            } catch {
                sharedSpaceWindow?.model.authenticationState = .signedOut
                sharedSpaceWindow?.model.githubDeviceCodeWasAutoCopied = false
                sharedSpaceWindow?.model.cloudSyncState = .localOnly
                sharedSpaceWindow?.model.authenticationOperationInProgress = false
                sharedSpaceWindow?.model.authenticationErrorMessage =
                    "暂时无法连接 GitHub，请检查网络后重试"
            }
        }
    }

    private func cancelGitHubSignIn() {
        githubSignInTask?.cancel()
        githubSignInTask = nil
        sharedSpaceWindow?.model.authenticationState = .signedOut
        sharedSpaceWindow?.model.githubDeviceCodeWasAutoCopied = false
        sharedSpaceWindow?.model.cloudSyncState = .localOnly
        sharedSpaceWindow?.model.authenticationOperationInProgress = false
        sharedSpaceWindow?.model.authenticationErrorMessage = nil
    }

    private func signOut() {
        githubSignInTask?.cancel()
        sharedSpaceWindow?.model.authenticationOperationInProgress = true
        sharedSpaceWindow?.model.githubDeviceCodeWasAutoCopied = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let oldCredential = try? await services.sessionStore.load()
            try? await services.backend.logout()
            try? await services.sessionStore.clear()
            if let accountID = oldCredential?.accountID {
                try? await services.accountEventCursorStore.clear(for: accountID)
            }
            try? await services.personalTimelineStore.clear()
            try? await services.socialMutationOutbox.clear()
            if let petID = developmentProfile?.petID {
                try? await agentMemoryStore?.removeAll(for: petID)
            }
            stopSocialRuntime()
            applyCurrentProfile(Self.defaultProfile(for: .standard))
            sharedSpaceWindow?.model.authenticationState = .signedOut
            sharedSpaceWindow?.model.cloudSyncState = .localOnly
            sharedSpaceWindow?.model.authenticationOperationInProgress = false
            sharedSpaceWindow?.model.authenticationErrorMessage = nil
        }
    }

    private func sessionCredential(from session: AccountSession) -> SessionCredential {
        SessionCredential(
            accountID: session.accountID,
            deviceID: session.device.id,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            accessTokenExpiresAt: session.accessExpiresAt,
            issuedAt: Date()
        )
    }

    private func saveCurrentProfile(accountName: String, petName: String) {
        let normalizedAccountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPetName = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccountName.isEmpty, normalizedAccountName.count <= 40 else {
            sharedSpaceWindow?.model.profileErrorMessage = "账号昵称需要填写，且不能超过 40 个字符"
            return
        }
        guard !normalizedPetName.isEmpty, normalizedPetName.count <= 24 else {
            sharedSpaceWindow?.model.profileErrorMessage = "宠物名字需要填写，且不能超过 24 个字符"
            return
        }

        sharedSpaceWindow?.model.profileOperationInProgress = true
        sharedSpaceWindow?.model.profileErrorMessage = nil
        sharedSpaceWindow?.model.profileSuccessMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { sharedSpaceWindow?.model.profileOperationInProgress = false }
            do {
                let profile: CurrentProfile
                if services.configuration.backend.mode == .remote {
                    profile = try await services.backend.updateCurrentProfile(
                        accountName: normalizedAccountName,
                        petName: normalizedPetName
                    )
                } else {
                    profile = CurrentProfile(
                        accountID: currentProfile.accountID,
                        petID: currentProfile.petID,
                        accountName: normalizedAccountName,
                        petName: normalizedPetName,
                        createdAt: currentProfile.createdAt
                    )
                }
                applyCurrentProfile(profile)
                if services.configuration.backend.mode == .remote {
                    try? await refreshFriendDirectory()
                }
                sharedSpaceWindow?.model.profileSuccessMessage = "个人资料已保存"
            } catch {
                sharedSpaceWindow?.model.profileErrorMessage = "资料没有保存成功，请检查连接后重试"
            }
        }
    }

    private func applyCurrentProfile(_ profile: CurrentProfile) {
        currentProfile = profile
        identityMenuItem?.title = "我的宠物 · \(profile.petName)"
        sharedSpaceWindow?.model.currentProfile = profile
        sharedSpaceWindow?.model.localAccountID = profile.accountID
        world?.setDisplayName(profile.petName, for: .mine)
        petWindows[.mine]?.updateDisplayName(profile.petName)
        refreshPetOperationsMenus()
        refreshVisitInvitationQueue()
        try? LocalProfilePreferences.save(
            profile,
            for: services.configuration.clientProfile
        )
        if let agentCoordinator {
            Task { await agentCoordinator.updateDisplayName(profile.petName) }
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

    private func friendProfile(for visit: Visit) -> FriendProfile? {
        if visit.visitorOwnerAccountID == developmentProfile?.accountID {
            return sharedSpaceWindow?.model.friends.first {
                $0.accountID == visit.hostAccountID
            }
        }
        return sharedSpaceWindow?.model.friends.first {
            $0.accountID == visit.visitorOwnerAccountID || $0.petID == visit.visitorPetID
        }
    }

    private func refreshVisitInvitationQueue() {
        guard let accountID = developmentProfile?.accountID else {
            visitInvitationWindow?.dismissAll()
            return
        }
        let presentations = pendingVisits.values
            .filter { $0.status == .pending && $0.responderAccountID == accountID }
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.rawValue < $1.id.rawValue
                    : $0.createdAt < $1.createdAt
            }
            .map { visit in
                let friend = friendProfile(for: visit)
                let direction: VisitPresentationDirection =
                    visit.visitorOwnerAccountID == accountID
                    ? .myPetToFriendDesktop
                    : .friendPetToMyDesktop
                return VisitInvitationPresentation(
                    id: visit.id,
                    friendName: friend?.accountName ?? "好友",
                    petName: direction == .myPetToFriendDesktop
                        ? currentProfile.petName
                        : (friend?.petName ?? "好友的 Mino"),
                    direction: direction,
                    characterID: direction == .myPetToFriendDesktop
                        ? ownPetCharacterID
                        : (friend?.characterID ?? fallbackFriendCharacter)
                )
            }
        visitInvitationWindow?.replaceQueue(presentations)
    }

    private func friendPetID(
        for visit: Visit,
        localPetID: PetProfileID
    ) -> PetProfileID? {
        if visit.visitorPetID != localPetID {
            return visit.visitorPetID
        }
        return friendProfile(for: visit)?.petID
    }

    private func submitFriendRequest(to accountID: AccountID) {
        guard services.configuration.backend.mode == .remote else {
            sharedSpaceWindow?.model.friendErrorMessage = "账号服务当前不可用，暂时无法发送好友申请"
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
                    friendshipID: FriendshipID(rawValue: requestID.rawValue),
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
        for friend in sortedFriends {
            if let familiarity = friend.familiarity {
                familiarities[friend.friendshipID] = familiarity
            }
            if let characterID = friend.characterID {
                sharedSpaceWindow?.model.friendCharacterIDs[friend.petID] = characterID
            }
        }
        if let visitorPetID = activeIncomingVisit?.visitorPetID,
           let characterID = sharedSpaceWindow?.model.friendCharacterIDs[visitorPetID] {
            world?.setCharacter(characterID, for: .partner)
        }
        if let activeFriend = sortedFriends.first(where: {
            $0.friendshipID == activeIncomingVisit?.friendshipID
        }), let publicCare = activeFriend.publicCare {
            careSession.replaceCare(PetCareSession.care(from: publicCare), for: .partner)
        }
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
        }
        refreshVisitInvitationQueue()
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
            sharedSpaceWindow?.model.visitState = .visiting
            world.animatePetEntering(
                visitingFriendPetState(for: nil, in: world),
                beside: .mine,
                from: .nearest,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ) { [weak self] in
                self?.petWindows[.partner]?.showSpeech("我来串门啦，一起玩吧。", duration: 2.4)
                self?.world?.performLocalActivity(
                    .partner,
                    activity: .celebrating,
                    emotion: .excited,
                    duration: 1.15,
                    motionClip: .welcome
                )
            }
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
        visitTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await animateVisitDeparture(for: .partner)
            world?.setVisiblePet(nil, for: .partner)
            await persistTimelineEvent(PersonalTimelineEvent(kind: .visitReturned))
            sharedSpaceWindow?.model.visitState = .away
        }
    }

    private func sendRemoteVisitInvitation(to friend: FriendProfile) {
        visitTransitionTask?.cancel()
        sharedSpaceWindow?.model.visitState = .sendingInvitation
        sharedSpaceWindow?.model.cloudSyncState = .pending
        guard let profile = developmentProfile,
              let visits = socialVisitCoordinator else {
            sharedSpaceWindow?.model.visitState = .away
            sharedSpaceWindow?.model.visitErrorMessage = "好友服务还没有准备好"
            return
        }
        visitTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let visit = try await visits.invite(
                    friendshipID: friend.friendshipID,
                    visitorPetID: friend.petID,
                    hostAccountID: profile.accountID,
                    reason: "好友邀请宠物过来玩"
                )
                pendingVisits[visit.id] = visit
                refreshVisitInvitationQueue()
                sharedSpaceWindow?.model.visitState = .invitationSent
                if sharedSpaceWindow?.model.cloudSyncState != .unavailable {
                    sharedSpaceWindow?.model.cloudSyncState = .synced
                }
            } catch {
                if shouldRetrySocialMutation(error) {
                    sharedSpaceWindow?.model.visitState = .invitationSent
                    sharedSpaceWindow?.model.cloudSyncState = .pending
                    sharedSpaceWindow?.model.visitErrorMessage =
                        "串门请求已排队，网络恢复后自动送达"
                } else {
                    sharedSpaceWindow?.model.visitState = .away
                    sharedSpaceWindow?.model.activeVisitFriendshipID = nil
                    sharedSpaceWindow?.model.visitErrorMessage = "这次串门请求无法发送"
                }
            }
        }
    }

    private func requestRemoteVisitReturn() {
        visitTransitionTask?.cancel()
        if let visits = socialVisitCoordinator,
           let activeVisit = activeIncomingVisit ?? activeOutgoingVisit {
            let wasIncoming = activeIncomingVisit?.id == activeVisit.id
            sharedSpaceWindow?.model.visitState = .returning
            sharedSpaceWindow?.model.cloudSyncState = .pending
            optimisticallyReturningVisitIDs.insert(activeVisit.id)
            visitTransitionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                async let endRequest = visits.end(visitID: activeVisit.id)
                if wasIncoming {
                    await animateVisitDeparture(for: .partner)
                    world?.setVisiblePet(nil, for: .partner)
                } else {
                    animateOwnPetReturningHome()
                }
                do {
                    let ended = try await endRequest
                    await visits.apply(ended)
                    if wasIncoming {
                        activeIncomingVisit = nil
                        announcedIncomingVisitID = nil
                    } else {
                        activeOutgoingVisit = nil
                    }
                    sharedSpaceWindow?.model.visitState = .away
                    if sharedSpaceWindow?.model.cloudSyncState != .unavailable {
                        sharedSpaceWindow?.model.cloudSyncState = .synced
                    }
                    accountEventSyncCoordinator?.requestCatchUp()
                } catch {
                    if shouldRetrySocialMutation(error) {
                        sharedSpaceWindow?.model.cloudSyncState = .pending
                        sharedSpaceWindow?.model.visitErrorMessage =
                            "回家请求已排队，网络恢复后自动完成"
                    } else {
                        optimisticallyReturningVisitIDs.remove(activeVisit.id)
                        if wasIncoming, let world {
                            world.setVisiblePet(
                                visitingFriendPetState(for: activeVisit, in: world),
                                for: .partner
                            )
                            sharedSpaceWindow?.model.visitState = .visiting
                        } else {
                            world?.setVisiblePet(nil, for: .mine)
                            sharedSpaceWindow?.model.visitState = .ownPetVisiting
                        }
                        if sharedSpaceWindow?.model.cloudSyncState != .unavailable {
                            sharedSpaceWindow?.model.cloudSyncState = .synced
                        }
                        sharedSpaceWindow?.model.visitErrorMessage = "这次回家请求无法完成"
                    }
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

    private func persistTimelineEvent(_ event: PersonalTimelineEvent) async {
        do {
            try await services.personalTimelineStore.append(event)
            let timeline = try await services.personalTimelineStore.load()
            sharedSpaceWindow?.model.timelineEvents = timeline
            if let friendshipID = event.friendshipID {
                sharedSpaceWindow?.model.friendTimelineEvents[friendshipID] =
                    deduplicatedTimeline(
                        timeline.filter { $0.friendshipID == friendshipID }
                    )
            }
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
    private func resetPetPositions() {
        world?.resetPetPositions()
    }

    private func visitingFriendPetState(
        for visit: Visit?,
        in world: PetWorld
    ) -> PetRuntimeState {
        let identity = runtimeIdentity
        let friend = visit.flatMap(friendProfile(for:)) ?? selectedFriendProfile
        let anchor = world.pets[.mine]?.position
            ?? CGPoint(x: NSScreen.main?.visibleFrame.midX ?? 720, y: 105)
        return PetRuntimeState(
            id: .partner,
            displayName: friend?.petName ?? identity.fallbackFriendPetName,
            position: CGPoint(x: anchor.x + 190, y: anchor.y),
            facing: .left,
            activity: .idle,
            emotion: .content,
            avatar: identity.fallbackFriendAvatar,
            characterID: friend.flatMap {
                sharedSpaceWindow?.model.friendCharacterIDs[$0.petID]
            } ?? fallbackFriendCharacter
        )
    }

    private func announceVisitArrival() {
        guard let visit = activeIncomingVisit,
              announcedIncomingVisitID != visit.id,
              let world else { return }
        announcedIncomingVisitID = visit.id
        let state = visitingFriendPetState(for: visit, in: world)
        world.animatePetEntering(
            state,
            beside: .mine,
            from: .nearest,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) { [weak self] in
            guard let self, self.activeIncomingVisit?.id == visit.id else { return }
            self.petWindows[.partner]?.showSpeech("我来串门啦，一起玩吧。", duration: 2.4)
            self.world?.performLocalActivity(
                .partner,
                activity: .celebrating,
                emotion: .excited,
                duration: 1.15,
                motionClip: .welcome
            )
            self.world?.performLocalActivity(
                .mine,
                activity: .celebrating,
                emotion: .happy,
                duration: 1.15,
                motionClip: .happy
            )
        }
    }

    private func announceVisitDeparture(
        for petID: PetID,
        completion: (() -> Void)? = nil
    ) {
        petWindows[petID]?.showSpeech("今天玩得很开心，下次见。", duration: 2.4)
        guard let world else {
            completion?()
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let waveDuration = reduceMotion ? 0.18 : 0.9
        world.performLocalActivity(
            petID,
            activity: .celebrating,
            emotion: .happy,
            duration: waveDuration,
            motionClip: .wave
        )
        Task { @MainActor [weak world] in
            try? await Task.sleep(for: .seconds(waveDuration))
            world?.animatePetExiting(
                petID,
                toward: .nearest,
                reduceMotion: reduceMotion,
                completion: completion
            )
        }
    }

    private func animateVisitDeparture(for petID: PetID) async {
        await withCheckedContinuation { continuation in
            announceVisitDeparture(for: petID) {
                continuation.resume()
            }
        }
    }

    private func animateOwnPetLeavingForVisit() {
        guard let visitID = activeOutgoingVisit?.id else { return }
        departingOwnPetVisitID = visitID
        petWindows[.mine]?.showSpeech("我去串门啦，晚点回来。", duration: 2.4)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let waveDuration = reduceMotion ? 0.18 : 0.9
        world?.performLocalActivity(
            .mine,
            activity: .celebrating,
            emotion: .happy,
            duration: waveDuration,
            motionClip: .wave
        )
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(waveDuration))
            guard let self, self.departingOwnPetVisitID == visitID else { return }
            world?.animatePetExiting(
                .mine,
                toward: .nearest,
                reduceMotion: reduceMotion
            ) { [weak self] in
                guard let self,
                      self.departingOwnPetVisitID == visitID,
                      self.activeOutgoingVisit?.status == .active else { return }
                self.departingOwnPetVisitID = nil
                self.world?.setVisiblePet(nil, for: .mine)
            }
        }
    }

    private func animateOwnPetReturningHome() {
        guard let world else { return }
        departingOwnPetVisitID = nil
        let state = localPetRuntimeState()
        world.animatePetEntering(
            state,
            toward: state.position,
            from: .nearest,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) { [weak self] in
            guard let self else { return }
            self.petWindows[.mine]?.showSpeech("我回来啦，给你带了故事。", duration: 2.4)
            self.world?.performLocalActivity(
                .mine,
                activity: .celebrating,
                emotion: .happy,
                duration: 1.15,
                motionClip: .welcome
            )
        }
    }

    private func localPetRuntimeState() -> PetRuntimeState {
        let fullFrame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = Self.visibleFrame(
            fullFrame,
            constrainedTo: services.configuration.clientProfile.screenRegion
        )
        let identity = runtimeIdentity
        return PetRuntimeState(
            id: .mine,
            displayName: identity.localPetName,
            position: CGPoint(x: frame.midX, y: frame.minY + 105),
            facing: .right,
            activity: .idle,
            emotion: .content,
            avatar: identity.localAvatar,
            characterID: ownPetCharacterID
        )
    }

    private func ensureLocalPetVisible() {
        guard let world, world.pets[.mine] == nil else { return }
        world.setVisiblePet(localPetRuntimeState(), for: .mine)
    }

    private var runtimeDefaultCharacter: PetCharacterID {
        services.configuration.clientProfile.id == "bob"
            ? .retrieverYellow
            : .malteseWhite
    }

    private var fallbackFriendCharacter: PetCharacterID {
        runtimeDefaultCharacter == .malteseWhite ? .retrieverYellow : .malteseWhite
    }

    private var ownPetCharacterID: PetCharacterID {
        sharedSpaceWindow?.model.ownPetCharacterID ?? runtimeDefaultCharacter
    }

    private func applyOwnPetCharacter(_ characterID: PetCharacterID) {
        sharedSpaceWindow?.model.ownPetCharacterID = characterID
        sharedSpaceWindow?.model.friendCharacterIDs[currentProfile.petID] = characterID
        if world?.pets[.mine] == nil, activeOutgoingVisit == nil {
            world?.setVisiblePet(localPetRuntimeState(), for: .mine)
        } else {
            world?.setCharacter(characterID, for: .mine)
        }
    }

    private var runtimeIdentity: RuntimePetIdentity {
        switch services.configuration.clientProfile.id {
        case "bob":
            RuntimePetIdentity(
                localPetName: currentProfile.petName,
                fallbackFriendPetName: "奶糖",
                localAvatar: .partner,
                fallbackFriendAvatar: .mine
            )
        default:
            RuntimePetIdentity(
                localPetName: currentProfile.petName,
                fallbackFriendPetName: "团子",
                localAvatar: .mine,
                fallbackFriendAvatar: .partner
            )
        }
    }

    private static func defaultProfile(
        for runtimeProfile: ClientRuntimeProfile
    ) -> CurrentProfile {
        switch runtimeProfile.id {
        case "alice":
            CurrentProfile(
                accountID: AccountID(rawValue: "00000000-0000-4000-8000-00000000000a"),
                petID: PetProfileID(rawValue: "00000000-0000-4000-8000-0000000000a1"),
                accountName: "Alice",
                petName: "奶糖",
                createdAt: Date(timeIntervalSince1970: 0)
            )
        case "bob":
            CurrentProfile(
                accountID: AccountID(rawValue: "00000000-0000-4000-8000-00000000000b"),
                petID: PetProfileID(rawValue: "00000000-0000-4000-8000-0000000000b1"),
                accountName: "Bob",
                petName: "团子",
                createdAt: Date(timeIntervalSince1970: 0)
            )
        default:
            CurrentProfile(
                accountID: AccountID(rawValue: "local-account"),
                petID: PetProfileID(rawValue: "local-pet"),
                accountName: "我的 Mino",
                petName: "奶糖",
                createdAt: Date()
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
        world?.restorePetsToVisibleScreens()
    }

    @objc
    private func systemDidWake() {
        accountEventSyncCoordinator?.requestCatchUp()
    }

    private func startSocialMVPIfConfigured() {
        guard services.configuration.backend.mode == .remote else { return }
        let runtimeProfile = services.configuration.clientProfile
        sharedSpaceWindow?.model.cloudSyncState = .connecting

        socialBootstrapTask?.cancel()
        socialBootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let profile: DevBootstrapProfile
                if runtimeProfile == .standard {
                    guard let credential = try await validStandardCredential() else {
                        sharedSpaceWindow?.model.authenticationState = .signedOut
                        sharedSpaceWindow?.model.cloudSyncState = .localOnly
                        visitInvitationWindow?.dismissAll()
                        return
                    }
                    let bootstrap = try await services.backend.fetchSyncBootstrap()
                    profile = DevBootstrapProfile(
                        profile: "standard",
                        token: credential.accessToken,
                        refreshToken: credential.refreshToken ?? "",
                        accountID: bootstrap.account.id,
                        deviceID: bootstrap.currentDevice.id,
                        petID: bootstrap.pet.petID,
                        accountName: bootstrap.account.displayName,
                        petName: bootstrap.pet.displayName
                    )
                    sharedSpaceWindow?.model.authenticationState = .signedIn
                } else {
                    profile = try await services.backend.bootstrapDevelopmentProfile(
                        runtimeProfile.id
                    )
                    try await services.sessionStore.save(
                        SessionCredential(
                            accountID: profile.accountID,
                            deviceID: profile.deviceID,
                            accessToken: profile.token,
                            refreshToken: profile.refreshToken,
                            accessTokenExpiresAt: .distantFuture,
                            issuedAt: Date()
                        )
                    )
                }
                developmentProfile = profile
                try await initializeSocialRuntime(profile: profile)
            } catch {
                if case BackendClientError.httpStatus(let statusCode, _) = error,
                   statusCode == 401 {
                    try? await services.sessionStore.clear()
                    stopSocialRuntime()
                    applyCurrentProfile(Self.defaultProfile(for: .standard))
                    sharedSpaceWindow?.model.authenticationState = .signedOut
                    sharedSpaceWindow?.model.cloudSyncState = .localOnly
                    sharedSpaceWindow?.model.visitErrorMessage = nil
                } else {
                    sharedSpaceWindow?.model.cloudSyncState = .unavailable
                    sharedSpaceWindow?.model.visitErrorMessage = "云端暂不可用，已保留当前内容"
                }
                MinoLog.backend.error(
                    "Social account bootstrap failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func validStandardCredential() async throws -> SessionCredential? {
        guard var credential = try await services.sessionStore.load() else { return nil }
        if credential.needsRefresh() {
            guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
                try await services.sessionStore.clear()
                return nil
            }
            let session = try await services.backend.refreshSession(refreshToken)
            credential = sessionCredential(from: session)
            try await services.sessionStore.save(credential)
        }
        return credential
    }

    private func initializeSocialRuntime(profile: DevBootstrapProfile) async throws {
        let remoteProfile = try await services.backend.fetchCurrentProfile()
        applyCurrentProfile(remoteProfile)
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
            displayName: remoteProfile.petName,
            friends: agentFriends
        )
        let localAgent = LocalPetAgent(
            identity: identity,
            modelClient: modelClient,
            memoryStore: memoryStore
        )
        let conversations = ConversationCoordinator(
            backend: services.backend,
            outbox: services.socialMutationOutbox
        )
        let visits = VisitCoordinator(
            backend: services.backend,
            outbox: services.socialMutationOutbox
        )
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

        startAccountEventSync()
        startSocialOutboxRetryLoop(visits)
    }

    private func stopSocialRuntime() {
        socialBootstrapTask?.cancel()
        accountEventSyncCoordinator?.stop()
        accountEventSyncCoordinator = nil
        socialOutboxRetryTask?.cancel()
        conversationCoordinator = nil
        socialVisitCoordinator = nil
        agentCoordinator = nil
        agentMemoryStore = nil
        visitProjectionReducer = nil
        developmentProfile = nil
        activeIncomingVisit = nil
        activeOutgoingVisit = nil
        pendingVisits = [:]
        optimisticallyReturningVisitIDs.removeAll()
        departingOwnPetVisitID = nil
        visitInvitationWindow?.dismissAll()
        isPrimaryAgentDevice = false
        sharedSpaceWindow?.model.friends = []
        sharedSpaceWindow?.model.friendRequests = []
        sharedSpaceWindow?.model.timelineEvents = []
        sharedSpaceWindow?.model.friendCharacterIDs = [:]
        sharedSpaceWindow?.model.ownPetCharacterID =
            services.configuration.clientProfile == .standard
            ? nil
            : runtimeDefaultCharacter
        sharedSpaceWindow?.model.petCharacterSelectionState = .hidden
        sharedSpaceWindow?.model.activeVisitFriendshipID = nil
        sharedSpaceWindow?.model.visitState = .away
        sharedSpaceWindow?.model.cloudSyncState = .localOnly
        world?.setVisiblePet(nil, for: .partner)
        world?.setCharacter(runtimeDefaultCharacter, for: .mine)
        ensureLocalPetVisible()
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

    private func startSocialOutboxRetryLoop(_ visits: VisitCoordinator) {
        socialOutboxRetryTask?.cancel()
        socialOutboxRetryTask = Task {
            while !Task.isCancelled {
                await visits.retryPendingMutations()
                do {
                    try await Task.sleep(for: .seconds(30))
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
        async let activeRequest = fetchVisitsAcrossFriends(status: .active)
        async let pendingRequest = fetchVisitsAcrossFriends(status: .pending)
        let (activeVisits, restoredPendingVisits) = try await (activeRequest, pendingRequest)
        pendingVisits = Dictionary(uniqueKeysWithValues: restoredPendingVisits.map { ($0.id, $0) })
        for visit in restoredPendingVisits {
            await visits.apply(visit)
        }
        refreshVisitInvitationQueue()
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
            } else {
                activeIncomingVisit = active
                activeOutgoingVisit = nil
                announceVisitArrival()
                sharedSpaceWindow?.model.visitState = .visiting
            }
            return
        }

        guard let pending = restoredPendingVisits
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first(where: {
            $0.visitorPetID == profile.petID || $0.hostAccountID == profile.accountID
        }) else {
            return
        }
        sharedSpaceWindow?.model.activeVisitFriendshipID =
            friendProfile(for: pending)?.friendshipID

        guard pending.responderAccountID == profile.accountID else {
            sharedSpaceWindow?.model.visitState = .invitationSent
            return
        }

        sharedSpaceWindow?.model.visitState = .consideringInvitation
    }

    private func fetchVisitsAcrossFriends(status: VisitStatus) async throws -> [Visit] {
        try await services.backend.fetchVisits(status: status)
    }

    /// Restores each friend's active conversation and bounded transcript before
    /// missed events are replayed.
    private func restoreSocialConversationState(
        agent: AgentCoordinator
    ) async throws {
        let activeConversations = try await services.backend.fetchConversations()
        for active in activeConversations {
            let messages = try await services.backend.fetchConversationMessages(
                conversationID: active.id
            )
            await agent.restoreConversation(active, messages: messages)
        }
    }

    private func startAccountEventSync() {
        guard let profile = developmentProfile else { return }
        accountEventSyncCoordinator?.stop()
        visitProjectionReducer = VisitProjectionReducer(
            accountID: profile.accountID,
            ownPetID: profile.petID
        )
        let coordinator = AccountEventSyncCoordinator(
            accountID: profile.accountID,
            backend: services.backend,
            realtime: services.realtimeSignals,
            cursorStore: services.accountEventCursorStore
        )
        accountEventSyncCoordinator = coordinator
        coordinator.start(
            onBootstrap: { [weak self] bootstrap in
                guard let self else { return }
                try await self.applySyncBootstrap(bootstrap)
            },
            onEvent: { [weak self] event in
                guard let self else { return false }
                return try await self.handleAccountEvent(event)
            },
            onStatusChange: { [weak self] status in
                guard let self, let model = self.sharedSpaceWindow?.model else { return }
                switch status {
                case .stopped:
                    if model.authenticationState == .signedOut
                        || model.authenticationState == .offline {
                        model.cloudSyncState = .localOnly
                    }
                case .bootstrapping, .catchingUp:
                    if model.cloudSyncState != .pending {
                        model.cloudSyncState = .connecting
                    }
                case .realtime, .polling:
                    if model.cloudSyncState != .pending {
                        model.cloudSyncState = .synced
                    }
                case .unavailable:
                    if model.cloudSyncState != .pending {
                        model.cloudSyncState = .unavailable
                    }
                }
            }
        )
    }

    private var acceptedFriendshipIDs: Set<FriendshipID> {
        Set(sharedSpaceWindow?.model.friends.map(\.friendshipID) ?? [])
    }

    private func applySyncBootstrap(_ bootstrap: SyncBootstrap) async throws {
        guard bootstrap.account.id == developmentProfile?.accountID else {
            throw BackendClientError.invalidResponse
        }
        if visitProjectionReducer == nil {
            visitProjectionReducer = VisitProjectionReducer(
                accountID: bootstrap.account.id,
                ownPetID: bootstrap.pet.petID
            )
        }
        isPrimaryAgentDevice = bootstrap.isPrimaryAgentDevice
        visitProjectionReducer?.reconcile(bootstrap)
        careSession.replaceCare(bootstrap.ownPetCare, for: .mine)
        familiarities = Dictionary(uniqueKeysWithValues: bootstrap.petFamiliarities.map {
            ($0.friendshipID, $0)
        })
        await reconcileOwnPetAppearance(bootstrap.pet)
        sharedSpaceWindow?.model.ownPetCare = careSession.care(for: .mine)
        publishSituationToAgent(for: .mine)
        for friendship in bootstrap.friendships {
            if let characterID = PetCharacterID(
                appearance: friendship.friend.pet.appearance
            ) {
                sharedSpaceWindow?.model.friendCharacterIDs[
                    friendship.friend.pet.petID
                ] = characterID
            }
            if let publicCare = friendship.friend.pet.publicCare {
                updateFriendCare(
                    friendshipID: friendship.id,
                    publicCare: publicCare,
                    familiarity: friendship.familiarity
                )
            }
        }
        if let visitorPetID = activeIncomingVisit?.visitorPetID,
           let visitorCharacter = sharedSpaceWindow?.model.friendCharacterIDs[visitorPetID] {
            world?.setCharacter(visitorCharacter, for: .partner)
        }
        for conversation in bootstrap.activeConversations {
            await agentCoordinator?.applyConversation(conversation)
        }
        try await applyVisitProjection()
        if sharedSpaceWindow?.model.cloudSyncState != .pending {
            sharedSpaceWindow?.model.cloudSyncState = .synced
        }
    }

    private func reconcileOwnPetAppearance(_ snapshot: PublicPetSnapshot) async {
        guard let model = sharedSpaceWindow?.model else { return }
        if let authoritative = PetCharacterID(appearance: snapshot.appearance) {
            let previous = model.petCharacterSelectionState
            applyOwnPetCharacter(authoritative)
            switch previous {
            case .saving(let selected), .pendingSync(let selected):
                model.petCharacterSelectionState = selected == authoritative
                    ? .confirmed(authoritative)
                    : .conflict(authoritative: authoritative)
            case .failed(let selected?, _):
                model.petCharacterSelectionState = selected == authoritative
                    ? .confirmed(authoritative)
                    : .conflict(authoritative: authoritative)
            case .confirmed, .conflict:
                break
            case .hidden, .required, .failed:
                model.petCharacterSelectionState = .hidden
            }
            return
        }

        if let pending = try? await pendingPetCharacterSelection() {
            applyOwnPetCharacter(pending)
            model.petCharacterSelectionState = .pendingSync(pending)
            model.cloudSyncState = .pending
            return
        }

        if services.configuration.clientProfile == .standard,
           model.authenticationState == .signedIn {
            model.ownPetCharacterID = nil
            model.petCharacterSelectionState = .required()
            world?.setVisiblePet(nil, for: .mine)
        } else {
            applyOwnPetCharacter(runtimeDefaultCharacter)
            model.petCharacterSelectionState = .hidden
        }
    }

    private func pendingPetCharacterSelection() async throws -> PetCharacterID? {
        let mutations = try await services.socialMutationOutbox.due(at: .distantFuture)
        for mutation in mutations.reversed()
        where mutation.kind == .petAppearanceSelection {
            guard case .object(let appearance)? = mutation.body["appearance"],
                  let rigID = appearance["rigID"]?.stringValue,
                  let body = appearance["body"]?.stringValue
            else { continue }
            if let characterID = PetCharacterID(
                appearance: ["rigID": rigID, "body": body]
            ) {
                return characterID
            }
        }
        return nil
    }

    private func handleAccountEvent(_ event: AccountEvent) async throws -> Bool {
        guard event.recipientAccountID == developmentProfile?.accountID else { return true }
        if let timeline = event.timelineEvent() {
            await persistTimelineEvent(timeline)
        }
        guard var reducer = visitProjectionReducer else { return true }
        let result = reducer.apply(event)
        visitProjectionReducer = reducer
        switch result {
        case .duplicate:
            return false
        case .requiresBootstrap:
            return true
        case .applied:
            break
        }

        try await applyVisitProjection()
        switch event.type {
        case "friendship.requested", "friendship.accepted", "friendship.rejected", "friendship.closed":
            try? await refreshFriendDirectory()

        case "visit.requested":
            // Visit invitations are always decided by the human recipient.
            if let visit: Visit = decodePayload(event.payload["visit"]),
               visit.responderAccountID == developmentProfile?.accountID {
                sharedSpaceWindow?.model.visitState = .consideringInvitation
            }

        case "visit.activated":
            break

        case "visit.closed":
            break

        case "visit.action.created":
            // Kept for wire compatibility. New care interactions never wait for
            // another device or an Agent response.
            break

        case "visit.action.replied":
            if let action: VisitAction = decodePayload(event.payload["action"]) {
                applyVisitActionReply(action)
            }

        case "conversation.message.created":
            if isPrimaryAgentDevice,
               let receipt: ConversationTurnReceipt = decodePayload(event.payload) {
                try await handleConversationReceipt(receipt, event: event)
            }

        case "conversation.ended":
            if let summary = event.payload["summary"]?.stringValue {
                sharedSpaceWindow?.model.agentMessage = summary
            }
            if let conversation: PetConversation = decodePayload(event.payload["conversation"]) {
                await agentCoordinator?.setActiveConversationID(nil, for: conversation.friendshipID)
            }

        case "letter.delivered":
            sharedSpaceWindow?.model.agentMessage =
                "\(currentProfile.petName)带回了一封只给你看的信，可在事件线中打开"

        case "pet.care.updated":
            applyCareEvent(event)

        case "pet.appearance.updated":
            if let snapshot: PublicPetSnapshot = decodePayload(
                event.payload["publicPetSnapshot"]
            ), let characterID = PetCharacterID(appearance: snapshot.appearance) {
                if snapshot.petID == currentProfile.petID {
                    applyOwnPetCharacter(characterID)
                    if let model = sharedSpaceWindow?.model {
                        switch model.petCharacterSelectionState {
                        case .saving(let selected), .pendingSync(let selected):
                            model.petCharacterSelectionState =
                            selected == characterID
                            ? .confirmed(characterID)
                            : .conflict(authoritative: characterID)
                        default:
                            break
                        }
                    }
                } else {
                    sharedSpaceWindow?.model.friendCharacterIDs[snapshot.petID] = characterID
                    if activeIncomingVisit?.visitorPetID == snapshot.petID {
                        world?.setCharacter(characterID, for: .partner)
                    }
                }
            }

        case "agent.primary.changed":
            return true

        default:
            break
        }
        return false
    }

    private func applyCareEvent(_ event: AccountEvent) {
        guard let petID = event.payload["petID"]?.stringValue,
              let publicCare: PublicPetCareSummary = decodePayload(event.payload["publicCare"])
        else { return }
        let careState: PetCareState? = decodePayload(event.payload["careState"])
        let familiarity: PetFamiliarity? = decodePayload(event.payload["familiarity"])
        if petID == currentProfile.petID.rawValue, let careState {
            careSession.replaceCare(careState, for: .mine)
            sharedSpaceWindow?.model.ownPetCare = careSession.care(for: .mine)
            publishSituationToAgent(for: .mine)
        } else if activeIncomingVisit?.visitorPetID.rawValue == petID {
            careSession.replaceCare(
                PetCareSession.care(from: publicCare, at: event.occurredAt),
                for: .partner
            )
        }
        if let familiarity {
            familiarities[familiarity.friendshipID] = familiarity
            updateFriendCare(
                friendshipID: familiarity.friendshipID,
                publicCare: publicCare,
                familiarity: familiarity
            )
        }
        sharedSpaceWindow?.model.cloudSyncState = .synced
    }

    private func applyVisitProjection() async throws {
        guard let projection = visitProjectionReducer?.projection else { return }
        let previousIncomingVisit = activeIncomingVisit
        let previousOutgoingVisit = activeOutgoingVisit
        activeIncomingVisit = projection.activeIncomingVisit
        activeOutgoingVisit = projection.activeOutgoingVisit
        pendingVisits = projection.pendingVisits
        refreshVisitInvitationQueue()

        let liveActiveVisitIDs = Set(
            [projection.activeIncomingVisit?.id, projection.activeOutgoingVisit?.id]
                .compactMap { $0 }
        )
        optimisticallyReturningVisitIDs.formIntersection(liveActiveVisitIDs)

        for visit in projection.pendingVisits.values {
            await socialVisitCoordinator?.apply(visit)
        }
        if let visit = projection.activeIncomingVisit {
            await socialVisitCoordinator?.apply(visit)
            await agentCoordinator?.applyVisit(visit)
        }
        if let visit = projection.activeOutgoingVisit {
            await socialVisitCoordinator?.apply(visit)
            await agentCoordinator?.applyVisit(visit)
        }

        if let outgoing = projection.activeOutgoingVisit {
            if optimisticallyReturningVisitIDs.contains(outgoing.id) {
                ensureLocalPetVisible()
            } else if previousOutgoingVisit?.id != outgoing.id, world?.pets[.mine] != nil {
                animateOwnPetLeavingForVisit()
            } else if previousOutgoingVisit?.id == outgoing.id,
                      departingOwnPetVisitID != outgoing.id {
                world?.setVisiblePet(nil, for: .mine)
            }
        } else if previousOutgoingVisit != nil {
            animateOwnPetReturningHome()
        } else {
            ensureLocalPetVisible()
        }

        if let incoming = projection.activeIncomingVisit {
            sharedSpaceWindow?.model.activeVisitFriendshipID = incoming.friendshipID
            if optimisticallyReturningVisitIDs.contains(incoming.id) {
                world?.setVisiblePet(nil, for: .partner)
                sharedSpaceWindow?.model.visitState = .returning
            } else {
                announceVisitArrival()
                sharedSpaceWindow?.model.visitState = .visiting
            }
        } else {
            if previousIncomingVisit != nil,
               announcedIncomingVisitID != nil,
               world?.pets[.partner] != nil {
                await animateVisitDeparture(for: .partner)
            }
            if activeIncomingVisit == nil {
                world?.setVisiblePet(nil, for: .partner)
                announcedIncomingVisitID = nil
            }
            if let outgoing = projection.activeOutgoingVisit {
                sharedSpaceWindow?.model.activeVisitFriendshipID = outgoing.friendshipID
                sharedSpaceWindow?.model.visitState =
                    optimisticallyReturningVisitIDs.contains(outgoing.id)
                    ? .returning
                    : .ownPetVisiting
            } else if let pending = projection.pendingVisits.values.sorted(by: {
                $0.createdAt < $1.createdAt
            }).first {
                sharedSpaceWindow?.model.activeVisitFriendshipID = pending.friendshipID
                sharedSpaceWindow?.model.visitState =
                    pending.responderAccountID == projection.accountID
                    ? .consideringInvitation
                    : .invitationSent
            } else {
                sharedSpaceWindow?.model.activeVisitFriendshipID = nil
                sharedSpaceWindow?.model.visitState = .away
            }
        }
    }

    private func handleUnresolvedVisitAction(_ action: VisitAction) async throws {
        guard isPrimaryAgentDevice,
              action.requiresResponse,
              let agentCoordinator,
              activeOutgoingVisit?.id == action.visitID
        else { return }
        let stimulus: PetInteractionStimulus = switch action.kind {
        case .feed:
            .feeding(foodName: action.payload["food"]?.stringValue)
        case .message, .speech:
            .message(text: action.payload["text"]?.stringValue ?? "主人和你说了句话")
        case .play, .pet, .hug, .kiss, .flower, .walk, .reaction, .activity, .acknowledgement:
            .play
        }
        try await agentCoordinator.observeEvent(
            AgentObservation(
                id: action.id,
                occurredAt: action.createdAt,
                kind: .visitInteraction(
                    visitID: action.visitID,
                    actorAccountID: action.senderAccountID,
                    stimulus: stimulus
                )
            )
        )
    }

    private func applyVisitActionReply(_ action: VisitAction) {
        let reaction = action.payload["reaction"]?.stringValue.flatMap(PetReaction.init(rawValue:))
        let remainsSleepy = reaction == .sleepy || reaction == .resting
        world?.setWaitingForRemoteAgent(.partner, isWaiting: remainsSleepy)
        switch reaction {
        case .happy: world?.setPetEmotion(.partner, emotion: .happy)
        case .excited: world?.setPetEmotion(.partner, emotion: .excited)
        case .grateful: world?.setPetEmotion(.partner, emotion: .grateful)
        case .playful: world?.setPetEmotion(.partner, emotion: .playful)
        case .shy: world?.setPetEmotion(.partner, emotion: .shy)
        case .sleepy, .resting: world?.setPetEmotion(.partner, emotion: .sleepy)
        case nil: break
        }
        sharedSpaceWindow?.model.agentMessage = action.payload["text"]?.stringValue
            ?? (remainsSleepy ? "来访宠物安心地睡着了" : "来访宠物回应了你的互动")
    }

    private func handleConversationReceipt(
        _ receipt: ConversationTurnReceipt,
        event: AccountEvent
    ) async throws {
        guard let profile = developmentProfile,
              receipt.message.senderAccountID != profile.accountID,
              let agentCoordinator
        else { return }
        let message = receipt.message
        let observation: AgentObservation
        switch message.actorType {
        case .human:
            observation = AgentObservation(
                id: UUID(uuidString: message.id.rawValue) ?? UUID(),
                occurredAt: message.createdAt,
                kind: .remoteHumanMessage(
                    senderAccountID: message.senderAccountID,
                    text: message.body
                )
            )
        case .petAgent:
            guard let friendPetID = sharedSpaceWindow?.model.friends.first(where: {
                $0.accountID == message.senderAccountID
            })?.petID else { return }
            observation = AgentObservation(
                id: UUID(uuidString: message.id.rawValue) ?? UUID(),
                occurredAt: message.createdAt,
                kind: .petMessage(senderPetID: friendPetID, text: message.body)
            )
        case .system:
            return
        }
        await agentCoordinator.applyConversation(receipt.conversation)
        await agentCoordinator.recordConversationMessage(
            conversationID: receipt.conversation.id,
            actorType: message.actorType,
            actorID: message.senderAccountID.rawValue,
            recipientPetID: profile.petID,
            turnIndex: message.turnIndex,
            text: message.body
        )
        if message.actorType == .petAgent, (message.turnIndex ?? -1) >= 5 {
            try await agentCoordinator.finishConversation(
                friendshipID: receipt.conversation.friendshipID,
                conversationID: receipt.conversation.id,
                occurredAt: event.occurredAt
            )
        } else {
            try await agentCoordinator.observeEvent(observation)
        }
    }

    private func decodePayload<Value: Decodable>(_ value: JSONValue?) -> Value? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(Value.self, from: data)
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
        let mutationOutbox = services.socialMutationOutbox
        let personalTimelineStore = services.personalTimelineStore
        localStateBootstrapTask = Task {
            do {
                async let credential = sessionStore.load()
                async let pendingMutations = mutationOutbox.due(at: .distantFuture)
                async let timeline = personalTimelineStore.load()
                let state = try await (credential, pendingMutations, timeline)
                self.sharedSpaceWindow?.model.timelineEvents = state.2
                if state.0 != nil,
                   let pendingCharacter = state.1.reversed().lazy.compactMap({
                       self.petCharacterID(from: $0)
                   }).first {
                    self.applyOwnPetCharacter(pendingCharacter)
                    self.sharedSpaceWindow?.model.petCharacterSelectionState =
                        .pendingSync(pendingCharacter)
                    self.sharedSpaceWindow?.model.cloudSyncState = .pending
                }
                if let friendshipID = self.sharedSpaceWindow?.model.selectedFriendshipID {
                    self.loadFriendTimeline(friendshipID)
                }
                MinoLog.lifecycle.info(
                    "Local state ready; signed in: \(state.0 != nil), pending social mutations: \(state.1.count)"
                )
            } catch {
                MinoLog.lifecycle.error(
                    "Local state bootstrap failed without deleting data: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func petCharacterID(from mutation: SocialMutation) -> PetCharacterID? {
        guard mutation.kind == .petAppearanceSelection,
              case .object(let appearance)? = mutation.body["appearance"],
              let rigID = appearance["rigID"]?.stringValue,
              let body = appearance["body"]?.stringValue
        else { return nil }
        return PetCharacterID(appearance: ["rigID": rigID, "body": body])
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
