# Mino Design Tokens

本文档是 Mino macOS 产品界面的单一视觉规范。界面 token 对应
`Sources/MinoPresentation/MinoDesignTokens.swift`，角色 token 对应
`Sources/MinoDomain/PetCharacterModels.swift`、
`Sources/MinoPresentation/PetFrameAnimationCatalog.swift` 与本文件；页面和组件不得在各自文件中新增随意的 RGB、字号、圆角、间距或角色采样策略。

## 设计方向

Mino 的界面是“温暖纸感的原生 macOS 社交空间”，而不是网页后台，也不是厚重的儿童化黏土 UI。

- **安静但有性格**：大面积暖灰纸色承载内容，珊瑚色只用于品牌、主操作和关键状态。
- **宠物优先、工具退后**：好友、事件和宠物资料是产品内容；服务器地址、API 版本和超时属于开发配置，不进入用户界面。
- **macOS 原生**：使用系统字体和 SF Symbols，保留键盘、焦点、菜单和窗口行为；不引入网页式超宽表单。
- **本地即时**：网络状态作为辅助说明，不阻塞桌宠本地反馈。

## 颜色

所有颜色都是语义角色，并同时定义浅色与深色值。

| Token | Light | Dark | 用途 |
|---|---:|---:|---|
| `minoCanvas` | `#FBF7F2` | `#1D1816` | 页面底色 |
| `minoSidebar` | `#F3EBE3` | `#241E1B` | 导航侧栏 |
| `minoSurface` | `#FFFDFC` | `#2B2420` | 卡片、表单分组 |
| `minoSurfaceRaised` | `#FFFFFF` | `#342A26` | 悬浮与强调表面 |
| `minoInk` | `#302824` | `#F7F0EB` | 主文字、图标 |
| `minoMuted` | `#6D625C` | `#C5B8B0` | 辅助文字 |
| `minoFaint` | `#948983` | `#9F928B` | 时间、占位说明 |
| `minoCoral` | `#E8545B` | `#FF7C82` | 品牌、主按钮、选中态 |
| `minoCoralPressed` | `#CD424A` | `#E9646B` | 主按钮按下态 |
| `minoCoralSoft` | `#FBE7E5` | `#48292B` | 选中背景、品牌弱表面 |
| `minoMint` | `#197A68` | `#58C9AE` | 成功、在线、已同步 |
| `minoMintSoft` | `#E4F3EE` | `#203D36` | 成功弱表面 |
| `minoWarning` | `#A96713` | `#F0B861` | 等待和提醒 |
| `minoDanger` | `#B83E45` | `#FF8589` | 错误、危险操作 |
| `minoLine` | `#DED4CC` | `#493E38` | 边框与分隔线 |
| `minoFocus` | `#B8333C` | `#FF9BA0` | 键盘焦点环 |

规则：状态不能只依赖颜色，必须同时有 SF Symbol 或文字；正文对比度目标为 WCAG AA 4.5:1。

### 官方角色配色

角色配色是角色资产协议的一部分，不能由页面主题色、系统 tint 或好友关系动态改写。两只角色都采用 Moonlab 角色的正面一体式软团轮廓：没有独立圆头、脖子、椭圆嘴套或分体四腿；白狗依靠蓬松碎边辨识，黄狗依靠平滑轮廓、浅米黄、外张圆耳和固定珊瑚项圈辨识。

| Token | 白色马尔济斯 | 黄色小金毛 | 用途 |
|---|---:|---:|---|
| `petBody` | `#FFFEFA` | `#F0D6AB` | 一体式主体毛色 |
| `petEar` | `#FFFEFA` | `#F0D6AB` | 耳朵必须与身体同色 |
| `petMuzzle` | `#FFFDF7` | `#F7E0B3` | 仅供动作道具或兼容姿势，不绘制独立嘴套 |
| `petInk` | `#141414` | `#302929` | 轮廓、点眼、小鼻和 T/ω 嘴 |
| `petBlush` | `#FF7A80 / 42%` | `#FF7573 / 36%` | 仅限需要的情绪关键姿势，idle 不显示 |
| `petAccent` | `#FF5C61` | `#FF6166` | 黄狗固定项圈，以及舌头、爱心、花朵等经审批的语义元素 |

