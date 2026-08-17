# Mino MVP 架构

## 核心边界

每个账号拥有一只个人宠物，每个主客户端运行该宠物的 Agent。Agent 负责自主动作、主人互动、好友宠物对话、串门决定和长期记忆；服务端是有状态的通信媒介与模型代理，但不是宠物大脑。

```text
Alice 客户端 Agent ── REST/WSS ── PostgreSQL + 模型代理 ── REST/WSS ── Bob 客户端 Agent
       │                                  │                                  │
  本地加密记忆                    会话/串门/事件/加密信件                  本地加密记忆
  桌面坐标与动画                  不保存桌面坐标、不代替离线 Agent          桌面坐标与动画
```

后端是单个 Fastify 进程，PostgreSQL 是唯一服务端事实来源。账号可以拥有多个好友关系，所有跨账号操作都必须显式选择已接受的 `friendshipID`。WebSocket 只降低延迟；客户端始终以 `GET /events?friendshipID=<id>&after=<eventID>` 补齐断线和重启期间的事件。MVP 不使用 Redis、消息队列或微服务。

## Swift 模块依赖

```text
MinoApp
├── MinoAgent ─────────────┐
├── MinoRuntime            │
├── MinoPresentation       ├──> MinoDomain
├── MinoInfrastructure ────┤
├── MinoPersistence ───────┤
└── MinoSecurity ──────────┘
```

- `MinoDomain`：强类型 ID、命令、访问/对话/信件/事件模型与协议；不导入 UI 或网络实现。
- `MinoAgent`：串行本地决策队列、上下文裁剪、模型客户端、策略护栏和容量受限的 AES-GCM 记忆。
- `MinoRuntime`：当前本机可见宠物、坐标、随机移动和显式互动；悬停只暂停环境移动。
- `MinoPresentation`：桌面窗口、右键菜单、好友页和独立个人事件线。
- `MinoInfrastructure`：REST 与 WebSocket 实现。DTO 在进入应用协调器前解码为领域模型。
- `MinoPersistence`：按账号/Profile 隔离的每好友事件游标、个人事件线、快照和 Outbox。
- `MinoSecurity`：会话 token 与 Agent 记忆密钥的 Keychain 存储。
- `MinoApp`：`AgentCoordinator`、`ConversationCoordinator`、`VisitCoordinator`、`EventSyncCoordinator` 的唯一组合根。

## 事件与幂等

客户端为每个好友关系维护独立事件游标，先处理并持久化事件带来的 UI/Agent 状态，再推进该关系游标。个人事件线把所有好友事件按发生时间合并。若 Agent 决定产生的消息、应答或 reaction 尚未送达，处理器会抛错并保留旧 cursor，八秒补拉会用同一观察 ID 重试。观察 ID 同时作为模型 `inferenceID` 和后续命令的幂等键，因此不会重复计费或重复产生副作用。

服务端在一个数据库事务中写业务状态、好友事件与幂等回执。重复 key 且 payload 相同会重放首次结果；不同 payload 复用同一 key 返回冲突。旧数据库中的 `couple_id`/`couple_events` 仅作为内部迁移兼容 scope，不属于领域协议。

## 对话

自主社交开启后不需要主人逐句审批。目标宠物必须属于当前已接受好友关系。服务端校验宠物轮次，一段对话最多六条宠物消息，并保证每个好友关系最多只有一段 active 对话；真人加入时消息明确标记为 `human`。客户端重启时会逐好友恢复 active conversation 和消息上下文。最后一轮到达发起方客户端后，还会从服务端补齐有限 transcript，再由发起方本地 Agent 生成摘要并调用结束接口。事件线只保存摘要，不展示完整逐句记录。

## 串门

服务端只保存 `pending → active → ended/cancelled` 和逻辑驻留：

- 发起前必须校验双方仍是好友；解除或未接受好友关系不能创建串门。
- 访客主人主动请求登门时，由接待方宠物 Agent 决定。
- 接待方邀请对方宠物时，由访客宠物 Agent 决定。
- 接受后，原端隐藏访客，接待端显示访客；客户端重启会先查询 active visit 恢复这一状态。
- 来访宠物仍由原主人客户端 Agent 驱动。接待端默认让它打盹；原 Agent 通过 reaction 事件证明在线后才恢复活动。
- 投喂、玩耍、真人消息以及界面上的亲亲、送花、散步都会转成 visit interaction 送回原 Agent；本地动画不冒充远端回应。
- 原 Agent 离线时，互动保留在事件流中，不由服务端生成替代回应。
- 自主回家、原主人召回与接待主人请回均使用同一幂等结束接口。

## 信件隐私

文字信正文只进入信件接口和授权收件界面，不进入好友事件、事件摘要、Agent observation、模型上下文或日志。服务端以 AES-256-GCM 存储，收件人只能在串门结束并交付后读取。事件线保存 `letterID`，用户可再次打开；宠物只知道自己携带/带回了一封密封信。

## 仍属后续范围

正式身份注册与账号发现、好友解除/拉黑/举报、跨设备 Agent 主设备选举、图片明信片和物品系统、推送唤醒、完整 E2EE、可观测性与水平扩容不属于本轮 MVP。
