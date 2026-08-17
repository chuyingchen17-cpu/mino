# MVP 后端契约

机器可读契约以 [`Backend/openapi.yaml`](../Backend/openapi.yaml) 为准。基础路径为 `{baseURL}/v1`，成功信封是 `{"data": ...}`，错误信封是 `{"error":{"code":"...","message":"..."}}`。除健康检查和启用后的开发 bootstrap 外，所有路由都要求 `Authorization: Bearer <token>`。

## 核心接口

| 能力 | 接口 |
|---|---|
| 健康与开发身份 | `GET /health`, `POST /dev/bootstrap` |
| 当前身份与好友 | `GET /me`, `GET/POST /friendships`, `POST /friendships/{id}/respond` |
| 事件恢复与时间线 | `GET /events?friendshipID=&after=`, `GET /timeline?friendshipID=&after=`, `GET /ws?friendshipID=` |
| 托管模型代理 | `POST /agent/decision` |
| 自主对话 | `GET/POST /conversations`, `GET/POST /conversations/{id}/messages`, `POST /conversations/{id}/end` |
| 串门邀请 | `GET/POST /visit-invitations`, `POST /visit-invitations/{id}/respond` |
| 来访互动与反应 | `POST /visits/{id}/interactions`, `POST /visits/{id}/reactions` |
| 信件 | `POST /visits/{id}/letter`, `GET /letters/{letterID}` |
| 回家 | `POST /visits/{id}/end` |

旧版 presence/interaction 路由保留为迁移兼容入口，新 MVP 以 durable events 与 `MVPVisit` 为准。旧 `POST /pet-visits` 无法表达对方同意，现已在写入前返回 `409 visit_invitation_required`；它不会遗留 pending 串门，调用方必须改用邀请握手。

## 隔离与授权

Bearer token 只确定当前个人账号，不能隐式确定某一位好友。所有跨账号路由必须携带 `friendshipID`，服务端同时校验该关系已接受、当前账号是成员、目标账号/宠物属于该关系，以及资源的内部 scope 与该关系一致。不存在、跨好友关系和无权访问的私密资源统一返回不可枚举的 404。为迁移兼容，账号恰好只有一个已接受好友时可以暂时省略 `friendshipID`；拥有零个或多个好友时返回 `409 friendship_context_required`。

串门响应者由方向决定：`requestedByAccountID` 若是访客主人，则 host 响应；若是 host，则访客主人响应。事件同时携带 `requestedByAccountID` 与 `responderAccountID` 供客户端确定由哪只本地宠物处理。

## 幂等与恢复

所有 mutation 携带 UUID `idempotencyKey`，客户端也写 `Idempotency-Key` header。服务端在账号/好友关系和 operation scope 内保存 canonical request fingerprint 与首次回执：

- 相同 key + 相同 payload：返回首次结果，不重复事件或计费。
- 相同 key + 不同 payload：`409 idempotency_key_reused`。

事件 ID 是严格 UUID。每个好友关系有独立 cursor；空页保持请求 cursor，格式错误 cursor 返回 400，未知或跨关系 cursor 返回 404。WebSocket 不承担持久化，断线后一律先 REST catch-up。个人事件线由客户端合并所有好友关系中 `timelineVisible` 的事件，好友申请单独从 `/friendships?status=pending` 获取。

## 模型边界

客户端只提交裁剪后的触发事件、白名单逻辑状态、相关记忆摘要和可用动作。服务端拒绝未知状态字段、伪造的好友/目标宠物身份以及任何信件类上下文，再校验结构化 `PetDecision`；不保存 prompt、原始 provider response 或完整本地记忆，只按账号和 `inferenceID` 保存已验证决定、memory disposition 和 token usage 以支持重放。

非法输出、超时或网络失败不会改变 visit/presence，客户端进入安全 idle。密封文字信正文禁止进入 Agent 请求。

## 信件

`letter_attached` 与 `letter_received` 事件只含 ID 和路由元数据。PostgreSQL 与幂等回执中的正文均为 AES-256-GCM 密文；API 只在授权时解密。作者可读取自己的信，收件人仅在 `delivered` 后可读取。MVP 使用 HTTPS/WSS 和服务端加密，不宣称 E2EE。