白色角色用近白填充配合固定深色轮廓，在浅色窗口和透明桌面上保持边界；黄色角色不能使用界面 warning 色或高饱和金黄代替浅米黄。角色轮廓在浅色、深色、透明窗口和不同桌面壁纸上始终使用自身 `petInk`。

## 排版

只使用系统字体，中文和拉丁字符共享同一原生排版指标。

| Token | 规格 | 用途 |
|---|---|---|
| `brand` | Rounded Heavy 28 | Mino 品牌字标 |
| `pageTitle` | Rounded Bold 28 | 页面一级标题 |
| `pageSubtitle` | Regular 13 | 页面说明 |
| `sectionTitle` | Bold 16 | 卡片标题 |
| `body` | Regular 13 | 正文 |
| `bodyStrong` | Semibold 13 | 行标题与主要值 |
| `label` | Semibold 12 | 表单标签、状态标签 |
| `caption` | Regular 11 | 时间和补充说明 |
| `code` | Monospaced Bold 16 | GitHub Device Flow 匹配码 |

正文避免超过约 70 个中文字符的阅读宽度。输入框必须有常驻标签，placeholder 不能代替标签。

## 间距与尺寸

- 间距采用 4pt 基线：`4 / 8 / 12 / 16 / 24 / 32 / 40 / 48`。
- 侧栏固定宽度 `224pt`；正文最大宽度 `720pt`；资料表单最大宽度 `560pt`。
- 普通控件高度 `40pt`，主操作高度 `44pt`；图标使用 `14 / 17 / 22pt`。
- 页面外边距在普通窗口为 `48pt`，小窗口不得低于 `32pt`。
- 桌宠贴身操作条固定 `252 × 42pt`，气泡最大 `224 × 58pt`，均限制在当前屏幕可见区域内。

### 角色帧画布与采样

- 两只角色统一使用 `120 × 120` 逻辑画布，脚底锚点为 `(60, 102)`；头像、桌宠、邀请和空状态只能等比缩放整套画布，不能对单只角色单独裁切或补偿位置。
- 轮廓、五官和语义特效都烘焙在经审批的透明 PNG 帧中；运行时不得重描线、主题着色、生成嘴套或用程序化形状补齐缺帧。
- 每帧的 sprite rect 固定为完整画布；帧播放器只能替换纹理，不能读取 alpha bounds 后重新裁切、居中或改变节点尺寸。
- 镜像只作用于 `bodyContainer`；`worldAnchor`、影子、气泡、文字和语义图标不得镜像。
- SpriteKit 使用 `.nearest`，SwiftUI 使用 `.interpolation(.none)`；角色可见内容必须留在画布安全边界内，新增姿势不得靠裁剪或线性采样隐藏触边问题。

## 圆角、边框与阴影

| Token | 值 | 用途 |
|---|---:|---|
| `control` | 10 | 输入框、小按钮 |
| `card` | 16 | 内容卡片 |
| `prominent` | 20 | 空状态等大容器 |
| `capsule` | 999 | 状态标签 |
| `petAccessory` | 14 | 桌宠悬停操作条 |
| `speechBubble` | 18 | 最多两行的即时回应气泡 |

卡片使用 `1pt minoLine` 边框与低透明度、`radius 12 / y 4` 的单层阴影。禁止多层高光、强玻璃模糊和随机投影。

## 组件

### 导航

