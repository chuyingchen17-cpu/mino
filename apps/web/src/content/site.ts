/**
 * Mino 产品页内容源。
 *
 * 所有文案与数据都来自仓库真实事实：README.md、PRODUCT.md、Docs/、Scripts/install.sh、
 * PetFrames/manifest.json。不要在这里编造用户评价、下载量、定价或未实现的能力。
 * 组件只负责表现，不在模板里写死文案。
 */

export const site = {
  name: 'Mino',
  url: 'https://mino.pet',
  repo: 'https://github.com/liyown/mino',
  /** 一句话产品定义，用于 Hero 与 meta description 的共同基底。 */
  tagline: '住在菜单栏里的 macOS 桌宠，每个账号一只',
  description:
    '原生 macOS 个人桌宠。摸摸、投喂、陪玩、散步在本机即时播放动画，不调用模型；云端只保存身份、好友、养成和串门。',
  locale: 'zh-Hans',
} as const;

export const requirements = {
  os: 'macOS 14+',
  chip: 'Apple 芯片',
  note: '不需要开发者账号',
} as const;

export const nav = [
  { label: '安装', href: '#install' },
  { label: '本地反馈', href: '#local-first' },
  { label: '角色', href: '#characters' },
  { label: '串门', href: '#visit' },
  { label: '隐私', href: '#letters' },
  { label: '工作方式', href: '#architecture' },
] as const;

export const hero = {
  eyebrow: '原生 macOS 桌宠',
  /** 不是抽象 slogan：说清是什么、给谁、归属于谁。 */
  heading: '住在菜单栏里的桌宠，每个账号一只',
  /**
   * 中文标题交给浏览器自动换行会拆开词（如“桌/宠”），
   * 因此显示时按语义手动分行；heading 仍用于 meta 与结构化数据。
   */
  headingLines: ['住在菜单栏里的桌宠，', '每个账号一只'],
  body: '没有 Dock 图标。形象、养成和个人事件线跟着账号走，不是某段关系里的装饰。摸摸、投喂、陪玩、散步会马上有动画和状态，这些互动在本机完成，不调用模型。',
  primaryCta: { label: '复制安装命令', href: '#install' },
  secondaryCta: { label: '在 GitHub 上查看', href: site.repo },
  /** Hero 视觉用真实产品帧，不用渲染图。 */
  visual: { character: 'maltese-white', clip: 'idle' },
} as const;

export const install = {
  heading: '一行命令装好',
  body: `${requirements.os}，${requirements.chip}。${requirements.note}。`,
  primary: {
    variant: 'nightly',
    label: '安装 nightly',
    command:
      'curl -fsSL https://raw.githubusercontent.com/liyown/mino/main/Scripts/install.sh | zsh',
    note: '脚本下载 CI 的 unsigned nightly，校验 SHA-256，装到 ~/Applications/Mino.app 并启动。',
  },
  tag: {
    variant: 'tag',
    label: '指定正式 tag',
    command:
      'curl -fsSL https://raw.githubusercontent.com/liyown/mino/main/Scripts/install.sh | MINO_INSTALL_RELEASE=v0.1.0 zsh',
  },
  source: {
    variant: 'source',
    label: '从源码安装',
    command: 'Scripts/install-app.sh --release --open',
    note: '仓库还没有 Release 时用这条。',
  },
  /** 诚实披露，必须显示在安装区内，不能折叠隐藏。 */
  disclosures: [
    '这是 ad-hoc 包，不是 Developer ID 签名的发行版。',
    '系统提示无法验证开发者时，按住 Control 单击 ~/Applications/Mino.app，再选打开。',
    '同一份 app 再打开会保留登录；换一个构建需要重新登录。',
  ],
  nightlyReleaseUrl: `${site.repo}/releases/tag/nightly`,
  releasesUrl: `${site.repo}/releases`,
} as const;

/**
 * 本地即时反馈演示。clip 必须是 PetFrames/manifest.json 里真实存在的 id。
 * fps 与 loops 取自 manifest，播放器不得自行拉伸时长。
 */
