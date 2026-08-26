# apps/web — Mino 产品页

根域名 `mino.pet` 的营销站。API 在 `api.mino.pet`（见 `Docs/CloudflareDeployment.md`：根域名保留给产品页），
两者在 Cloudflare 上互不影响。

技术栈按 `Landing Page 技术栈补充提示词.md` 的默认栈执行：Astro + TypeScript + Tailwind CSS 4 +
React Islands + Motion + Lucide + Content Collections + Cloudflare Workers Static Assets。
本仓库没有 Next.js，也没有需要与产品页共享的登录态或 Dashboard，因此不存在保留 Next.js 的理由。

当前目录状态：**内容与 Token 已确定，视觉模板待接入**。`src/content/site.ts` 与
`src/styles/tokens.css` 是模板无关的底座，接模板时替换的是组件层，不是内容层。

## 一、Section 列表与设计目的

页面按"用户能做的真实动作"排序，而不是按套模板顺序排。

| # | Section | 目的 | 真实素材来源 |
|---|---|---|---|
| 1 | Navbar | 导航 + 常驻安装 CTA | — |
| 2 | Hero | 一句话讲清"住在菜单栏里的桌宠，每个账号一只" | 真实 `idle` 帧动画 |
| 3 | Install | 首屏之后立刻给出真实下一步：一行命令 | `Scripts/install.sh` |
| 4 | 本地即时反馈 | 核心卖点演示：摸摸/投喂/陪玩/散步不等网络 | `pet_receive` `eat` `play` `walk` 帧 |
| 5 | 两只官方角色 | 说明角色系统与"选定后不能更换"的真实约束 | `maltese-white` / `retriever-yellow` |
| 6 | 养成状态 | 四项数值 + 好友只看三级文字的隐私差异 | `Docs/DesignTokens.md` 养成状态 |
| 7 | 串门 | 产品最独特的机制：双向邀请与编舞时序 | `Docs/VisitProtocol.md` |
| 8 | 文字信 | 隐私边界：正文不进事件线、日志、模型上下文 | `PRODUCT.md` 原则 6 |
| 9 | 工作方式 | 给开发者的架构与同步模型 | `README.md` 架构图、`Docs/EventSynchronization.md` |
| 10 | 无障碍 | Reduce Motion 与 VoiceOver 的真实承诺 | `PRODUCT.md` 无障碍 |
| 11 | 当前不包含 | 主动列出未做的能力，建立可信度 | `README.md` / `PRODUCT.md` 当前不包含 |
| 12 | Final CTA | 收口到安装命令与 GitHub | — |
| 13 | Footer | 文档、协议、Release、角色授权声明 | `Docs/`、`openapi.yaml` |

### 明确不做的 Section

按提示词第 10 条"没有实际内容就删除"：

- **Pricing** —— 产品没有定价模型，也没有付费墙。做一个假的 Free / Pro 表格就是编造。
- **Testimonials** —— 没有真实用户评价。
- **LogoCloud / Social Proof** —— 没有真实客户或媒体报道。
- **统计数字** —— 没有真实的用户数、下载数。GitHub star 数只有在接真实 API 时才展示。
- **Integrations / Use Cases** —— 目前没有第三方集成；用例等真实用户场景积累后再补。

## 二、Astro / React Island 边界

默认全部 `.astro`。只有下面两处 hydrate：

| 组件 | 指令 | 理由 |
|---|---|---|
| `InstallCommand` | `client:visible` | 剪贴板写入 + 复制成功状态 + `install_command_copy` 上报 |
| `PetClipPlayer` | `client:visible` | 逐帧播放真实 PNG 序列，需要 rAF、clip 切换与 Reduce Motion 分支 |

Hero 的 `idle` 也用 `PetClipPlayer`，但它是首屏，用 `client:load` 并只预载 `idle` 一个 clip。
Navbar 移动端菜单用 `<details>` + CSS，不 hydrate。角色切换、FAQ 折叠同样用原生元素，不进 React。

## 三、Design Token

Token 直接取 `Docs/DesignTokens.md`，与 `MinoDesignTokens.swift` 同源，落在
`src/styles/tokens.css` 的 `@theme` 里。产品页和 App 用同一套暖纸色 + 珊瑚品牌色，
不为网页另造一套配色。

