# Worker API 契约

机器可读契约以 [`apps/worker/openapi.yaml`](../apps/worker/openapi.yaml) 为准。所有时间为 Unix milliseconds。成功信封为 `{"data": ...}`，错误信封为 `{"error":{"code":"...","message":"..."}}`。

除 health、GitHub Device Flow、refresh 和启用后的 dev bootstrap 外，所有接口要求 `Authorization: Bearer <accessToken>`。业务 mutation 还要求 UUID `Idempotency-Key` header；command body 不重复传输该 key。

## 路由

| 能力 | 接口 |
|---|---|
| 健康 | `GET /health`, `GET /v1/health` |
| 会话 | `POST /v1/auth/github/device/start`, `POST /v1/auth/github/device/complete`, `POST /v1/auth/refresh`, `POST /v1/auth/logout` |
| 本地开发 | `POST /v1/dev/bootstrap` |
| 当前账号 | `GET /v1/me`, `GET/PATCH /v1/me/profile`, `PATCH /v1/me/pet` |
| Agent 主设备 | `POST /v1/devices/{deviceID}/claim-agent` |
| 好友 | `GET/POST /v1/friendships`, `POST /v1/friendships/{id}/respond`, `POST /v1/friendships/{id}/close` |
| 同步 | `GET /v1/sync/bootstrap`, `GET /v1/events?after=&limit=&timelineVisible=` |
| 实时提示 | `GET /v1/realtime` WebSocket upgrade |
| Visit | `GET/POST /v1/visits`, `POST /v1/visits/{id}/respond`, `POST /v1/visits/{id}/end` |
| Visit Action | `POST /v1/visits/{id}/actions` |
| 对话 | `GET/POST /v1/conversations`, `GET/POST /v1/conversations/{id}/messages`, `POST /v1/conversations/{id}/end` |
| 信件 | `POST /v1/visits/{id}/letters`, `GET /v1/letters/{letterID}` |
| 模型 | `POST /v1/agent/decision` |

## 授权与不可枚举资源

Bearer token 在服务端解析为可信 `accountID/deviceID/petID/isPrimaryAgentDevice`。客户端不能通过 header、query 或 body 改写这些身份。跨账号命令必须同时满足：

- 当前账号属于目标 Friendship，且状态为 `accepted`；
- visitor、host、pet 与 friendship 两侧身份严格匹配；
- Visit/action/conversation/letter 内部 friendship 与账号归属匹配；
- `actorType=pet_agent` 时设备是当前 Primary Agent Device。

不存在与越权资源统一返回 404，避免泄露其它账号资源是否存在。无效输入、未知字段和未知 action 返回 400；请求体超过 64 KiB 返回 413。

## 宠物角色永久选择

`PATCH /v1/me/pet` 是首次选择角色及旧账号升级的唯一写入口。协议继续使用 appearance schema 1，并把官方双角色目录固定为 catalog 2：

```json
{
  "appearanceSchemaVersion": 1,
  "appearanceCatalogVersion": 2,
  "appearance": {
    "rigID": "maltese-pair-v1",
    "body": "maltese-white"
  }
}
```

`appearance.body` 只接受 `maltese-white` 或 `retriever-yellow`。所有字段均为 strict；额外字段、其它 rig、其它 catalog 或角色值返回 `400 unsupported_pet_appearance`。稳定 UUID 只放在 `Idempotency-Key` header，不进入 body。

写入规则是一次性永久选择：

- 当前外观为空或 `rigID = mino-default` 时允许首次写入，不需要 D1 migration；
- 已选角色与命令相同，返回当前 `PublicPetSnapshot`，不增加 appearance version；
- 已选角色与命令不同，返回 `409 appearance_locked`；
- 两台设备并发选择不同角色时，D1 首次成功提交为事实，失败方收到 `appearance_locked`；客户端必须 bootstrap 读取权威角色，不可本地覆盖；
- 相同 `Idempotency-Key` 与相同 body 重放首次结果；同 key 不同 body 仍返回 `409 idempotency_key_reused`。

首次成功会增加 `appearanceVersion`，并发送 timeline-invisible 的 `pet.appearance.updated` 给本人、所有已接受好友和当前来访 Host。事件只包含 `PublicPetSnapshot`，不会发送旧 avatar recipe。`GET /v1/sync/bootstrap`、好友资料和访问中投影均返回同一 schema/catalog/appearance/version；访问中的宠物可原地刷新角色，不重新执行进场。

客户端必须先把选择写入持久 outbox，再立即乐观显示。离线时保留“稍后同步”；重启从 outbox 恢复相同选择。收到成功回执后删除 mutation；收到 `appearance_locked` 后重新 bootstrap，并以服务端角色收敛所有窗口、头像和桌宠。

## Visit 命令

创建 Visit 的 body 为：

```json
{
  "friendshipID": "uuid",
  "visitorPetID": "pet-id",
  "hostAccountID": "account-id",
  "reason": "optional"
}
```

若请求者是 visitor owner，则 host 是 responder；若请求者是 host，则 visitor owner 是 responder。只有 responder 能调用 `/respond`。过期 pending 在响应时原子收敛为 `closed/expired`。`/end` 是收敛操作：pending requester 可取消；active visitor owner 可召回；active host 可请回；重复和并发结束返回同一个 closed 事实。

Action 使用 discriminated union。真人允许 `feed/play/pet/hug/kiss/flower/walk/message`；Pet Agent 允许 `reaction/activity/speech/acknowledgement`。真人 Host action 标记 `requiresResponse`，visitor owner 的 Primary Agent 以 `replyToActionID` 回复；数据库保证一个 action 最多一个 reply。

完整状态机见 [`VisitProtocol.md`](VisitProtocol.md)。

## 幂等

幂等 scope 为 `(accountID, operation, Idempotency-Key)`。服务端保存 canonical request fingerprint：

- 同 key + 同 payload：重放首次 HTTP status 与 data，不重复事件、交付或模型计费；
- 同 key + 不同 payload：`409 idempotency_key_reused`；
- 并发 transition：只有版本/unique constraint 获胜者写事件和 receipt，失败者返回明确冲突或收敛后的状态。

Refresh Token rotation 使用同一个 D1 atomic batch 插入唯一 replacement 并撤销旧 session；同一 refresh token 的并发请求最多一个成功。

## Account Event

`GET /v1/events?after=<sequence>&limit=1...100` 只返回当前账号事件副本，按 `sequence` 升序。`nextCursor` 为空页时等于输入 cursor。`timelineVisible=true` 只过滤展示事件，不改变账号事实流的含义。

WebSocket 只发：

```json
{"type":"ready"}
{"type":"events_available"}
```

消息不是事实，也不携带 account identity 或业务 payload；任何提示都触发 REST catch-up。

## 模型与信件

模型请求只接受裁剪后的 trigger、白名单 state/memories 和 available actions。`inferenceID` 与请求 fingerprint 绑定，成功结果可重放；prompt、原始 provider response 和完整本地记忆不持久化。信件类字段在 Agent context 中被拒绝。

信件 body 只出现在 attach 请求与授权后的 `GET /letters/{id}` 响应。D1 保存 `ciphertext/iv/key_version`；Account Event 和幂等回执只保存 ID、作者、收件人、Visit 与 delivery status。收件人只有在 Visit 结束且 status 为 `delivered` 后能读取。
