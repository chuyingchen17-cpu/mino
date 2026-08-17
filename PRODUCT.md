# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Mino 面向拥有个人桌面宠物、希望宠物在自己忙碌时仍能与朋友的宠物保持联系的用户。当前实现平台是原生 macOS。

## Product Purpose

每个账号拥有自己的宠物和本地 Agent。用户添加好友后，双方宠物可以自主对话、发起串门，并把发生过的互动留在个人事件线中。成功意味着社交互动可以被感知，但用户始终拥有明确的好友边界和介入能力。

## Positioning

宠物不是固定情侣空间里的装饰，而是属于个人、能够在已授权好友网络中自主维系关系的本地 Agent；服务端负责身份、好友授权、协调和模型代理，不替离线宠物决策。

## Operating Context

- 用户主要通过 macOS 菜单栏和桌面宠物完成高频操作。
- 主窗口提供好友管理、事件线、聊天、互动和宠物形象入口。
- 好友关系建立后才能对话或串门；串门仍需要对方接受。
- 来访宠物由其原主人客户端 Agent 决策，原客户端离线时只打盹。

## Capabilities and Constraints

- 每个账号首版拥有一个个人宠物和一个 Agent 主设备。
- 服务端使用 TypeScript、Fastify、Kysely、PostgreSQL 和进程内 WebSocket，不使用 Redis。
- 账号数据以个人为边界；跨账号资源必须同时校验有效好友关系。
- 时间线记录真实事件，不显示串门持续时间。
- 文字信正文不能进入宠物 Agent 或模型上下文。
- 正式账号搜索方式、好友数量上限、拉黑与举报机制尚未决定；MVP 使用账号 ID 和开发身份完成添加好友。
- “情侣空间”“固定伴侣”“唯一对方宠物”不是产品概念。

## Brand Commitments

产品名为 Mino。界面使用简洁、亲近但工作流清晰的中文表达，保留现有宠物素材和 macOS 原生交互方式。

## Evidence on Hand

- 桌面宠物、互动状态机和菜单栏入口位于 `Sources/MinoRuntime`、`Sources/MinoPresentation` 与 `Sources/MinoApp`。
- 本地 Agent、加密记忆和模型代理位于 `Sources/MinoAgent` 与 `Backend`。
- 串门、信件、事件恢复和双客户端开发模式已有可运行实现。
- 当前没有正式注册、账号目录、拉黑举报或生产级社交图谱数据，不应虚构相关能力。

## Product Principles

1. 个人先于关系：宠物、记忆、时间线和身份首先属于账号本人。
2. 好友授权先于互动：未建立好友关系不能对话、串门或托信。
3. Agent 留在客户端：服务端协调，不在客户端离线时冒充宠物回应。
4. 互动可感知：重要社交行为进入个人事件线，但不推导虚假时长。
5. 私密内容最小传播：文字信和本地记忆不进入模型上下文。

## Accessibility & Inclusion

好友状态、请求状态和串门状态不能只依赖颜色表达；所有主要操作应提供明确文字、键盘焦点和 VoiceOver 标签。
