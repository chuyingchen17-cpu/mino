# Mino Worker

Mino 后端是 Cloudflare Worker。Hono 提供严格校验的 REST/OpenAPI 边界，D1 保存业务事实，`AccountRealtimeHub` Durable Object 通过 Hibernation WebSocket API 向一个账号的全部在线设备发送轻量提示。

## 本地开发

```sh
cp .env.example .dev.vars
npm ci
npm run db:migrate:local
npm run dev
```

默认地址为 `http://127.0.0.1:8787`。健康检查：

```sh
curl http://127.0.0.1:8787/v1/health
```

开发身份仅在 `ENVIRONMENT=development` 且 `DEV_BOOTSTRAP_ENABLED=true` 时可用：

```sh
curl -sS http://127.0.0.1:8787/v1/dev/bootstrap \
  -H 'content-type: application/json' \
  -d '{"profile":"alice"}'
```

Alice 与 Bob 预置为好友；Charlie 没有预置好友。开发凭证只用于本机测试。

## 命令

- `npm run typecheck`：检查 Worker 与测试 TypeScript。
- `npm test`：使用官方 Workers Vitest 集成，在 Workers Runtime 中测试真实 D1 与 Durable Object binding。
- `npm run openapi`：从路由生成 `openapi.yaml`。
- `npm run db:migrate:local`：迁移本地 Wrangler D1。
- `npm run db:migrate:remote`：迁移 production D1；先替换正式资源 ID。
- `npm run deploy:dry-run`：验证 Worker bundle、D1 binding 和 Durable Object migration，不部署。

## 资源与变量

`wrangler.jsonc` 声明：

- `DB`：D1 binding；本地、staging、production 使用独立数据库。
- `ACCOUNT_REALTIME`：`AccountRealtimeHub` Durable Object binding。
- `v1` Durable Object migration。

以下值必须通过 `.dev.vars`、Wrangler vars 或 `wrangler secret put` 提供：

- GitHub：`GITHUB_CLIENT_ID`，对应启用了 Device Flow 的 OAuth App
- 会话：`SESSION_TOKEN_PEPPER`
- 信件：`LETTER_ENCRYPTION_KEY_V1`
- 模型：可选 `MODEL_PROVIDER_API_KEY`；未配置时社交事实功能可用，但 Agent 模型调用会失败并由客户端降级

生产环境必须设置 `ENVIRONMENT=production`、`DEV_BOOTSTRAP_ENABLED=false`。`SESSION_TOKEN_PEPPER` 或信件密钥丢失会分别使现有会话或密文不可恢复，需按版本化运维流程轮换。

## 持久化与一致性

D1 migrations 按领域拆分为 identity、friendships、visits/actions、account events/idempotency、conversations、letters 和 model inferences。Mutation 使用一个 `DB.batch()` 原子提交：

1. 受版本/transition marker 保护的业务状态；
2. 每个 recipient 独立的 Account Event；
3. 请求指纹与首次响应组成的幂等回执。

提交后 Worker best-effort 通知双方账号的 Durable Object。通知失败不回滚业务；客户端最长 60 秒通过 REST 补拉。

同一 operation + `Idempotency-Key` + 同 payload 重放首次结果；同 key 不同 payload 返回 `409 idempotency_key_reused`。D1 partial unique indexes 处理 Host Busy、Visitor Busy、同访客/Host pending 和 action 单次 reply 竞争。

## 安全边界

- D1 只保存 access/refresh token hash，不保存 Bearer Token 明文；refresh rotation 原子撤销旧 session。
- GitHub Device Flow 遵守 provider interval；每次成功授权都重新请求 GitHub `/user`，以稳定数字 ID 建立 provider identity，GitHub token 不落库。
- 跨账号资源同时校验当前账号、accepted friendship、目标账号/宠物和资源归属；越权资源统一不可枚举 404。
- `pet_agent` 写入只允许当前 Primary Agent Device。
- 信件正文使用 AES-GCM 密文写入 D1；event、日志与 idempotency receipt 都不包含明文。
- 请求体上限 64 KiB，全部输入使用 strict schema，拒绝未知 action / appearance 字段。

协议以 [`openapi.yaml`](./openapi.yaml) 为准；部署步骤见 [`../Docs/CloudflareDeployment.md`](../Docs/CloudflareDeployment.md)。