export const localFirst = {
  heading: '桌宠不等网络返回才动',
  body: '基础互动在本机完成。云端只保存身份、好友、养成和串门事实，网络用来同步这些事实。',
  demos: [
    { label: '摸摸', detail: '单击桌宠等同摸摸，不弹窗、不等网络', clip: 'pet_receive', fps: 12 },
    { label: '投喂', detail: '悬停 200ms 后出现贴身操作条的第一项', clip: 'eat', fps: 12 },
    { label: '陪玩', detail: '动作与右键菜单调用同一 action boundary', clip: 'play', fps: 16 },
    { label: '散步', detail: '脚底线固定，位移只发生在世界锚点上', clip: 'walk', fps: 16 },
  ],
  details: [
    '气泡默认显示 2.4 秒，最多两行。',
    '贴身操作条固定四个入口：投喂、陪玩、散步、更多。',
    '右键菜单和菜单栏"宠物操作"子菜单提供完整的键盘与 VoiceOver 等价路径。',
    '待发送的动作进持久 outbox，离线时显示"稍后同步"，恢复后自行对账。',
  ],
} as const;

export const characters = {
  heading: '两只官方角色',
  body: '角色选择只在首次注册或旧账号升级时出现一次。好友头像、个人页、串门邀请、陪伴页和桌宠始终是同一个角色身份。',
  /** 选定后不能更换是真实约束，写在页面上而不是等用户注册后才发现。 */
  constraint: '选定后不能更换。',
  items: [
    {
      id: 'maltese-white',
      name: '白色马尔济斯',
      detail: '近白填充配合固定深色轮廓，靠蓬松碎边辨识，在浅色窗口和透明桌面上都保持边界。',
    },
    {
      id: 'retriever-yellow',
      name: '黄色小金毛',
      detail: '平滑轮廓、浅米黄、外张圆耳，固定珊瑚项圈。',
    },
  ],
  /** 17 个 clip 两只角色等量实现，来自 manifest.json。 */
  clipCount: 17,
  clipGroups: [
    { label: '基础', clips: ['idle', 'walk', 'pet_receive', 'eat', 'play', 'sleep', 'shy', 'happy'] },
    { label: '拒绝', clips: ['tired_refuse', 'full_refuse'] },
    { label: '双方互动', clips: ['cuddle_give', 'cuddle_receive', 'flower_give', 'flower_receive'] },
    { label: '社交与访问', clips: ['letter_give', 'wave', 'welcome'] },
  ],
} as const;

export const growth = {
  heading: '养成状态只对自己精确',
  body: '自己看到四项精确数值和进度条；好友和来访宠物永远只显示三级文字，不显示进度条或数值。',
  own: [
    { label: '饱腹', tone: 'coral' },
    { label: '精力', tone: 'warning' },
    { label: '心情', tone: 'mint' },
    { label: '亲密', tone: 'coral' },
  ],
  familiarity: ['初见', '眼熟', '熟悉', '亲近'],
  syncStates: ['localOnly', 'connecting', 'synced', 'pending', 'unavailable'],
  syncNote: '未登录只显示"仅保存在此 Mac"；成功 bootstrap 或收到权威回执后才显示"已同步"。',
} as const;

export const visit = {
  heading: '串门',
  body: '只有已接受的好友才能邀请、登门、互动或托信。方向由发起方推导出唯一 responder，服务端不代答真人动作。',
  /** 邀请文案必须与 App 内一致，不能在营销页另编一套。 */
  directions: [
    { label: '邀请 TA 来我桌面', detail: '好友宠物出现在我的桌面上' },
    { label: '让我的 Mino 去 TA 家', detail: '我的宠物在原端隐藏，出现在好友端' },
  ],
  choreography: ['walk-in', 'face companion', 'welcome', '…', 'wave', 'walk-out'],
  interactions: ['投喂', '陪玩', '摸摸', '贴贴', '亲亲', '送花', '散步', '托信'],
  details: [
    '收到邀请用独立的全局顶部横幅，主窗口关闭时仍可见，且不抢走当前应用焦点。',
    '真人动作需要访客原端 Agent 回复，Worker 不会在客户端离线时伪造宠物回应。',
    '离线 Agent 的待处理互动通过事件和 bootstrap 恢复。',
    '个人事件线聚合所有好友的重要事件，不显示虚构的串门持续时长。',
  ],
  docHref: `${site.repo}/blob/main/Docs/VisitProtocol.md`,
} as const;

