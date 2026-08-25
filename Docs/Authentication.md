# 身份与会话

## GitHub Device Flow

正式账号使用 GitHub OAuth Device Flow：

1. 客户端调用 `POST /v1/auth/github/device/start`；
2. Worker 向 GitHub 申请 device/user code，只把 device code 的 peppered hash 写入 D1；
3. 客户端自动复制完整 user code、打开 GitHub verification URL，并显示匹配码；
4. 客户端按服务端给出的 interval 调用 `POST /v1/auth/github/device/complete`；
5. Worker 取得 GitHub token 后立即调用 `GET https://api.github.com/user`，以稳定数字 `id` 而非可修改的 login/email 作为 subject；
6. GitHub token 不保存，Worker 为 `github:<id>` identity 签发 Mino 自己的 opaque session。

GitHub OAuth App 必须显式启用 Device Flow。macOS 客户端不保存 GitHub Client Secret，也不持久化 GitHub access token。D1 `accounts.provider_subject` 是通用 provider identity；以后接 QQ 时使用独立 `qq:<openid>` namespace。

## Session

Access Token 默认 15 分钟，Refresh Token 默认 30 天。正式签名客户端把随机 token 保存在 Keychain；缺少稳定签名的本机开发包使用按可执行文件隔离的 AES-GCM 加密会话文件，密钥与密文均限制为当前用户读写。D1 `sessions` 表只保存带 `SESSION_TOKEN_PEPPER` 的 SHA-256 hash、expiry 和 revoke time。

每个已认证请求同时检查：

- access token hash 存在且未过期；
- session 未 revoked；
- session 对应 Device 属于同一 Account 且未 revoked；
- Pet 与 Account 的一对一归属。

## Refresh rotation

`POST /v1/auth/refresh` 不接受 Bearer token，只接受 refresh token。Worker 查找未过期、未撤销且 Device 有效的 session，然后在一个 D1 atomic batch 中：

1. 只有旧 session 仍 live 时才 `INSERT … SELECT` replacement；
2. 只有 replacement 确实存在才撤销旧 session。

因此同一个 refresh token 的并发使用最多一个成功。成功响应丢失时，旧 token 已失效，客户端必须重新认证；这避免允许多个 replayable replacement。`POST /v1/auth/logout` 撤销当前 session。

## Device 与 Primary Agent

账号可有多个 macOS Device，但 `accounts.primary_agent_device_id` 必须引用该账号未撤销的 Device，D1 trigger 在存储层强制这一约束。首个设备自动成为 Primary Agent；授权账号可以调用 `/v1/devices/{id}/claim-agent` 切换。

只有 Primary Agent Device 可以：

- 请求模型 decision；
- 以 `actorType=pet_agent` 接受/拒绝 Visit；
- 创建 reaction/activity/speech/acknowledgement；
- 代表 Pet 执行其它 semantic social command。

非主设备仍可显示同步状态和执行真人操作。服务端永远使用 session 派生的 device identity，不信任客户端提交的 account/device header。

## 开发身份

`/v1/dev/bootstrap` 只在 `ENVIRONMENT ∈ {local,development,test}` 且 `DEV_BOOTSTRAP_ENABLED=true` 时启用。Production 配置若打开该开关会使环境校验失败。Alice、Bob、Charlie 的固定身份和 token 仅用于本机与 Workers Runtime 测试，不可部署为生产凭证。

## Secret 运维

生产配置 GitHub OAuth App Client ID，并用 `wrangler secret put` 设置 session pepper、信件 key 和可选模型 key。不得把 `.dev.vars`、Bearer token、refresh token 或 provider key 写入 Git、日志、event payload、D1 receipt 或崩溃报告。详情见 [`CloudflareDeployment.md`](CloudflareDeployment.md)。
