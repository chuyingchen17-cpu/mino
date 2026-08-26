import MinoDomain
import SwiftUI

struct TimelineFoundationView: View {
    let events: [PersonalTimelineEvent]
    let friends: [FriendProfile]
    let identity: SharedSpaceIdentity
    let authenticationState: SharedSpaceAuthenticationState
    let cloudSyncState: CloudSyncState
    let onOpenLetter: (LetterID) -> Void
    let openFriends: () -> Void
    let openProfile: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(
                title: "个人事件线",
                subtitle: "每次串门结束后，互动和带回的小心意会汇成一条摘要"
            )
            switch authenticationState {
            case .signedOut:
                SocialEmptyState(
                    symbol: "person.crop.circle.badge.plus",
                    title: "登录后查看事件线",
                    detail: "登录后，串门结束时生成的互动摘要会保存在这里。",
                    actionTitle: "前往个人页",
                    action: openProfile
                )
            case .waitingForGitHub:
                SocialEmptyState(
                    symbol: "key.fill",
                    title: "正在完成 GitHub 登录",
                    detail: "完成授权后，Mino 会自动恢复你的事件线。",
                    actionTitle: "查看登录进度",
                    action: openProfile
                )
            case .offline, .signedIn:
                timelineContent
            }
        }
        .background(Color.minoCanvas)
    }

    @ViewBuilder
    private var timelineContent: some View {
        if authenticationState == .signedIn, cloudSyncState == .connecting, events.isEmpty {
            SocialLoadingState(title: "正在恢复事件线")
        } else if authenticationState == .signedIn, cloudSyncState == .unavailable, events.isEmpty {
            SocialEmptyState(
                symbol: "wifi.slash",
                title: "暂时无法载入事件线",
                detail: "云端连接暂时不可用，已有记录不会丢失。",
                actionTitle: "重新连接",
                action: retry
            )
        } else if events.isEmpty {
            SocialEmptyState(
                symbol: "clock.arrow.circlepath",
                title: "还没有串门记录",
                detail: friends.isEmpty
                    ? "添加好友并完成一次串门后，这里会留下互动摘要。"
                    : "邀请好友的 Mino 串门，结束后这里会留下互动摘要。",
                actionTitle: authenticationState == .signedIn
                    ? (friends.isEmpty ? "去添加好友" : "发起串门")
                    : nil,
                action: authenticationState == .signedIn ? openFriends : nil
            )
        } else {
            VStack(spacing: 0) {
                if authenticationState == .signedIn,
                   cloudSyncState == .connecting || cloudSyncState == .pending || cloudSyncState == .unavailable {
                    CloudSyncNotice(
                        state: cloudSyncState,
                        hasCachedContent: true,
                        retry: retry
                    )
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            TimelineEventRow(
                                event: event,
                                friend: friend(for: event),
                                identity: identity,
                                onOpenLetter: onOpenLetter,
                                continuesBelow: index < events.count - 1
                            )
                        }
                    }
                    .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                    .padding(.horizontal, MinoDesign.Spacing.xxxl)
                    .padding(.bottom, MinoDesign.Spacing.xxxl)
                }
            }
        }
    }

    private func friend(for event: PersonalTimelineEvent) -> FriendProfile? {
        guard let friendshipID = event.friendshipID else { return nil }
        return friends.first { $0.friendshipID == friendshipID }
    }
}

struct TimelineEventRow: View {
    let event: PersonalTimelineEvent
    let friend: FriendProfile?
    let identity: SharedSpaceIdentity
    let onOpenLetter: (LetterID) -> Void
    let continuesBelow: Bool

