# 本地数据与会话

## Profile 隔离

Debug 双客户端通过 `MINO_CLIENT_PROFILE=alice|bob` 选择独立命名空间。Application Support、会话存储、Agent 记忆密钥与本地状态不会跨 profile 共享。

```text
~/Library/Application Support/Mino/<profile>/
├── account-event-cursors.json
├── personal-timeline.json
├── social-mutation-outbox.json
└── agent-memory.json.enc
```

目录权限为 `0700`，普通状态文件使用原子替换和 `0600` 权限。每个文件包含 schema version；未知版本会明确失败，不会静默覆盖原文件。默认 profile 使用 `Mino/` 根路径，避免强制迁移现有用户目录。

## 会话与本地密钥

具有稳定 Apple Development / Developer ID 签名时，Keychain service 为 `com.mino.app.session[.profile.<namespace>]`，保存：

- Account ID；
- Access Token 与过期时间；
- 可轮换 Refresh Token。

Credential 的日志描述始终 redact token。Agent memory 的 256-bit AES key 使用独立 Keychain item；session token、refresh token 和 memory key 不写入 Info.plist、明文 JSON 或日志。Device revoke 或 refresh 失败后客户端清除不可用 credential 并重新认证。

ad-hoc 开发包没有稳定的 Keychain designated requirement，因此不访问上述 Keychain item。它在当前 profile 下创建按可执行文件 CDHash 隔离的 `local-security.executable.<hash>/`：随机密钥和 AES-GCM 会话密文分别保存为 `0600` 文件，目录为 `0700`，写入使用原子替换。相同 app 重开可恢复会话；重新构建后进入新的隔离目录并需要重新登录。没有开发者身份时：`curl -fsSL https://raw.githubusercontent.com/chuyingchen17-cpu/mino/main/Scripts/install.sh | zsh` 安装 CI nightly，或 `Scripts/install-app.sh` 从源码装到 `~/Applications/Mino.app`。该降级只服务本机运行，不替代发行签名。

## Account Event Cursor

`account-event-cursors.json` 以 Account ID 为 key，只允许单调增加。处理顺序为：

1. 解码事件并更新 `VisitProjection`、UI、Agent 或时间线；
2. 上述处理成功；
3. 原子持久化该 `sequence`。

因此进程在第 1/2 步崩溃会重放事件，而不会丢事件。Reducer 同时使用 `(aggregateID, aggregateVersion)` 去重副作用。未知 event type 会推进 cursor 后强制 bootstrap 对账，避免一个前向版本事件永久阻塞同步。

## Bootstrap 与个人时间线

每次启动先使用 `/v1/sync/bootstrap` 恢复账号、设备、Pet、好友、pending/active Visit、未处理 Visit Action、active conversations 与事件 cursor。Bootstrap 是 D1 atomic batch 的同一快照；随后从其 cursor 补拉，关闭响应到下一次写入之间的窗口。

`personal-timeline.json` 仅保存 `timelineVisible` 的真实事件，按 event ID 去重并保留服务端发生时间。它不会存储或推导 Visit 持续时长。Letter 只保存 metadata/letterID，正文按需从授权接口读取。

## Social Mutation Outbox

Visit create/respond/action/end、conversation create/message/end 与 letter attach 在发送前进入 `social-mutation-outbox.json`。每条记录保存稳定 `idempotencyKey`、命令 payload、尝试次数和下次时间；30 秒调度器按有上限的退避重试，服务端成功 receipt 后删除。Transport、429 与 5xx 可重试；400/401/403/404、409 和本地无效请求会停止重试并移除记录。容量默认 500，最旧记录先淘汰。

信件正文可能在尚未收到服务端回执时短暂存在于本机 `0600` outbox 中；成功后立即删除。它不会进入事件、时间线、Agent memory 或日志。当前不是端到端加密，因此已解锁本机与服务端解密密钥仍属于信任边界。

## Agent 记忆

长期记忆文件使用 CryptoKit AES-GCM 加密，默认最多 200 条。模型只收到本轮筛选出的摘要。密封信正文永远不属于 Agent observation 或记忆，宠物只能知道一封信被附着或已交付。