- 一级导航只有“好友”和“事件线”，图标与文字同时出现。
- 当前页用 `minoCoralSoft` 表面、`minoCoral` 图标和较粗文字表示。
- 左下角身份块进入个人页；整行可点击，最小高度 64pt，并保留 `contentShape` 与正确层级，避免内容页覆盖点击区域。

### 卡片

- 账号状态、资料表单、好友行与事件内容都使用同一 `minoCard` 表面语法。
- 一个卡片只表达一个主题；一个页面只保留一个主要 CTA。
- 只读信息使用普通文字行，不伪装成禁用输入框。

### 表单

- 标签位于输入框上方，标签与控件间距 8pt。
- 错误显示在相关分组内部，包含原因和恢复动作。
- 保存期间禁用主按钮并显示 ProgressView；成功与失败反馈使用图标加文字。
- 账号 ID 是可复制的只读值；服务器地址永远不作为用户输入项。

### 按钮

- 主按钮：珊瑚色填充、白色文字，每屏最多一个。
- 次按钮：表面填充或边框，不与主按钮争夺注意力。
- 文本按钮：用于取消、返回和退出；危险操作使用 `minoDanger`。
- hover/press 只改变颜色或透明度，不改变布局尺寸；过渡时间 `160–240ms`。

### 桌宠即时互动

- 单击桌宠等同“摸摸”，不弹窗、不等待网络；气泡默认显示 `2.4s`，最多两行。
- 悬停 `200ms` 后显示贴身操作条，固定四个入口：投喂、陪玩、散步、更多；前三项与右键菜单调用完全相同的 action boundary。
- 指针从宠物移入贴身操作条时必须保持显示；只有同时离开宠物和操作条 `180ms` 后才隐藏。“更多”菜单展开期间不得自动消失。
- 贴身操作条不是唯一入口：右键菜单和菜单栏“宠物操作”子菜单提供完整的键盘与 VoiceOver 等价路径。
- 自己的“更多”包含查看状态、休息、请求串门；来访宠物包含贴贴、送花、托付文字信、让它回家。
- 气泡使用 `minoSurfaceRaised` / popover material、`speechBubble` 圆角和正文色，不使用大面积品牌填充。
- 反馈通过统一固定画布像素帧切换动作和表情；Reduce Motion 下取消逐帧播放、位移、跳跃、缩放和旋转，只显示对应 clip 声明的静态帧与淡入淡出。

### 官方双角色系统

- `PetCharacterID` 只有 `malteseWhite` 与 `retrieverYellow`。全产品必须通过同一 `PetFrameAnimationCatalog` 读取角色帧；SwiftUI 的 `PetCharacterView` 与 SpriteKit 桌宠只能是同一帧目录的两个消费者，禁止各自重画角色，也禁止再显示旧像素猫、像素兔、3D 兔子或默认矢量替身。
- 好友头像、个人页、串门邀请、陪伴页、空状态、桌宠和应用图标必须保持同一角色身份。占位状态可使用相同角色的 `idle` 静态姿势，不得回退到旧素材。
- `AvatarRecipe` 仅用于读取旧本地数据并映射迁移，不是新的视觉接口。页面代码不得根据“自己/访客”自行分配角色。
- 角色选择只在首次注册或旧账号升级时出现一次。选择界面同时展示两只角色、名称与“选定后不能更换”的说明；个人页只读展示已选角色，不提供伪装成可用的切换入口。

公开视觉参考仅来自以下授权方官方入口：

