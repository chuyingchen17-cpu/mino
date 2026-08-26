import Foundation
import MinoDomain

public struct DeterministicInteractionResponseProvider: InteractionResponseProvider {
    public init() {}

    public func response(for context: PetReactionContext) async -> PetReactionPlan {
        let familiar = context.familiarityTier == .familiar || context.familiarityTier == .close

        switch context.outcome {
        case .tooFull:
            return plan(
                for: context,
                options: ["肚子已经圆圆的啦。", "先收下心意，下次再吃。"],
                activity: .petting,
                emotion: .content
            )
        case .tooTired:
            return tiredPlan(for: context)
        case .restingCooldown:
            return plan(
                for: context,
                options: ["刚刚才休息过，我先醒醒神。", "精神已经补过啦，晚点再眯一会儿。"],
                activity: .sleeping,
                emotion: .content
            )
        case .cosmeticOnly:
            return repeatedPlan(for: context, familiar: familiar)
        case .applied:
            break
        }

        let options: [String]
        let activity: PetActivity
        let emotion: PetEmotion
        let effect: PetReactionEffect
        switch context.kind {
        case .pet:
            options = context.recentRepeatCount >= 3
                ? ["知道啦，今天特别黏人。", "还要摸摸呀？那再靠近一点。"]
                : ["摸摸收到啦。", "嗯，就这样再待一会儿。", "我在呢。"]
            activity = .petting
            emotion = .happy
            effect = .none
        case .feed:
            options = ["好吃，认真收下啦。", "这一口刚刚好。", "闻起来就很香。"]
            activity = .eating
            emotion = .grateful
            effect = .none
        case .play:
            options = familiar
                ? ["我就知道你会来找我玩。", "这次也要玩个尽兴。"]
                : ["来啦，一起动一动。", "好呀，准备好了吗？"]
            activity = .playing
            emotion = .playful
            effect = .none
        case .walk:
            options = ["出发，去看看桌面另一边。", "一起走走，吹吹风。"]
            activity = .walking
            emotion = .excited
            effect = .none
        case .rest:
            options = ["我眯一会儿，你也休息一下。", "晚点再一起玩。"]
            activity = .sleeping
            emotion = .sleepy
            effect = .none
        case .cuddle:
            options = familiar
                ? ["靠近一点也没关系。", "熟悉的感觉，真安心。"]
                : ["慢一点，我有一点害羞。", "第一次贴贴，记住你啦。"]
            activity = .celebrating
            emotion = familiar ? .happy : .shy
            effect = .heart
        case .flower:
            options = ["这朵花，我会好好收着。", "谢谢你，今天也变好看了。"]
            activity = .offeringGift
            emotion = .grateful
            effect = .flower
        }

        return plan(
            for: context,
            options: options,
            activity: activity,
            emotion: emotion,
            effect: effect
        )
    }

    private func tiredPlan(for context: PetReactionContext) -> PetReactionPlan {
        switch context.kind {
        case .walk:
            plan(
                for: context,
                options: ["脚步有点慢，今天先看会儿风景。", "等我恢复精神再走远一点。"],
                activity: .sleeping,
                emotion: .sleepy
            )
        default:
            plan(
                for: context,
                options: ["今天先玩轻一点，好不好？", "有点累了，陪我歇一会儿吧。"],
                activity: .sleeping,
                emotion: .sleepy
            )
        }
    }

    private func repeatedPlan(
        for context: PetReactionContext,
        familiar: Bool
    ) -> PetReactionPlan {
        switch context.kind {
        case .pet:
            plan(
                for: context,
                options: ["知道啦，今天特别黏人。", "还要摸摸呀？那再靠近一点。"],
                activity: .petting,
                emotion: .happy
            )
        case .feed:
            plan(
                for: context,
                options: ["这一份心意也收到啦。", "先慢慢吃，别担心我饿着。"],
                activity: .eating,
                emotion: .content
            )
        case .play:
            plan(
                for: context,
                options: ["还要再来一局呀？", "好啦，再陪你玩一下。"],
                activity: .playing,
                emotion: .playful
            )
        case .walk:
            plan(
                for: context,
                options: ["又要出发啦，那就再走一小圈。", "今天的散步安排得满满的。"],
                activity: .walking,
                emotion: .excited
            )
        case .rest:
            plan(
                for: context,
                options: ["正在休息呢，嘘。", "让我再眯一小会儿。"],
                activity: .sleeping,
                emotion: .sleepy
            )
        case .cuddle:
            plan(
                for: context,
                options: familiar
                    ? ["再靠近一点也可以。", "今天收到好多贴贴。"]
                    : ["我还在慢慢记住你。", "再贴一下就更熟悉啦。"],
                activity: .celebrating,
                emotion: familiar ? .happy : .shy,
                effect: .heart
            )
        case .flower:
            plan(
                for: context,
                options: ["又是一朵花，谢谢你。", "今天的花束越来越香啦。"],
                activity: .offeringGift,
                emotion: .grateful,
                effect: .flower
            )
        }
    }

    private func plan(
        for context: PetReactionContext,
        options: [String],
        activity: PetActivity,
        emotion: PetEmotion,
        effect: PetReactionEffect = .none
    ) -> PetReactionPlan {
        PetReactionPlan(
            speech: options[stableIndex(context.interactionID, count: options.count)],
            activity: activity,
            emotion: emotion,
            motionClip: PetMotionResolver.resolve(
                activity: activity,
                emotion: emotion,
                interaction: context.kind,
                outcome: context.outcome,
                role: .receiver
            ),
            effect: effect
        )
    }

    private func stableIndex(_ id: UUID, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var uuid = id.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0) }
        let folded = bytes.enumerated().reduce(0) { partial, item in
            (partial &* 31) &+ Int(item.element) &+ item.offset
        }
        return abs(folded == .min ? 0 : folded) % count
    }
}
