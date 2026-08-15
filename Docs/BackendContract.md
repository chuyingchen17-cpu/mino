# 后端接入约定

机器可读契约位于 [`Backend/openapi.yaml`](../Backend/openapi.yaml)。当前契约只覆盖连通性和互动投递，用于稳定客户端边界，不代表账号、配对和同步模型已经定稿。

## 配置

| Info.plist | 环境变量 | 默认值 | 说明 |
|---|---|---:|---|
| `MinoBackendMode` | `MINO_BACKEND_MODE` | `offline` | `offline` 或 `remote` |
| `MinoAPIBaseURL` | `MINO_API_BASE_URL` | 空 | 远端模式必填 |
| `MinoAPIVersion` | `MINO_API_VERSION` | `v1` | URL 版本段 |
| `MinoRequestTimeout` | `MINO_REQUEST_TIMEOUT` | `10` | 1–60 秒 |

环境变量优先于 Info.plist。非本地服务必须使用 HTTPS；HTTP 只允许 `localhost`、`127.0.0.1` 和 `::1`。

## 协议

- 基础路径：`{baseURL}/{apiVersion}`
- 健康检查：`GET /health`
- 发送互动：`POST /interactions`
- 成功响应：`{"data": ...}`
- 失败响应：`{"error":{"code":"...","message":"..."}}`
- 认证：`Authorization: Bearer <token>`
- 客户端标识：`X-Mino-Client: macos`
- JSON 日期：ISO 8601

每次互动都携带 UUID `idempotencyKey`，同时写入 `Idempotency-Key` 请求头。服务端必须在情侣关系范围内去重，重复请求返回第一次的 receipt，而不是再次触发互动。

## 身份与安全

- `PetProfileID` 是服务端档案 ID；本地 `.mine/.partner` 只是界面角色，禁止作为远端主键。
- Token 不允许出现在 Info.plist、环境配置文件、URL、分析事件或日志中。
- 客户端已通过 Keychain 会话仓库为 `AccessTokenProvider` 提供未过期的访问令牌；刷新流程尚未接入。
- 客户端不能信任本地 sender，服务端必须从登录会话和情侣关系重新授权。
- 错误日志只记录稳定错误码和请求 ID，不记录响应正文中的私人内容。

## 暂不定义

账号注册、邀请配对、宠物档案同步、素材清单、实时事件游标和冲突解决仍处于产品探索阶段。客户端已有强类型身份和情侣快照模型，但这些端点应该在交互流程明确后分别扩充协议，避免现在形成错误的通用 `/sync` 接口。
