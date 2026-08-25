# Account Event 同步

Mino 为每个 recipient 写一份独立 Account Event。客户端只有一个账号级 cursor，不再为每个好友维护流或 WebSocket；个人时间线只是该事实流的展示投影。

## Event 结构

```text
sequence              D1 AUTOINCREMENT cursor
id                    全局唯一 event ID
schemaVersion         当前为 1
recipientAccountID    唯一授权读者
friendshipID          可选的关系上下文
type
aggregateType / aggregateID / aggregateVersion
payload
timelineVisible
occurredAt
```

同一业务变化会为两侧账号插入各自的 event row，因此每个账号独立授权、独立 cursor、独立保留顺序。客户端按 `sequence` 升序处理；相同 aggregate 的较旧/重复 version 只推进 cursor，不重复副作用。

## 启动与握手

```text
GET /sync/bootstrap
  ├─ apply complete state projection
  └─ persist bootstrap.cursor
          │
GET /events?after=cursor until page < 100
          │
open /realtime with Bearer token
          │ ready
GET /events again (closes REST/WS handoff window)
          │
events_available ──► GET /events until drained
60 second timer ───► GET /events until drained
disconnect/error ──► wait, REST drain, reconnect
```

Bootstrap 的所有查询与 `MAX(account_events.sequence)` 在一个 D1 atomic batch 中执行。即使 bootstrap 返回后立刻发生 mutation，后续 `after=cursor` 也会取得它。

## Cursor 提交规则

对每个事件严格执行：

1. 解码；
2. reducer/UI/timeline/Agent handler 成功；
3. 原子保存 `sequence`。

若第 2 步失败，旧 cursor 保留并重放。若 cursor 文件保存失败，同样不处理下一事件。事件处理与 cursor 保存均在 Swift coordinator 的串行 MainActor 路径上，避免多页并发乱序。

若客户端无法识别 schema/type，它不会永久卡住：先保存该 sequence，再请求权威 bootstrap 并用 `max(event.sequence, bootstrap.cursor)` 对账。这允许服务端前向发布新 event，同时让旧客户端恢复已知状态。

## 分页与重复提示

`GET /events` limit 最大 100。客户端只要一页恰好 100 条就继续请求，直到少于 100；空页保持原 cursor。WebSocket 的 `ready`、重复 `events_available`、定时器和重连都只触发同一个 `drain(after:)`，因此重复 hint 不会产生重复副作用。

事件表全局 sequence 中属于其它账号的空洞不影响读取；`after` 是下界，不要求连续整数。`timelineVisible=true` 仅用于展示查询，状态同步必须读取完整流。

## 多设备与主 Agent

一个 Account 的全部设备连接同一个 Durable Object。每个设备保存自己的本地 cursor 并读取同一 recipient stream；事件天然可在多设备重放。只有 bootstrap 标记的 Primary Agent Device 可以执行 `pet_agent` 命令和模型请求。主设备变更产生账号事件；新主设备 bootstrap 后恢复 unresolved Visit Action，旧设备的写入由服务端拒绝。

## 故障场景

| 故障 | 恢复方式 |
|---|---|
| D1 commit 成功、DO notify 失败 | 60 秒 REST fallback 或下次启动补拉 |
| WebSocket 在握手窗口断开 | 建连前后各一次 drain；外层循环重连 |
| 重复 hint / 多设备同时拉取 | cursor + aggregate version 去重 |
| 客户端处理后、保存 cursor 前崩溃 | 重放事件；reducer/outbox 幂等 |
| 保存 cursor 成功后 UI 重建 | bootstrap 重建权威投影 |
| Agent 离线 | unresolved action 保留在 D1/bootstrap |
| mutation response 丢失 | 本地 outbox 使用原 Idempotency-Key 重试 receipt |
| 未知 event | 推进 cursor 后 bootstrap 对账 |

WebSocket 不承诺 durable delivery；D1 event row、bootstrap 和幂等 receipt 才是恢复闭环。
