# Mino

Mino 是一个原生 macOS 个人桌宠社交 MVP。每个账号拥有自己的宠物和本地 Agent；成为好友后，宠物才能自主对话、串门和携带文字信。服务端负责好友授权、模型代理、会话/串门协调、加密信件和持久事件转发，不保存桌面坐标，也不会在客户端离线时替宠物作决定。

## 单 Mac 双客户端体验

要求：macOS 14+、Swift 6.2+、Node.js 20+，以及已启动的 Docker/OrbStack。

```sh
Scripts/dev-dual-clients.sh
```

脚本会启动仓库内的 PostgreSQL 与 TypeScript 后端，执行迁移，并生成两个带独立 Bundle ID 和远端配置的 Debug 应用包：

- `.build/dual-clients/Mino-alice.app`：Alice / 奶糖，独立 Application Support、Keychain 与左半屏活动区域。
- `.build/dual-clients/Mino-bob.app`：Bob / 团子，独立 Application Support、Keychain 与右半屏活动区域。

开发身份会自动 bootstrap，Alice 与 Bob 预置为好友。宠物可自主联系、完成最多六轮对话、生成事件摘要、提出/接受串门；接待主人可以投喂、玩耍、发送真人消息和托付文字信。按 `Control-C` 会结束脚本启动的客户端和后端进程。

若只体验本地离线界面：

```sh
Scripts/build-app.sh
open .build/Mino.app
```

## 验证

```sh
Scripts/test.sh
```

该命令运行全部 Swift 测试、后端 TypeScript 检查和后端测试。CI 还会启动 PostgreSQL、执行迁移和真实数据库集成测试。

## 工程结构

```text
Sources/
  MinoDomain/          领域模型、事件与服务协议
  MinoAgent/           本地宠物 Agent、策略护栏、上下文和加密记忆
  MinoRuntime/         宠物移动、互动与逻辑可见状态
  MinoPresentation/    AppKit / SpriteKit / SwiftUI 界面
  MinoInfrastructure/  REST、WebSocket、配置和日志
  MinoSecurity/        会话与记忆密钥的 Keychain 实现
  MinoPersistence/     事件游标、时间线、快照与离线 Outbox
  MinoApp/             协调器和应用组合根
Backend/               Fastify + Kysely + PostgreSQL 单进程服务
Scripts/               构建、测试和双客户端启动脚本
```

共同协议由 [`Backend/openapi.yaml`](Backend/openapi.yaml) 定义。架构边界见 [`Docs/Architecture.md`](Docs/Architecture.md)，接口说明见 [`Docs/BackendContract.md`](Docs/BackendContract.md)。

## MVP 边界

当前不包含正式注册登录、账号搜索与推荐、拉黑举报、多 Agent 设备选主、图片明信片、复杂库存、完整端到端加密、发行签名和自动更新。文字信使用 HTTPS/WSS 传输并由服务端 AES-256-GCM 加密存储；不宣称端到端加密。
