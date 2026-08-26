import MinoDomain
import SwiftUI

struct FriendDetailView: View {
    let friend: FriendProfile?
    let events: [PersonalTimelineEvent]
    let identity: SharedSpaceIdentity
    let isLoading: Bool
    let errorMessage: String?
    let visitState: FriendVisitState
    let activeVisitFriendshipID: FriendshipID?
    let operationInProgress: Bool
    let characterID: PetCharacterID
    let perform: (FriendDirectoryAction) -> Void
    let onOpenLetter: (LetterID) -> Void
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let friend {
                FeatureHeader(title: friend.petName, subtitle: "\(friend.accountName) · 自 \(friend.friendsSince.formatted(date: .abbreviated, time: .omitted)) 成为好友") {
                    HStack(spacing: 10) {
                        Button {
                            back()
                        } label: {
                            Label("返回好友", systemImage: "chevron.left")
                        }
                        .buttonStyle(MinoTextButtonStyle())

                        if isActiveVisitFriend && visitState == .consideringInvitation {
                            Button("拒绝") {
                                perform(.respondToVisit(.decline))
                            }
                            .buttonStyle(MinoTextButtonStyle())
                            .disabled(operationInProgress)

                            Button("接受") {
                                perform(.respondToVisit(.accept))
                            }
                            .buttonStyle(MinoCompactButtonStyle())
                            .disabled(operationInProgress)
                        } else {
                            if isActiveVisitFriend,
                               visitState == .visiting || visitState == .ownPetVisiting {
                                Button {
                                    perform(.endVisit)
                                } label: {
                                    Label("结束串门", systemImage: "house.fill")
                                }
                                .buttonStyle(MinoCompactButtonStyle())
                                .disabled(operationInProgress)
                            } else {
                                Menu {
                                    Button("邀请 \(friend.petName) 来我桌面") {
                                        perform(.inviteFriendPet(friend.friendshipID))
                                    }
                                    Button("让我的 Mino 去 \(friend.accountName) 家") {
                                        perform(.sendOwnPet(friend.friendshipID))
                                    }
                                } label: {
                                    Label("串门", systemImage: "paperplane.fill")
                                }
                                .menuStyle(.borderlessButton)
                                .disabled(operationInProgress || visitDisabled)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.minoCoral)
                        .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                        .padding(.horizontal, MinoDesign.Spacing.xxxl)
                }

                HStack(alignment: .center, spacing: MinoDesign.Spacing.md) {
                    ReadOnlyPetCharacterCard(
                        characterID: characterID,
                        petName: friend.petName,
                        detail: "\(friend.accountName) 的 Mino · 角色由好友永久选定",
                        characterSize: 76
                    )
                    .frame(maxWidth: 310)
                    FriendPublicCareSummary(friend: friend)
                }
                .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                .padding(.horizontal, MinoDesign.Spacing.xxxl)
                .padding(.bottom, MinoDesign.Spacing.md)

                if isLoading && events.isEmpty {
                    ProgressView("正在同步事件")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty {
                    VStack(spacing: MinoDesign.Spacing.sm) {
                        PetCharacterPairView(size: 70)
                        Text("还没有共享事件")
                            .font(MinoDesign.Typography.sectionTitle)
                            .foregroundStyle(Color.minoInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                                TimelineEventRow(
                                    event: event,
                                    friend: friend,
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
            } else {
                Text("请选择一位好友")
                    .foregroundStyle(Color.minoMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.minoCanvas)
    }

    private var isActiveVisitFriend: Bool {
        friend?.friendshipID == activeVisitFriendshipID
    }

    private var visitDisabled: Bool {
        friend == nil || (visitState != .away && !isActiveVisitFriend)
    }

    private var visitTitle: String {
        guard isActiveVisitFriend else { return "邀请串门" }
        return switch visitState {
        case .visiting, .ownPetVisiting: "结束串门"
        case .sendingInvitation: "正在发送"
        case .invitationSent, .consideringInvitation: "等待回应"
        case .returning: "正在回家"
        case .away: "邀请串门"
        }
    }

    private var visitSymbol: String {
        isActiveVisitFriend && (visitState == .visiting || visitState == .ownPetVisiting)
            ? "house.fill"
            : "paperplane.fill"
    }
}

struct FriendPublicCareSummary: View {
    let friend: FriendProfile

    var body: some View {
        HStack(spacing: MinoDesign.Spacing.sm) {
            qualitativePill(symbol: "fork.knife", text: fullnessText)
            qualitativePill(symbol: "bolt.fill", text: energyText)
            qualitativePill(symbol: "face.smiling.fill", text: moodText)
            Spacer()
            Label(friend.familiarity?.tier.displayName ?? "初见", systemImage: "heart.circle.fill")
                .font(MinoDesign.Typography.caption.weight(.semibold))
                .foregroundStyle(Color.minoCoral)
        }
        .padding(.horizontal, MinoDesign.Spacing.md)
        .frame(minHeight: 54)
        .background(Color.minoSurface, in: RoundedRectangle(
            cornerRadius: MinoDesign.Radius.card,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func qualitativePill(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(MinoDesign.Typography.caption)
            .foregroundStyle(Color.minoMuted)
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: 30)
            .background(Color.minoCanvas, in: Capsule())
    }

    private var fullnessText: String {
        switch friend.publicCare?.fullness ?? .steady {
        case .low: "有点饿"
        case .steady: "吃得正好"
        case .high: "肚子饱饱"
        }
    }

    private var energyText: String {
        switch friend.publicCare?.energy ?? .steady {
        case .low: "有点累"
        case .steady: "精神还好"
        case .high: "精神很好"
        }
    }

    private var moodText: String {
        switch friend.publicCare?.mood ?? .steady {
        case .low: "有点低落"
        case .steady: "心情平稳"
        case .high: "心情很好"
        }
    }
}

