# Mino 架构

## 系统边界

每个 Account 拥有一个 Pet，并可有多个 Device。服务端是身份、好友授权、养成状态、熟悉度、Visit、信件和事件的事实来源，但不是宠物大脑。标准互动由任意客户端本地立即完成，不依赖 Primary Agent、好友设备在线或模型。

```text
┌──────────────── macOS Client ────────────────┐
│ App / VisitProjection / AccountEventSync     │
│ Deterministic response + optimistic care     │
│ Durable outbox, motion and animation         │
└────────────── HTTPS + WSS ───────────────────┘
                         │
┌──────────────── Cloudflare Worker ───────────┐
│ Hono REST + auth + strict validation         │
│ Application commands and D1 repositories     │
│ Optional model proxy (outside base path)     │
├───────────────────┬──────────────────────────┤
│ D1                │ AccountRealtimeHub DO    │
│ durable facts     │ one instance / Account   │
│ events + receipts │ ready/events_available   │
└───────────────────┴──────────────────────────┘
```

不再存在常驻 Node 服务、进程内业务 WebSocket hub、PostgreSQL 或 Redis。Durable Object 不保存业务状态；其丢失、休眠或通知失败只影响延迟。

## Worker 请求路径

```text
Bearer token
   │ hash + session/device expiry/revocation check
   ▼
AuthContext(accountID, deviceID, petID, isPrimaryAgentDevice)
   │
   ├─ strict request schema + 64 KiB body limit
   ├─ friendship/resource ownership authorization
   └─ idempotency lookup(account, operation, key, fingerprint)
          │ miss
          ▼
      D1 atomic batch
      ├─ conditional aggregate transition
      ├─ recipient A event copy
      ├─ recipient B event copy
      └─ idempotency receipt
          │ commit
          ▼
      best-effort notify AccountRealtimeHub for each recipient
```

业务表用 `version` 与 `last_transition_id` 保护 conditional write。事件与回执使用同一 marker 的 `INSERT … SELECT`，因此竞争失败的 transition 不会留下幽灵事件或成功回执。D1 `account_events.sequence` 是全库单调整数，但客户端只读取 `recipient_account_id = 当前账号` 的独立事件副本。

## Durable Object 实时层

Worker 使用 `ACCOUNT_REALTIME.idFromName(accountID)`，所以一个账号无论有多少设备，都映射到一个 `AccountRealtimeHub`。外部请求不能提交 account/device identity；Worker 在 Bearer 鉴权后移除伪造 header，再向 DO 写入可信 `x-mino-device-id`。

DO 通过 Hibernation API `acceptWebSocket` 接受连接，发送：

- `ready`：连接已由服务端认证并接管；
- `events_available`：D1 可能存在新事件。

客户端发送业务消息会以 policy violation 关闭。断开的 socket 由 Hibernation API 的集合清理；通知单个 socket 失败不会影响其他设备或业务 commit。

仓库按产品边界分成两个 mise config root：`apps/macos` 是 SwiftPM 客户端，`apps/worker` 是 Cloudflare Worker。仓库根的 `mise.toml` 声明 `monorepo_root` 与 `config_roots = ["apps/*"]`。

## Swift 模块

```text
MinoApp
├── MinoAgent ─────────────┐
├── MinoRuntime            │
├── MinoPresentation       ├── MinoDomain
├── MinoInfrastructure ────┤
├── MinoPersistence ───────┤
└── MinoSecurity ──────────┘
```

- `MinoDomain`：Account、Friendship、Visit、PetCareState、PetFamiliarity、interaction command/receipt、`PetCharacterID`、`PetRigManifest`、`PetMotionClipID`、AccountEvent 与 reducer/projection。
- `MinoInfrastructure`：Worker REST DTO、token refresh、单账号 WebSocket signal client。
- `MinoPersistence`：按 Account 保存事件 cursor、个人 timeline、社交 mutation outbox。
- `MinoApp`：先用 `InteractionResponseProvider` 播放基础反馈，再由 `VisitCoordinator` 通过持久 outbox 发送养成命令；`AccountEventSyncCoordinator` 串行 bootstrap/catch-up/realtime 并静默校正。`PetCareSession` 是养成数值、主人上下文和乐观 generation 的唯一内存来源；AppDelegate 只决定许可、播反应和发网络。
- `MinoRuntime`：只消费 `VisitProjection` 的可见状态和 `PetCharacterID`，不直接调用社交后端；活动移动期间由 display-paced driver 推进世界坐标。双宠交互动画由 `PairedPetChoreography` 描述，`PetWorld` 按 giver/receiver 槽位播放，不按动作名写死会话类型。
- `MinoPresentation`：用同一固定画布帧目录向 SpriteKit 桌宠和 SwiftUI 页面提供透明 PNG、帧时序、Reduce Motion 静态帧与统一采样策略。社交窗是 SwiftUI：`SharedSpaceModel` 为 `@Observable` 展示 store，页面切换是 View 本地 `@State`，屏幕按好友 / 事件线 / 详情 / 个人页拆文件。View 通过 action 闭包把意图交给 AppDelegate，不在 `body` 里改账号事实。

### 客户端会话与可见情境

后续 Agent 智能、主人状态（如正在听音乐）和双宠交互动画都读同一份可见情境，而不是在 AppDelegate 上堆布尔值：

```text
OwnerContext + PetCareState + companionPresent
                 │
                 ▼
            PetSituation
        ┌────┴────┐
        ▼         ▼
 PetCareSession  AgentPetState.applyVisibleSituation
        │
        ▼
 PetReactionContext → Deterministic plan / 日后模型增强
        │
        ▼
 PairedPetChoreography → PetWorld giver/receiver
```