- 颜色：`canvas / sidebar / surface / surfaceRaised / ink / muted / faint / coral / coralPressed / coralSoft / mint / mintSoft / warning / danger / line / focus`，浅深双值。
- 圆角：`control 10 / card 16 / prominent 20 / capsule 999`。
- 阴影：单层 `radius 12 / y 4`，禁止多层高光与玻璃拟态。
- 间距：4pt 基线 `4 / 8 / 12 / 16 / 24 / 32 / 40 / 48`。
- 排版：系统字体栈（`-apple-system` 优先，圆体用于品牌字标）。不引入 Web Font，字体数量为 0。
- 网页专属补充：`section` 纵向节奏与 `container` 最大宽度（App 的 720pt 正文宽度不适用于营销页）。

## 四、SEO

统一 `src/layouts/BaseLayout.astro` + `src/components/Seo.astro`，页面只传数据，不手写 `<head>`。

覆盖：`title` / `description` / `canonical` / Open Graph / Twitter Card / favicon / `sitemap.xml` /
`robots.txt` / JSON-LD。

JSON-LD 按页面类型：

- 首页 —— `SoftwareApplication`（`operatingSystem: macOS 14+`、`applicationCategory: UtilitiesApplication`）
  + `Organization`。`offers` 只在有真实价格时才写。
- FAQ 内容若上线 —— `FAQPage`。
- 后续 Changelog / Blog —— `Article`。

站点默认中文（`lang="zh-Hans"`），英文版留 `/en` 路由位置，暂不生成空壳页面。

## 五、Analytics

单一出口 `src/lib/analytics.ts` 的 `track(event, properties)`。组件不直接调 SDK。
底层先接 Cloudflare Web Analytics（同一 Cloudflare 账号，无 Cookie），后续可换 PostHog / Plausible / Umami。

事件：

```text
page_view
cta_click            { location, label }
install_command_copy { variant: 'nightly' | 'tag' | 'source' }
github_click         { location }
docs_click           { doc }
demo_play            { character, clip }
character_view       { character }
visit_section_view
```

`pricing_view` / `pricing_select` / `signup_click` 暂不定义——没有对应页面与动作，
留着只会产出永远为空的事件。

## 六、性能

- Hero 视觉是 240×240 的透明 PNG 帧，尺寸显式声明，`width`/`height` 固定，不会 CLS。
- 只 `preload` `idle/frame-000.png` 一帧作为首屏 LCP 元素；其余帧 `client:visible` 后按 clip 拉取。
- 帧序列走 `Scripts/` 同步到 `public/pet-frames/`，只复制页面用到的 clip，不打包全部 236 帧。
- 零 Web Font，零 UI 组件库，零 Hero 视频。
- Motion 只用于 Hero 文案入场与 Section 进入，`prefers-reduced-motion` 下全部关闭。
- Lighthouse 目标 Performance / Accessibility / Best Practices / SEO 均 ≥ 95。

## 七、文案原则

Hero 不写 "Revolutionize your workflow"。CTA 用真实动作：`复制安装命令` / `在 GitHub 上查看` /
`阅读文档` / `查看协议`，不用 `了解更多` / `探索`。

诚实项必须写进页面，不藏起来：

- nightly 是 ad-hoc 包，**不是 Developer ID 签名**；首次打开需要 Control 单击。
- 换构建版本需要重新登录。
- 文字信在传输和存储时加密，但**不是端到端加密**。
- 角色选定后不能更换。
- 当前不包含账号搜索、拉黑举报、系统推送、图片明信片、物品经济、完整 E2EE、发行签名和自动更新。

## 八、待解决问题

1. **缺真实截图**。`Design/References/shared-space-selected.png` 是旧稿（3D 兔子、"我们的空间"），
   `Docs/DesignTokens.md` 已明确禁止再展示旧像素猫、像素兔、3D 兔子。产品页不能用它，
   需要从当前 App 重新截图：好友页、事件线、个人页、桌宠贴身操作条、串门横幅。
2. **仓库没有 LICENSE 文件**。产品页若写"开源"，需要先补 LICENSE。
3. **角色授权**。`Docs/DesignTokens.md` 要求营销画面在授权方视觉审批前不得进入生产发布，
   Footer 需要保留 Moonlab Studio 授权声明，上线前确认审批状态。
4. **没有 Release**。README 说仓库还没有 Release 时要走源码安装，产品页的安装区需要
   同时给出 nightly 与源码两条路径，并在 Release 缺失时不至于给出死链。
5. **OG 图待产出**，依赖第 1 项的真实截图。

## 九、下一步

模板确定后按顺序执行：初始化 Astro 工程 → 落 `tokens.css` → 用模板样式实现 `ui/` 与
`marketing/` 组件 → 接 `site.ts` 内容 → SEO 与 analytics → 375 / 768 / 1024 / 1440 四档
响应式检查 → Lighthouse。