    var body: some View {
        HStack(alignment: .top, spacing: MinoDesign.Spacing.md) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: MinoDesign.Size.iconSmall, weight: .bold))
                    .foregroundStyle(Color.minoCoral)
                    .frame(width: 38, height: 38)
                    .background(Color.minoCoralSoft, in: Circle())

                if continuesBelow {
                    Rectangle()
                        .fill(Color.minoLine)
                        .frame(width: 1)
                        .frame(minHeight: 64)
                }
            }

            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(MinoDesign.Typography.sectionTitle)
                        .foregroundStyle(Color.minoInk)
                    Spacer()
                    Label(friendPetName, systemImage: "person.crop.circle")
                        .font(MinoDesign.Typography.caption.weight(.medium))
                        .foregroundStyle(Color.minoMuted)
                        .lineLimit(1)
                }

                Text(detail)
                    .font(MinoDesign.Typography.body)
                    .foregroundStyle(Color.minoMuted)

                if let letterID = event.letterID {
                    Button("打开信件") {
                        onOpenLetter(letterID)
                    }
                    .buttonStyle(MinoTextButtonStyle())
                }

                if !event.cargoItems.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(event.cargoItems, id: \.itemID) { item in
                            Label(
                                item.quantity > 1 ? "\(item.displayName) ×\(item.quantity)" : item.displayName,
                                systemImage: "shippingbox.fill"
                            )
                            .font(MinoDesign.Typography.caption.weight(.semibold))
                            .foregroundStyle(Color.minoInk)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.minoCoralSoft, in: Capsule())
                        }
                    }
                }

                if let postcard = event.postcard {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color.minoCoral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(postcard.title)
                                .font(MinoDesign.Typography.label)
                                .foregroundStyle(Color.minoInk)
                            if let message = postcard.message {
                                Text(message)
                                    .font(MinoDesign.Typography.caption)
                                    .foregroundStyle(Color.minoMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.minoSurface, in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                            .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
                    }
                }
            }
            .padding(.bottom, continuesBelow ? MinoDesign.Spacing.lg : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch event.kind {
        case .visitInvited:
            event.actorAccountID == friend?.accountID
                ? "\(friendPetName)发来串门提议"
                : "向\(friendPetName)发起串门提议"
        case .visitArrived: "\(subjectPetName)过来玩了"
        case .visitReturned: "\(subjectPetName)回家了"
        case .invitationDeclined: "这次串门提议被婉拒了"
        case .interaction: "发生了一次互动"
        case .visitInteraction:
            switch event.visitInteractionKind {
            case .feed: "\(subjectPetName)被投喂了"
            case .play: "\(subjectPetName)和主人玩了一会儿"
            case .message: "主人给\(subjectPetName)留了句话"
            case .pet: "\(subjectPetName)被轻轻摸了摸"
            case .hug: "\(subjectPetName)收到了一个拥抱"
            case .kiss: "\(subjectPetName)被亲了一下"
            case .flower: "\(subjectPetName)收到了一朵花"
            case .walk: "\(subjectPetName)出去散了会儿步"
            case .reaction, .activity, .speech, .acknowledgement: "来访宠物回应了互动"
            case nil: "串门时发生了一次互动"
            }
        case .conversationSummary: "两只小家伙聊了聊天"
        case .letterReceived: "宠物带回了一封信"
        case .cargoReceived: "好友宠物带来了东西"
        case .postcardReceived: "收到一张明信片"
        }
    }

    private var detail: String {
        switch event.kind {
        case .visitInvited: "串门邀请已经送达，等待好友明确接受或拒绝。"
        case .visitArrived: "\(subjectPetName)来到桌面，开始这次来访。"
        case .visitReturned:
            visitSummaryText
                ?? "这次来访结束了，\(subjectPetName)已经回到自己的家。"
        case .invitationDeclined: "邀请仍然留作记录，下次再约也可以。"
        case .interaction:
            switch event.interactionKind {
            case .kiss: "\(identity.localPetName)和\(friendPetName)贴贴了一下。"
            case .flowerGift: "一朵小花被送到了\(friendPetName)身边。"
            case .walk: "\(identity.localPetName)和\(friendPetName)一起散了会儿步。"
            case nil: "\(identity.localPetName)和\(friendPetName)留下了一个小瞬间。"
            }
        case .visitInteraction:
            switch event.visitInteractionKind {
            case .feed: "接待主人给来访的小家伙准备了食物。"
            case .play: "来访的小家伙被好好陪着玩了一会儿。"
            case .message: "一句话已经交给来访的小家伙。"
            case .pet: "接待主人轻轻摸了摸来访的小家伙。"
            case .hug: "接待主人抱了抱来访的小家伙。"
            case .kiss: "接待主人亲了亲来访的小家伙。"
            case .flower: "接待主人送给来访的小家伙一朵花。"
            case .walk: "来访的小家伙出去散了会儿步。"
            case .reaction, .activity, .speech, .acknowledgement: "来访宠物回应了这次互动。"
            case nil: "串门期间留下了一个小瞬间。"
            }
        case .conversationSummary:
            event.summary ?? "它们悄悄联络了一下感情。"
        case .letterReceived: "信封完好地随宠物回到了家，正文只对收件人可见。"
        case .cargoReceived: "来访时携带的小东西已经收好。"
        case .postcardReceived: "一段值得留下来的远方记忆。"
        }
    }

    private var friendPetName: String {
        friend?.petName ?? "好友宠物"
    }

    private var visitSummaryText: String? {
        guard let summary = event.visitInteractionSummary, !summary.isEmpty else { return nil }
        let names: [PetCareInteractionKind: String] = [
            .pet: "摸摸", .feed: "投喂", .play: "陪玩", .walk: "散步",
            .rest: "休息", .cuddle: "贴贴", .flower: "送花"
        ]
        let actions = PetCareInteractionKind.allCases.compactMap { kind -> String? in
            guard let count = summary.counts[kind], count > 0 else { return nil }
            return "\(names[kind] ?? kind.rawValue) \(count) 次"
        }.joined(separator: "、")
        var parts: [String] = []
        if !actions.isEmpty { parts.append(actions) }
        if summary.familiarityGained > 0 {
            parts.append("熟悉度 +\(summary.familiarityGained)")
        }
        if summary.letterAttached { parts.append("带回一封文字信") }
        return "这次串门留下了：\(parts.joined(separator: "，"))。"
    }

    private var subjectPetName: String {
        guard let petID = event.petID else { return friendPetName }
        return petID == friend?.petID ? friendPetName : identity.localPetName
    }

    private var symbol: String {
        switch event.kind {
        case .visitInvited: "paperplane.fill"
        case .visitArrived: "sparkles"
        case .visitReturned: "house.fill"
        case .invitationDeclined: "moon.zzz.fill"
        case .interaction: "heart.fill"
        case .visitInteraction: "pawprint.fill"
        case .conversationSummary: "bubble.left.and.bubble.right.fill"
        case .letterReceived: "envelope.fill"
        case .cargoReceived: "shippingbox.fill"
        case .postcardReceived: "photo.fill"
        }
    }

}

