# Cloudflare 部署

## 资源清单

每个环境需要：

- 一个 Worker：`mino-worker-staging` 或 `mino-worker-production`；
- 一个独立 D1 database：`mino-staging` 或 `mino-production`；
- Worker 内的 `ACCOUNT_REALTIME` Durable Object binding，class 为 `AccountRealtimeHub`；
- Durable Object migration tag `v1`；
- GitHub OAuth Client ID、session/letter secrets，以及可选 model secret。

本地 `wrangler.jsonc` 的 D1 ID 是开发占位值；staging 仍需在首次部署前替换自己的 D1 ID。Production 已绑定独立的 `mino-production`，不要跨环境复用数据库。

## 首次创建

登录正确的 Cloudflare account 后：

```sh
cd Backend
npx wrangler whoami
npx wrangler d1 create mino-staging
npx wrangler d1 create mino-production
```

把输出 ID 写入 `wrangler.jsonc` 对应 environment。不要复用数据库跨环境。

逐环境设置 secret：

```sh
npx wrangler secret put SESSION_TOKEN_PEPPER --env staging
npx wrangler secret put LETTER_ENCRYPTION_KEY_V1 --env staging
```

`GITHUB_CLIENT_ID` 是非敏感 Wrangler var，但 OAuth App 必须启用 Device Flow。Production 重复上述 secret 命令并改为 `--env production`。需要 Agent 模型时再设置 `MODEL_PROVIDER_API_KEY`；`MODEL_PROVIDER_BASE_URL` 和 `MODEL_NAME` 可以作为非敏感 vars。

## 验证与迁移

提交前：

```sh
npm ci
npm run typecheck
npm test
npm run openapi
npm run deploy:dry-run
```

应用 staging migrations：

```sh
npx wrangler d1 migrations apply mino-staging --remote --env staging
npx wrangler deploy --env staging
```

完成 GitHub Device Flow、两个账号好友、双方向 Visit、action/reply、事件 catch-up、letter delivery 和 restart/bootstrap smoke 后，再对 production 执行：

```sh
npm run db:migrate:remote
npx wrangler deploy --env production
```

D1 migration 采用只向前的编号 SQL。生产迁移前先创建可恢复备份/导出并阅读 SQL；不要在自动化中运行 destructive ad-hoc SQL。Worker 代码必须兼容迁移完成后的 schema，先迁移再 deploy。

## 环境保护

Production 必须满足：

```text
ENVIRONMENT=production
DEV_BOOTSTRAP_ENABLED=false
```

Worker 会拒绝 production + dev bootstrap 的组合。GitHub OAuth App 应以 `https://mino.pet` 为主页并启用 Device Flow；API custom domain 为 `api.mino.pet`，根域名保留给产品页。

## 密钥轮换

- `SESSION_TOKEN_PEPPER`：改变后现有 session hash 无法匹配，等价于全量登出；安排维护窗口并明确通知。
- `LETTER_ENCRYPTION_KEY_V1`：当前 schema 保存 `key_version`，但代码只配置 v1 key。上线前若需要无损轮换，应先发布多版本 decrypt，再迁移 ciphertext，最后移除旧 key。
- GitHub Client ID：变更 OAuth App 会要求所有未完成 Device Flow 重新开始；Mino 已签发 session 不受影响。
- Model provider key：可直接替换，已完成 inference receipt 不会重新计费；进行中的请求需要按失败语义恢复。

## 监控与回滚

至少监控 5xx、D1 errors/latency、Durable Object connection/notification errors、401/409 比例、model provider latency 与 letter decrypt failures。通知失败不影响 commit，因此还要监控客户端 REST fallback 延迟。

Worker 代码可回滚到仍兼容当前 D1 schema 的上一版本；D1 migration 不自动向下回滚。若新 schema 不向后兼容，应前置 expand/contract 发布，而不是依赖代码回滚删除列或表。

Production D1、GitHub Client ID、production secrets 与 `api.mino.pet` custom domain 已配置并部署。根域名 `mino.pet` 保持独立，供产品页、注册和用户界面使用。
