# 本地数据与会话

## Profile 隔离

Debug 双客户端通过 `MINO_CLIENT_PROFILE=alice|bob` 选择独立命名空间。Alice 与 Bob 的 Application Support、会话 Keychain、Agent 记忆密钥和事件游标互不共享；配置错误回退到离线模式时也保留已识别的 profile，避免两个实例意外合并。

```text
Mino/<profile>/couple-snapshot.json
Mino/<profile>/interaction-outbox.json
Mino/<profile>/couple-timeline.json
Mino/<profile>/couple-event-cursor.json
Mino/<profile>/agent-memory.json.enc
```

默认 profile 保留旧路径兼容。普通 JSON 文件使用原子替换、`0600` 文件权限和版本信封；读取未知 schema 时失败并保留原文件。

## Keychain

Keychain 保存：

- bearer session credential；
- 每个 profile 独立的 256-bit Agent memory AES key。

Token 和记忆密钥不写入 Info.plist、普通 JSON 或日志。开发 bootstrap token 仅是本机公开测试凭证，并在服务重启后保持稳定；生产环境禁用该入口。

## Agent 记忆

长期记忆容量默认 200 条，使用 CryptoKit AES-GCM 加密文件存储。检索按宠物、类别、相关宠物、时间和有限关键词进行；模型只能收到本轮挑选出的摘要。主人可以查看和删除长期记忆。

密封信正文不属于 Agent 记忆，也不会作为观察事件进入上下文。信件正文按需从授权后端接口读取，不落入本地时间线 JSON。

## 事件与时间线

`couple-event-cursor.json` 只在对应事件的 UI 与 Agent 处理成功后推进。客户端重启时先向服务端查询 active/pending visit 恢复可见状态，再从 cursor 补收事件，防止外出宠物在两端同时出现。

`couple-timeline.json` 只保存 `timelineVisible` 的真实事件，按 ID 去重并保留发生时间；不推导或显示串门持续时长。信件事件只保存可再次授权获取正文的 `letterID`。

## Outbox

旧版离线互动 Outbox 继续保留：以 `idempotencyKey` 去重，使用有上限的指数退避，成功 receipt 后删除。MVP 新社交命令由 durable event 协调器和服务端幂等共同保证恢复。