主人媒体检测、新的双宠 clip、模型对情境的使用都可以在这些类型上增长。不要把 `isListening` / `isPlayingTogether` 加进 AppDelegate。

## 角色与动作子系统

```text
PetRuntimeState / interaction result / visit phase
                         │
                         ▼
                PetMotionResolver
                         │ one semantic clip
                         ▼
PetCharacterID ── PetMotionClipID ── PetFrameAnimationCatalog
                                      │
                         PetFrameAnimation manifest
                         frames / timing / loop / static index
                                      │
                         ┌────────────┴────────────┐
                         ▼                         ▼
                 SpriteKit desktop          PetCharacterView
                 SKSpriteNode frames         same PNG frames
```

`PetCharacterID` 只包含 `malteseWhite` 与 `retrieverYellow`，wire body 分别为 `maltese-white` 与 `retriever-yellow`。两者共用 `maltese-pair-v1` 的 `120 × 120` 固定画布和 `(60, 102)` 脚底锚点。旧 `AvatarRecipe` 仅在解析已有本地状态时映射角色；它不再决定新界面或桌宠渲染。

帧目录固定为 `Resources/PetFrames/<character.rawValue>/<clip.rawValue>/frame-NNN.png`。`PetFrameAnimationCatalog` 是资源加载和校验的唯一入口，返回有序纹理、单帧时长、循环标记、Reduce Motion 静态帧索引、画布尺寸与脚底锚点。所有 PNG 都必须保留完整透明画布，禁止 trim 或依据 alpha bounds 重新定位。磁盘像素可以是 120 或 240，逻辑画布仍是 `120 × 120`。SpriteKit 使用 `.linear`，SwiftUI 使用中等插值；两个表面不得各自维护第二套角色素材。播放按 manifest 帧率推进，反应时长不得把短 clip 拉成慢放。

公开网页中的角色位图只能用于视觉核对，禁止下载、裁切、转码后直接进入 `Resources` 或应用包。产品帧只能从授权交付物或经授权方确认的独立制作源导出，并保留可追溯的源图与审批版本。

`PetMotionResolver` 是 `PetActivity`、`PetEmotion`、养成互动/结果、giver/receiver 角色和 Visit 阶段到 `PetMotionClipID` 的唯一映射点。构建测试必须验证两个角色的全部 clip、连续帧号、统一逻辑画布、透明通道、脚底锚点和 Reduce Motion 索引；发布构建不允许以矢量、旧 atlas 或含义不同的动作补洞。旧 naitang/tuanzi atlas 与程序化矢量 rig 已从呈现层移除。

### 单一位移所有权

```text
worldAnchor             owns screen/world translation only
├── shadow              fixed to ground anchor
└── bodyContainer       owns facing mirror only
    ├── characterSprite fixed 120 × 120 canvas; texture changes only
    └── effects         clip-local overlays when not baked into a frame
```

世界运动、帧播放和窗口呈现不能各自叠加位移。`walk` 只推进相同画布内的纹理帧，不能根据每帧 alpha bounds 移动或缩放 sprite。macOS 14 `CADisplayLink` 在移动和交互时以目标 60Hz 推进；到达且没有活动动作后停止，低频 idle 使用独立节拍。最终窗口坐标先按目标屏幕 `backingScaleFactor` 量化到物理像素，再用于比较和设置窗口原点，避免 1x/2x 与多屏切换时反复舍入。

Reduce Motion 不建立另一套业务状态机。每个 clip 在自己的帧 manifest 中指定静态帧索引，客户端仍完成到达、互动和离开状态迁移，展示层只切到该静态 PNG 并做透明度变化，不推进序列，也不做走位、弹跳、缩放或旋转。

`VisitProjection` 用 aggregate version 去重：active outgoing Visit 隐藏自己的 Pet；active incoming Visit 创建 remote Pet；关闭、好友关闭或 bootstrap 对账会恢复/移除。`pet.care.updated` 不进入事件线，只更新养成投影。旧 `VisitAction` 仅保留协议兼容，不参与新标准互动。

## 恢复模型

启动时先获取原子 bootstrap（账号、当前设备、自己的精确养成状态、角色外观、相关熟悉度、好友定性状态、pending/active Visit 和 event cursor），应用完整投影并持久化 cursor；随后从该 cursor REST catch-up。WebSocket 建立后再次 catch-up 关闭握手窗口，并在每个提示后拉取。即使 socket 一直在线但提示丢失，也会周期拉取。

客户端只在事件的 UI/Agent 处理成功后推进 cursor。未知 schema/type 会先推进该事件，随后 bootstrap 对账，避免永久毒事件。网络 mutation 先写本地 outbox，使用稳定 UUID 作为 `Idempotency-Key`，成功后删除。

角色外观采用相同 local-first 流程：bootstrap 若没有 catalog 2 角色或仍是旧 `mino-default`，在 GitHub 登录完成后显示一次性选择；用户确认后立即更新当前 Mac 并把 `PetAppearanceSelectionCommand` 写入持久 outbox。离线重启从 outbox 恢复“稍后同步”。服务端首次提交的角色永久锁定；另一设备选择冲突时返回 `appearance_locked`，客户端重新 bootstrap，以权威角色覆盖乐观结果并说明该角色已在另一设备选定。

详见 [`VisitProtocol.md`](VisitProtocol.md) 与 [`EventSynchronization.md`](EventSynchronization.md)。
