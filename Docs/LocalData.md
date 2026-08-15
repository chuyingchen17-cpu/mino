# 本地数据与会话

## 数据分类

Mino 将敏感凭证和普通应用数据分开保存：

- Keychain：访问令牌、刷新令牌、账号 ID、过期时间。
- Application Support：情侣快照和待投递互动，不包含 token。
- OSLog：只记录状态、计数和稳定错误码，不记录 token、请求正文或私人内容。

签名并启用 App Sandbox 后，Application Support 会自动位于应用容器中。当前文件名为：

```text
Mino/couple-snapshot.json
Mino/interaction-outbox.json
```

文件使用原子替换并设置为 `0600`，目录设置为 `0700`。

## Schema 与迁移

每个 JSON 文件都使用以下信封：

```json
{
  "schemaVersion": 1,
  "payload": {}
}
```

本地 payload 中的日期使用 Unix epoch 毫秒，避免互动重试时间在进程重启后丢失亚秒精度；HTTP 契约仍使用 ISO 8601。

读取未知版本时必须失败并保留原文件，禁止自动清空。增加字段时优先保持向后兼容；需要破坏性变更时，为旧版本增加显式迁移器并用 fixture 测试。

Keychain 凭证也有独立 schema version。Token 永远不能迁移到普通 JSON 文件。

## Interaction Outbox

- `idempotencyKey` 同时是本地去重键和 HTTP `Idempotency-Key`。
- 默认最多保留 500 条，防止离线状态无限占用磁盘。
- 失败只保存不超过 128 字符的稳定错误码。
- 重试使用 2 秒起步、最高 5 分钟的指数退避。
- 条目只有在服务端返回有效 receipt 后才能删除。
- App 崩溃不会产生“永久 in-flight”状态；下次启动仍可重新投递同一幂等请求。

当前 Demo 互动没有真实的账号和宠物档案 ID，因此不会写入 Outbox。正式登录与配对完成后，由应用层投递协调器创建 `InteractionCommand`，而不是让 `PetWorld` 直接访问持久化或网络。

## 登出与解除配对

后续登出用例必须按顺序停止同步任务、清除 Keychain 会话、清除情侣快照和 Outbox，最后更新 UI。任一步失败都需要可见错误，不能在凭证仍存在时假装已经退出。
