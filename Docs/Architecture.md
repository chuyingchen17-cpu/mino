# Mino 工程架构

## 目标

当前架构优先保证三件事：桌宠运行时可持续演进、界面实现可替换、后端接入不会渗透到动画和窗口代码。它不是最终的全部生产架构，但已经建立后续功能必须遵守的边界。

## 依赖方向

```text
                         ┌──────────────────┐
                         │     MinoApp      │
                         │  Composition Root│
                         └───┬────┬────┬────┘
                             │    │    │
                    ┌────────┘    │    └──────────┐
                    ▼             ▼               ▼
             MinoRuntime  MinoPresentation  MinoInfrastructure
                    │             │               │
                    └─────────────┴───────────────┘
                                  ▼
                              MinoDomain
```

- `MinoDomain`：稳定的业务语言、值类型和服务协议。不能导入 AppKit、SpriteKit 或 URLSession。
- `MinoRuntime`：`PetWorld`、移动算法和互动状态机。不能创建窗口或访问网络。
- `MinoPresentation`：透明窗口、SpriteKit 节点和效果渲染。只消费领域状态，通过回调表达用户意图。
- `MinoInfrastructure`：环境配置、OSLog、REST 客户端和认证令牌抽象。不能依赖 UI。
- `MinoApp`：唯一的组合根，负责实例化服务、连接状态与渲染、处理应用生命周期。

任何新模块都必须保持依赖向下，不允许 `Domain` 反向依赖具体实现。

## 状态与并发

- `PetWorld` 是桌宠位置、朝向、活动和情绪的单一事实来源。
- AppKit、SpriteKit 与 `PetWorld` 都隔离在 `@MainActor`。
- 网络客户端使用 actor，网络健康检查不阻塞应用启动。
- 网络响应必须先转换为领域模型，再进入运行时；渲染层不能直接解析 DTO。
- 互动使用显式阶段状态机，避免依赖散落的延时回调。

## 后端边界

`MinoDomain.BackendService` 是当前唯一后端入口。`MinoInfrastructure` 提供：

- `OfflineBackendService`：默认安全实现，不发出请求。
- `HTTPBackendService`：版本化 REST 实现。
- `AccessTokenProvider`：未来接入 Keychain 会话的替换点。
- `BackendServiceFactory`：根据环境配置创建具体服务。

当前本地 Demo 互动不会自动上传。正式同步应在 `MinoApp` 中加入独立的命令协调器，由它决定乐观更新、重试、去重与失败反馈，而不是让 `PetWorld` 依赖网络。

未来实时同步应新增单独的 `RealtimeService` 协议，不要把 WebSocket 生命周期塞进 REST 客户端。

## 测试策略

- `MinoDomainTests`：值类型、编码兼容性和领域约束。
- `MinoRuntimeTests`：移动算法和互动状态机，使用确定性时间步长。
- `MinoInfrastructureTests`：配置优先级、安全校验、请求路径和协议头。
- 后续增加 `MinoPresentationTests`：节点快照与窗口行为。
- 后续增加 App 级测试：启动、菜单、跨屏和休眠恢复。

## 下一阶段入口

1. 建立用于签名、Asset Catalog、权限和发行配置的 Xcode App 工程，继续复用现有 SwiftPM 模块。
2. 定义账号、情侣关系与宠物档案领域模型。
3. 用 Keychain 实现 `AccessTokenProvider`，并加入刷新令牌状态机。
4. 增加本地持久化与迁移策略，然后实现离线队列。
5. 服务端契约稳定后生成或验证 OpenAPI 客户端，但保持领域层不依赖生成代码。
