# Mino

Mino 是一个原生 macOS 情侣桌宠应用。仓库目前处于“生产地基 + 可运行 Demo”阶段：保留可展示的双宠物体验，同时把领域、运行时、渲染和基础设施拆成可独立测试的模块。

## 快速开始

要求：macOS 14+、Swift 6.2+。

```sh
Scripts/test.sh
Scripts/build-app.sh
open .build/Mino.app
```

使用菜单栏的 `♡` 播放完整 Demo，或单独触发亲亲、送花、散步和换装。

Release 构建：

```sh
MINO_BUILD_CONFIGURATION=release Scripts/build-app.sh
```

## 工程结构

```text
Sources/
  MinoDomain/          纯领域模型与服务协议
  MinoRuntime/         宠物世界、移动和互动状态机
  MinoPresentation/    AppKit / SpriteKit 窗口与渲染
  MinoInfrastructure/  配置、日志和后端客户端
  MinoApp/             应用入口与依赖组装
Tests/                 按模块拆分的测试
Backend/openapi.yaml   预留的 v1 后端契约
Docs/                  架构与后端接入说明
```

详细依赖规则见 [Architecture](Docs/Architecture.md)，后端约定见 [Backend Contract](Docs/BackendContract.md)。

## 后端模式

默认是 `offline`，不会发出网络请求。远端联调时使用环境变量覆盖：

```sh
MINO_BACKEND_MODE=remote \
MINO_API_BASE_URL=https://api.example.com/mino \
MINO_API_VERSION=v1 \
Scripts/build-app.sh
```

构建脚本会把以上非敏感配置写入产物的 Info.plist；直接运行可执行文件时，环境变量仍可在启动时覆盖它们。未来访问令牌必须由 Keychain 支持的 `AccessTokenProvider` 提供，不能写入仓库、Info.plist 或日志。

## 当前边界

已有：原生双窗口桌宠、组合式形象、互动状态机、离线 Demo、模块化工程、HTTP 后端适配层、CI 和签名预留。

尚未实现：正式账号/配对、Keychain 会话、服务端同步、持久化、推送或实时通道、正式素材流水线、发行与自动更新。
