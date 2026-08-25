# Visit 协议

Visit 是一次授权串门的唯一聚合，不存在独立 presence 或 invitation 真相。它同时表达方向、响应者、逻辑驻留、互动、结束与信件交付。

## 身份与方向

一个 Visit 固定包含：

- `visitorPetID` / `visitorOwnerAccountID`：外出的宠物及其账号；
- `hostAccountID`：接待账号；
- `requestedByAccountID`：发起邀请的人类账号；
- `responderAccountID`：唯一有权接受/拒绝的账号；
- `friendshipID`：双方 accepted Friendship；
- `version` / `lastTransitionID`：竞争控制。

两种合法方向：

| 发起方式 | requester | visitor | host | responder |
|---|---|---|---|---|
| 宠物主人请求登门 | visitor owner | 自己的 Pet | 好友账号 | host |
| Host 邀请好友宠物 | host | 好友的 Pet | 自己账号 | visitor owner |

服务端只接受 friendship 两侧的上述组合，并自行推导 owner/responder；客户端提交的伪造 visitor、host 或跨好友 ID 返回不可枚举 404。

## 状态机

```text
                         accept
                    ┌──────────────┐
                    │              ▼
create ───────► pending ───────► active ───────► closed
                    │              │              ▲
                    │ decline      │ recall       │
                    │ cancel       │ send_home    │
                    │ expire       │ friendship   │
                    └──────────────┴──────────────┘
```

状态只有 `pending | active | closed`。关闭原因：

- `declined`：responder 拒绝；
- `cancelled`：requester 取消 pending；
- `expired`：超过 `expiresAt` 后的首次响应将其原子关闭；
- `recalled`：visitor owner 召回 active Visit；
- `sent_home`：host 结束 active Visit；
- `friendship_closed`：任一方关闭 Friendship，所有 open Visit 在同一事务关闭。

终态不重新打开。重复 `/end` 返回已收敛的 closed Visit，不重复 `visit.closed` 事件或信件交付。

## 并发约束

D1 partial unique indexes 是最终仲裁者：

```sql
UNIQUE(visitor_pet_id) WHERE status = 'active'
UNIQUE(host_account_id) WHERE status = 'active'
UNIQUE(visitor_pet_id, host_account_id) WHERE status = 'pending'
```

因此一个 Host 可同时收到多个不同好友的 pending，但只能接受一个；一只 visitor 也只能 active 在一个 Host。并发 accept 中只有一个 conditional update + event + receipt 批次成功，另一个映射为 `host_busy` 或 `visitor_busy`。同一 action 的 reply 由 `UNIQUE(reply_to_action_id)` 保证一次性。

## 无模型互动与离线恢复

Visit active 后，Host 可对当前来访宠物调用 `POST /v1/pets/{petID}/interactions`。客户端顺序固定为：本地计算乐观状态、立即播放 `PetReactionPlan`、写入持久 outbox、接收服务端回执后静默校正。访客主人或其 Primary Agent 离线不影响互动。

Worker 验证目标确实是自己的宠物或当前来访宠物，并以 idempotency key 原子更新养成状态、好友熟悉度和本次 Visit 聚合统计。30 秒内同动作只返回视觉反馈，不增长数值；单日亲密度和熟悉度分别受上限保护。精确数值只返回宠物主人，Host 只得到三级定性状态。

历史 `VisitAction` 路由继续保留以兼容旧客户端，但不再是投喂、陪玩、散步、贴贴或送花的标准路径，也不触发等待远端 Agent 的睡眠态。

## 可见状态

Swift `VisitProjection` 是纯 reducer：

- 自己 Pet 是 active Visit 的 visitor：本机隐藏；
- 自己账号是 active Visit 的 host：创建/更新 remote Pet snapshot；
- Visit closed：自己的 Pet 恢复，remote Pet 移除；
- pending 只显示请求/邀请，不改变桌面驻留；
- appearance version 较旧或重复 aggregate version 不覆盖新投影。

Bootstrap 是权威对账；事件负责增量。客户端不会把桌面坐标上传到 Worker。

## 幂等与恢复

每个 create/respond/action/end/letter 命令在本地 outbox 中拥有稳定 UUID，并只通过 `Idempotency-Key` header 发送。服务端以账号、operation、key 和 canonical payload fingerprint 保存首次回执：完全相同的重试重放，改变 payload 的 key 复用返回冲突。业务 transition、双方事件与回执在一个 D1 batch 中提交，所以“响应丢失后重试”不会产生第二个 Visit、Action、close 或 delivery。

应用重启先用 bootstrap 恢复 pending/active Visit、可见宠物、自己的精确养成状态、来访宠物定性状态和熟悉度，再从 bootstrap cursor 补拉。断网互动保留在本地 outbox；恢复后使用原 interaction ID 重放，服务端返回同一回执。WebSocket 缺失不会改变协议结果。

## 信件

信件只能由 active Visit 的一方写给另一方，初始 `attached`。正文加密写 D1，事件和 receipt 只保存 metadata。任何关闭 transition 都在同一 D1 batch 将 attached 信件改为 `delivered` 并为收件人写 `letter.delivered`；条件 marker 与终态保证最多一次。收件人在 delivered 前读取返回不可访问。

## 时序

```text
Visitor client        Worker + D1          Host client
      | POST Visit         |                    |
      |------------------->| state+2 events    |
      |                    |<--human accept----|
      |<------DO hint------| state+2 events    |
      | hide own Pet       |                    | walk in + welcome
      |                    |                    | local reaction first
      |                    |<--care interaction|
      |<------DO hint------| care+familiarity  | reconcile receipt
      |                    |<--end Visit-------| walk out + goodbye
      | restore own Pet    | close summary     | remove remote Pet
```

所有 command 在网络发送前进入本地 outbox，并保持同一个 `Idempotency-Key` 重试。WebSocket 箭头只是提示；缺失时 REST catch-up 与 60 秒 fallback 得到相同结果。
