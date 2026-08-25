# Mino

Mino 是原生 macOS 个人桌宠社交 MVP。每个账号拥有一只可养成的桌宠；好友关系授权后，主人可以双向邀请串门、离线照顾来访宠物，并托付密封文字信。摸摸、投喂、陪玩、散步等标准互动完全由本地确定性引擎即时回应，不调用模型；服务端只负责身份、授权、养成事实、Visit、信件和事件同步。

## 本地运行

要求：macOS 14+、Swift 6.2+、Node.js 20+。后端直接运行在本地 Cloudflare Workers Runtime，不需要 Docker 或 PostgreSQL。

```sh
cp Backend/.env.example Backend/.dev.vars
npm --prefix Backend ci
npm --prefix Backend run db:migrate:local
npm --prefix Backend run dev -- --ip 127.0.0.1 --port 8787
```

另一个终端可启动 Alice / Bob 两个隔离的 Debug 客户端：

```sh
MINO_API_BASE_URL=http://127.0.0.1:8787 Scripts/dev-dual-clients.sh
```

脚本会在后端未运行时自动迁移本地 D1 并启动 Wrangler，然后生成：

- `.build/dual-clients/Mino-alice.app`
- `.build/dual-clients/Mino-bob.app`

若只想验证双账号完整协议，不打开 GUI：

```sh
Scripts/smoke-dual-client-api.sh
```

## 验证

```sh
Scripts/test.sh
```

该命令运行 Swift 测试、Worker TypeScript 检查、Workers Runtime 中的 D1 / Durable Object 测试、OpenAPI 生成和 Wrangler dry-run。单独构建应用：

```sh
Scripts/build-app.sh
```

正式或 QA release 包必须使用稳定的 Developer ID 签名，以使用 Keychain
并让登录状态安全地跨版本升级：

```sh
MINO_BUILD_CONFIGURATION=release \
MINO_CODE_SIGN_IDENTITY="Developer ID Application: …" \
Scripts/build-app.sh
```

`MINO_ALLOW_ADHOC_RELEASE=1` 只供 CI 校验未分发的 bundle 结构使用。

本机 Debug 包优先使用稳定的 Apple Development 身份：

```sh
MINO_CODE_SIGN_IDENTITY="Apple Development: …" Scripts/build-app.sh
```

如果 `codesign` 返回 `errSecInternalComponent`，需要先由本人解锁“登录”钥匙串或在
Xcode 中允许该私钥用于签名；不要把锁屏密码写进脚本或环境变量。未能稳定签名时，
构建脚本会生成 ad-hoc 包；该包使用按当前二进制隔离的 AES-GCM 本地会话存储，
不会访问旧构建的 Keychain。相同 app 重开可复用登录，重新编译后需登录一次。

标准客户端（包括 Xcode / SwiftPM 直接运行）内置生产服务 `https://api.mino.pet`，用户界面不提供服务器地址、API 版本或超时设置。`MINO_API_BASE_URL` 等环境变量只用于本地双客户端和开发 smoke，不会成为产品设置。

## 架构

```text
macOS 客户端 ── HTTPS/WSS ── Cloudflare Worker (Hono)
     │                              ├── D1：业务状态、账号事件、幂等回执
     │                              ├── AccountRealtimeHub Durable Object
     └── 本地回应/动画/持久 Outbox         └── 可选模型代理（不在标准互动路径）
```

Worker 写入业务状态、每个收件人的 Account Event 和幂等回执后，按 `AccountID` 通知唯一 Durable Object。WebSocket 只发送 `ready` / `events_available` 提示；客户端始终通过 `GET /v1/events?after=` 恢复事实，并用 `GET /v1/sync/bootstrap` 对账完整状态。

主要目录：

```text
Sources/MinoDomain/          领域模型、Visit 投影、命令和服务协议
Sources/MinoAgent/           本地 Agent、策略护栏和加密记忆
Sources/MinoRuntime/         本地宠物移动、动画与可见状态
Sources/MinoPresentation/    AppKit / SpriteKit / SwiftUI
Sources/MinoInfrastructure/  Worker REST、账号 WebSocket 与配置
Sources/MinoPersistence/     账号事件游标、个人时间线、社交 Outbox
Sources/MinoSecurity/        Keychain／加密会话与记忆密钥
Sources/MinoApp/             同步、Visit、对话和 Agent 协调器
Backend/                     Cloudflare Worker、D1 migrations、Durable Object
```

机器可读协议为 [`Backend/openapi.yaml`](Backend/openapi.yaml)。详细设计见 [`Docs/Architecture.md`](Docs/Architecture.md)、[`Docs/VisitProtocol.md`](Docs/VisitProtocol.md) 与 [`Docs/EventSynchronization.md`](Docs/EventSynchronization.md)；视觉规范见 [`Docs/DesignTokens.md`](Docs/DesignTokens.md)，部署见 [`Docs/CloudflareDeployment.md`](Docs/CloudflareDeployment.md)。

## MVP 边界

正式账号发现、拉黑举报、推送唤醒、图片明信片、复杂库存、Pro 套餐/额度账本、完整端到端加密、发行签名与自动更新仍不在本轮范围。文字信通过 HTTPS/WSS 传输并在 D1 中使用 AES-GCM 密文保存；这不是 E2EE。未来 Pro 智能回应只能在基础反馈之后由发起者主动触发，不能改变养成数值、Visit 权限或读取信件正文。