- [Moonlab Studio 官方入口](https://linktr.ee/moonlab_studio)
- [LINE 官方商品页](https://store.line.me/themeshop/product/36a8914b-b9cf-4b8e-8d61-e5e572124440/en)
- [官方游戏页面](https://store.steampowered.com/app/3404470/Malteses_Fluffy_Onsen/)

网页位图只能用于造型核对，不能直接下载、裁切、转码或随应用打包。产品中的透明 PNG 像素帧必须从授权交付物或经授权方确认的独立制作源导出，并保留可追溯的审批版本；公开网页截图不得成为帧资产源。若授权合同要求逐稿审批，角色造型、动作、应用图标及营销画面完成授权方视觉审批前不得进入生产发布。

### 固定画布像素帧

- 资源根目录固定为 `Resources/PetFrames/<character.rawValue>/<clip.rawValue>/frame-NNN.png`。角色目录使用 `maltese-white`、`retriever-yellow`，clip 目录严格使用 `PetMotionClipID.rawValue`，帧号从 `frame-000.png` 开始连续递增，不允许缺号、别名或通用 `gift` 目录。
- 每一帧必须是 `120 × 120`、透明背景的 RGBA PNG。禁止按内容裁边、atlas trim、逐帧改变 padding、在帧外追加阴影，或用不同尺寸图片混在同一个 clip；透明画布本身就是稳定坐标系。
- 源图片坐标以左上为原点，脚底锚点固定为 `(60, 102)`。同一角色以及两个角色的所有帧都必须共享该画布和脚底线；姿势可以改变，但站立脚底和影子不能因 alpha bounds 改变而漂移。
- 每个 clip 的 manifest 必须声明有序帧、`framesPerSecond`、是否循环和 `reduceMotionFrameIndex`；catalog 再据此计算 `frameDuration`。静态帧索引必须落在该 clip 自己的帧序列内，不能统一借用 `idle`，从而保留“拒绝、送花、贴贴、收信”等语义。
- SpriteKit 纹理必须使用 `.nearest`，SwiftUI 图像必须使用无插值采样。角色在 1x/2x 屏幕上按整数物理像素倍率呈现；窗口最终原点继续按目标屏幕 `backingScaleFactor` 量化，禁止用线性采样掩盖帧间错位。
- 默认产品渲染器只能读取上述 PNG 帧。矢量路径、程序化形状和旧 atlas 可以保留为迁移或开发诊断代码，但不得成为缺帧时的静默默认降级；缺帧必须被构建测试阻止。
- 每帧的非透明内容不得触碰画布边缘。阴影属于桌面节点的稳定兄弟节点，不烘焙进角色帧；好友头像、个人页、邀请和空状态默认使用该角色 `idle` 的 Reduce Motion 静态帧。

### 动作 Clip 与降级

`PetMotionClipID` 的完整目录如下；两个角色必须等量实现，禁止用一个笼统的 `gift` 代替不同语义：

| 语义 | Clip |
|---|---|
| 基础 | `idle`, `walk`, `pet_receive`, `eat`, `play`, `sleep`, `shy`, `happy` |
| 拒绝 | `tired_refuse`, `full_refuse` |
| 双方互动 | `cuddle_give`, `cuddle_receive`, `flower_give`, `flower_receive` |
| 社交与访问 | `letter_give`, `wave`, `welcome` |

- `PetMotionResolver` 是活动、情绪、互动结果、giver/receiver 角色和串门阶段到 clip 的唯一映射点。情绪变化若没有改变实际 clip，不得重启动画。
- `PetReactionPlan.duration` 是非循环动作的时长事实来源；渲染层不得统一截断为固定时长。
- 资产检查必须保证每只角色覆盖全部 clip、帧号连续、PNG 尺寸和透明通道有效、画布与脚底锚点统一、Reduce Motion 索引合法。发布构建不允许缺帧；开发构建若仍遇到损坏资源，必须显式记录资产错误并停止该动作，不能回退到矢量替身或语义不符的 clip。
- 串门编舞固定为 `walk-in → face companion → welcome`；贴贴和送花分别播放 giver/receiver；结束固定为 `wave → walk-out`。

### 稳定运动与 Reduce Motion

- 节点层级固定为 `worldAnchor → shadow + bodyContainer → characterSprite/effects`。世界移动只能改变 `worldAnchor`；clip 只能替换 `characterSprite.texture`，脚底、影子、sprite 尺寸和容器原点不能随帧变化。
- `walk` 的每帧仍使用完整 `120 × 120` 画布，角色脚底线固定；禁止用逐帧裁切框制造整体上下跳，禁止非整数整体缩放，也禁止角色渲染器与窗口同时拥有位移。
- 移动和交互期间由 macOS 14 `CADisplayLink` 以目标 60Hz 推进世界位置与姿势。到达且无活动动作后停止 display link；低频 `idle` 由独立节拍驱动，不保持持续 60Hz 唤醒。
- 窗口最终位置必须根据目标屏幕的 `backingScaleFactor` 量化到物理像素；位置比较和 `setFrameOrigin` 使用同一个量化值。跨屏时使用目标屏幕比例，停止与转向跳变不得超过一个物理像素。
- Reduce Motion 为每个 clip 读取 manifest 指定的独立静态帧，只允许淡入淡出；禁止推进帧序列、走位、弹跳、缩放或旋转。串门到达和离开仍更新业务状态，但视觉上用静态帧与透明度完成。

### 养成状态

- 自己的四项状态使用 `2 × 2` 紧凑网格：常驻名称、SF Symbol、精确整数、8pt 进度条与定性说明。
- 好友及来访宠物永远只显示三级文字，不显示进度条或精确数值；熟悉度使用“初见、眼熟、熟悉、亲近”。
- 云端状态统一为 `localOnly / connecting / synced / pending / unavailable`。未登录只能显示“仅保存在此 Mac”，成功 bootstrap 或收到权威回执后才能显示“已同步”。
- 乐观状态和权威状态校正不制造 toast；只有 outbox 待发送时显示 `arrow.triangle.2.circlepath + 稍后同步`，云端不可用时保留缓存并提供重试。
- 饱腹用珊瑚、精力用 warning、心情用 mint、亲密用珊瑚；颜色之外必须保留图标和文字。

### 串门邀请

- 好友行的“串门”是方向菜单，文案必须明确为“邀请 TA 来我桌面”与“让我的 Mino 去 TA 家”。
- 收到邀请使用独立的全局顶部横幅，而不是依赖主窗口内部状态；主窗口关闭时仍可见，且不抢走当前应用焦点。
- 横幅按方向说明“好友宠物来我的桌面”或“我的 Mino 去好友家”，同时显示来源、宠物名、接受与拒绝；多个待处理邀请按创建时间排队。
- 接受后先播放走入与欢迎气泡；结束前先播放走出与告别，再移除来访窗口。

## 页面结构

- **好友**：页头操作 → 待处理申请 → 已发出申请 → 好友列表/空状态。
- **事件线**：页头 → 单列时间线；不使用卡片瀑布流。
- **好友详情**：返回与串门操作置于页头，好友事件沿用同一时间线组件。
- **个人页**：账号状态卡 → 今日状态卡 → 个人资料卡。生产服务固定连接 `https://api.mino.pet`，不显示可编辑服务器设置。

## 可访问性与状态

- 所有图标按钮提供 `accessibilityLabel` 和 tooltip。
- 选中、成功、等待、失败均使用“颜色 + 图标 + 文字”。
- 所有关键操作可通过键盘到达；表单支持默认/取消快捷键。
- 使用系统 Reduce Motion 时不添加装饰动画；加载状态不改变整体布局。
- 深浅色分别验证文字、边框、焦点和 disabled 状态，不能只依赖浅色截图推断。

## 禁止项

- 不在页面中直接写 RGB/hex、随机字号、随机圆角或随机间距。
- 不把服务器地址、API 版本、超时、测试连接、重启生效暴露给最终用户。
- 不用 placeholder 代替表单标签，不使用无边界的超宽输入框。
- 不用 emoji 作为结构图标，不混用不同粗细与填充语言的图标。
- 不用 Drawer 承载资料编辑；个人资料保持在稳定页面中。