export const letters = {
  heading: '托出去的信是密封的',
  body: '文字信在 active Visit 中附着，Visit 结束时只交付一次。',
  guarantees: [
    '正文不进入事件线、日志、幂等回执、Agent observation 或模型上下文。',
    '只有授权的真人界面可以读取正文。',
    '屏幕坐标、动画状态和本地 Agent 长期记忆不上传为服务端事实。',
    '以后的智能回应不能改养成数值、串门权限，也不能读信。',
  ],
  /** 不含糊其辞：明确说明不是 E2EE。 */
  caveat: '文字信在传输和存储时加密，但不是端到端加密。',
} as const;

export const architecture = {
  heading: '工作方式',
  body: '客户端始终用事件游标和 bootstrap 对账，不把 WebSocket 当成事实来源。',
  diagram: `macOS 客户端 ── HTTPS / WSS ── Cloudflare Worker
  本地动画与回应                 身份、好友、养成、串门
  持久 outbox                    D1 保存事实
                                 WebSocket 只提示有新事件`,
  facts: [
    { label: '客户端', value: 'Swift 6.2+，SwiftUI 与 SpriteKit 共用同一帧目录' },
    { label: '后端', value: 'Cloudflare Worker + Hono + D1' },
    { label: '实时提示', value: 'account-scoped Durable Object，不保存业务事实' },
    { label: '登录', value: 'GitHub Device Flow' },
    { label: '生产服务', value: 'https://api.mino.pet' },
  ],
  openapiHref: `${site.repo}/blob/main/apps/worker/openapi.yaml`,
} as const;

export const accessibility = {
  heading: '无障碍',
  items: [
    '好友、Visit、离线和同步状态不只依赖颜色，同时有 SF Symbol 或文字。',
    '主要操作有明确文字、键盘焦点和 VoiceOver 标签。',
    '开启系统 Reduce Motion 时按 clip 显示指定静态帧，只保留淡入淡出，不推进帧序列、走位或缩放。',
    '正文对比度目标为 WCAG AA 4.5:1，深浅色分别验证。',
  ],
} as const;

/** 主动披露未实现的能力，来自 README.md 与 PRODUCT.md 的"当前不包含"。 */
export const notIncluded = {
  heading: '当前不包含',
  body: '这些能力还没做。列在这里，免得你装完才发现。',
  items: [
    '账号搜索与推荐',
    '拉黑与举报',
    '系统推送',
    '图片明信片',
    '物品经济',
    '完整端到端加密',
    '发行签名',
    '自动更新',
  ],
  extra: 'QQ 登录待 QQ 互联开发者资质、应用和回调域名审核完成后接入。',
} as const;

export const finalCta = {
  heading: '给这台 Mac 养一只',
  body: `${requirements.os}，${requirements.chip}。`,
  primaryCta: { label: '复制安装命令', href: '#install' },
  secondaryCta: { label: '在 GitHub 上查看', href: site.repo },
} as const;

export const footer = {
  docs: [
    { label: '产品原则', doc: 'PRODUCT', href: `${site.repo}/blob/main/PRODUCT.md` },
    { label: '架构', doc: 'Architecture', href: `${site.repo}/blob/main/Docs/Architecture.md` },
    { label: '串门协议', doc: 'VisitProtocol', href: `${site.repo}/blob/main/Docs/VisitProtocol.md` },
    {
      label: '事件同步',
      doc: 'EventSynchronization',
      href: `${site.repo}/blob/main/Docs/EventSynchronization.md`,
    },
    { label: '视觉规范', doc: 'DesignTokens', href: `${site.repo}/blob/main/Docs/DesignTokens.md` },
    { label: 'OpenAPI', doc: 'openapi', href: architecture.openapiHref },
  ],
  /** Docs/DesignTokens.md 要求保留授权方官方入口声明。 */
  attribution: {
    text: '角色视觉参考来自 Moonlab Studio 官方入口。',
    href: 'https://linktr.ee/moonlab_studio',
  },
} as const;
