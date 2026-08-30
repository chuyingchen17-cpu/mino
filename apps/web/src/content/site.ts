/**
 * Mino 产品页内容源。
 *
 * 所有文案与数据都来自仓库真实事实：README.md、PRODUCT.md、Docs/、Scripts/install.sh、
 * PetFrames/manifest.json。不要在这里编造用户评价、下载量、定价或未实现的能力。
 * 组件只负责表现，不在模板里写死文案。
 *
 * 文案只写访客能据此做判断的话。实现细节（outbox、bootstrap、responder、action boundary、
 * clip id、D1、Durable Object）一律不出现在页面上——想看这些的人会去仓库，
 * 而看落地页的人只想知道这东西装上之后是什么样。
 *
 * 语气统一为书面陈述，但不上术语：
 *   - 不用口语和语气词（「就行」「照样」「不含糊其辞」「守在电脑前」），
 *     也不用「陪着你」这类替用户表达感受的句子；
 *   - 不用行业词（端到端、事件溯源、幂等）解释产品，除非那是用户会看到的原词；
 *   - App 界面上的原词一律照抄，不改成更「书面」的说法：
 *     摸摸、投喂、陪它玩、一起散步、贴贴、送花、托付一封文字信、来我家、去 TA 家。
 *     页面和 App 说的必须是同一个词，否则用户装完对不上。
 */

/**
 * owner/name。仓库链接、文档链接和安装命令的 raw 地址全从这里派生。
 * 不要再在下面写第二份 owner/name：之前仓库链接和安装命令各写一份，换仓库时就漏了。
 */
const repoSlug = 'chuyingchen17-cpu/mino';

/** 一键安装脚本的 raw 地址。仓库为 private 时这个地址对访客是 404。 */
const installScriptUrl = `https://raw.githubusercontent.com/${repoSlug}/main/Scripts/install.sh`;

export const site = {
  name: 'Mino',
  url: 'https://mino.pet',
  repoSlug,
  repo: `https://github.com/${repoSlug}`,
  /** 一句话产品定义，用于 Hero 与 meta description 的共同基底。 */
  tagline: '常驻菜单栏的 macOS 桌宠，每个账号一只',
  description:
    '原生 macOS 桌宠。摸摸、投喂、陪玩、散步的动画在本机即时播放，不等待网络；也可以让它去好友桌面上串门，并带回一封信。',
  locale: 'zh-Hans',
} as const;

export const requirements = {
  os: 'macOS 14+',
  chip: 'Apple 芯片',
  note: '不需要开发者账号',
} as const;

/**
 * 导航只留五个内容锚点。安装已经是右边那个按钮，不在这里重复；
 * 常见问题和无障碍这类收尾内容放 Footer，不占顶部导航的位置。
 * 串门虽然占了连续三块，导航里也只给一个入口，指向第一块。
 */
export const nav = [
  { label: '演示', href: '#demo' },
  { label: '角色', href: '#characters' },
  { label: '养成', href: '#growth' },
  { label: '串门', href: '#visit' },
  { label: '隐私', href: '#privacy' },
] as const;

export const hero = {
  eyebrow: '原生 macOS 桌宠',
  /** 不是抽象 slogan：说清是什么、给谁、归属于谁。 */
  heading: '常驻菜单栏的桌宠，每个账号一只',
  /**
   * 中文标题交给浏览器自动换行会拆开词（如“桌/宠”），
   * 因此显示时按语义手动分行；heading 仍用于 meta 与结构化数据。
   */
  headingLines: ['常驻菜单栏的桌宠，', '每个账号一只'],
  /**
   * 只说两件下一屏不会重复的事：不进 Dock、宠物归属账号。
   * 「当场就有反应、不用等网络」这句从这里删掉了——Demo 区块整屏都在讲它，
   * Hero 抢着说一遍，访客滚下去只会觉得听过了。
   */
  body: '它不进 Dock，只在菜单栏保留一个图标。宠物与养成记录保存在账号上，换一台 Mac 登录仍是同一只。',
  primaryCta: { label: '复制安装命令', href: '#install' },
  secondaryCta: { label: '在 GitHub 上查看', href: site.repo },
  /** Hero 视觉用真实产品帧，不用渲染图。 */
  visual: { character: 'maltese-white', clip: 'idle' },
} as const;

/**
 * 本机即时反馈演示。clip 必须是 PetFrames/manifest.json 里真实存在的 id。
 * fps 与 loops 取自 manifest，播放器不得自行拉伸时长。
 * speech 逐字来自 MinoAgent/DeterministicInteractionResponseProvider.swift，不另编一套。
 */
export const demo = {
  heading: '每次互动都在本机即时完成',
  body: '日常互动在这台 Mac 上计算并播放，不等待服务器返回；网络中断时同样可用。',
  /** 页面上这四个演示可以直接点，播放的就是 App 里同一份帧序列。 */
  hint: '以下四项可直接试用',
  items: [
    {
      label: '摸摸',
      detail: '单击宠物即为摸摸',
      clip: 'pet_receive',
      speech: '摸摸收到啦。',
    },
    {
      label: '投喂',
      detail: '指针悬停时，操作条在宠物旁展开',
      clip: 'eat',
      speech: '好吃，认真收下啦。',
    },
    {
      label: '陪玩',
      detail: '右键菜单中同样可以发起',
      clip: 'play',
      speech: '来啦，一起动一动。',
    },
    {
      label: '散步',
      detail: '让它在桌面上走动一段',
      clip: 'walk',
      speech: '出发，去看看桌面另一边。',
    },
  ],
  details: [
    '气泡最多两行，数秒后自动收起，不遮挡工作区域。',
    '四个常用操作紧贴宠物显示：投喂、陪玩、散步、更多。',
    '键盘与右键菜单可完成同样的操作，不依赖指针。',
    '网络中断期间的操作会在本地留存，恢复连接后自动补齐。',
  ],
} as const;

/** 17 个 clip 两只角色等量实现，来自 manifest.json。页面上只写中文动作名。 */
export const characters = {
  heading: '注册时选定一只，此后不再更换',
  body: '选择只进行一次。此后你的桌宠、好友列表中的头像、以及串门时出现在对方桌面上的形象，都是这一只。',
  /** 选定后不能更换是真实约束，写在选择旁边而不是等用户注册后才发现。 */
  constraint: '选定后不能更换',
  items: [
    {
      id: 'maltese-white',
      name: '白色马尔济斯',
      detail: '近白色毛发，边缘蓬松，深色描边保证它在任何壁纸上都清晰可辨。',
    },
    {
      id: 'retriever-yellow',
      name: '黄色小金毛',
      detail: '浅米黄毛色，圆耳，佩戴一条珊瑚色项圈。',
    },
  ],
  actionCount: 17,
  actionGroups: [
    { label: '日常', actions: ['待机', '走路', '被摸', '进食', '玩', '睡觉', '害羞', '开心'] },
    { label: '拒绝', actions: ['累了', '吃饱了'] },
    { label: '好友之间', actions: ['贴贴', '被贴贴', '送花', '收花'] },
    { label: '串门', actions: ['迎接', '挥手', '送信'] },
  ],
} as const;

/**
 * PetCareBand 的真实阈值：0–34 low、35–69 steady、70+ high
 * （apps/macos/Sources/MinoDomain/PetCareModels.swift）。
 * 阈值本身不写在页面上，只用来保证两个面板的示例数据不互相矛盾。
 */
function band(value: number): 'low' | 'steady' | 'high' {
  if (value <= 34) return 'low';
  if (value <= 69) return 'steady';
  return 'high';
}

/** 好友侧的三档文字，逐字来自 App 的 FriendDetailView。 */
const publicBandText = {
  饱腹: { low: '有点饿', steady: '吃得正好', high: '肚子饱饱' },
  精力: { low: '有点累', steady: '精神还好', high: '精神很好' },
  心情: { low: '有点低落', steady: '心情平稳', high: '心情很好' },
} as const;

/**
 * 自己看到的四项。value 是页面演示用的示例数值，
 * 好友侧的三档文字从它推导，两个面板不会对不上。
 */
const ownCare = [
  { label: '饱腹', value: 72, tone: 'coral' },
  { label: '精力', value: 48, tone: 'warning' },
  { label: '心情', value: 86, tone: 'mint' },
  { label: '亲密', value: 61, tone: 'coral' },
] as const;

export const growth = {
  heading: '数值只对你可见',
  body: '饱腹、精力、心情、亲密的具体数值只出现在你自己的界面。好友查看你的宠物时，只得到一句概括描述。',
  own: ownCare,
  ownTitle: '你看到的',
  friendTitle: '好友看到的',
  /** 好友只拿到 PublicPetCareSummary 的三项。 */
  publicBands: (['饱腹', '精力', '心情'] as const).map((label) => ({
    label,
    text: publicBandText[label][band(ownCare.find((item) => item.label === label)!.value)],
  })),
  /** 亲密不在公开摘要里，好友只能从关系阶梯看到一个粗粒度的层级。 */
  hidden: { label: '亲密', note: '不对好友公开' },
  familiarityTitle: '关系逐级递进',
  familiarity: ['初见', '眼熟', '熟悉', '亲近'],
  /** statusText 逐字来自 MinoPresentation/SharedSpaceModel.swift。 */
  syncStates: [
    { id: 'localOnly', label: '仅保存在此 Mac', tone: 'warning' },
    { id: 'connecting', label: '正在同步', tone: 'neutral' },
    { id: 'synced', label: '已同步', tone: 'mint' },
    { id: 'pending', label: '稍后同步', tone: 'warning' },
    { id: 'unavailable', label: '暂时离线', tone: 'neutral' },
  ],
  syncTitle: '同步状态逐条写明',
  syncNote: '每种状态都用一句明确的话说明；只有确实写入云端后才显示“已同步”。',
} as const;

/**
 * 串门（第一块）：一次串门如何发生。
 *
 * 全部措辞与 App 内保持一致，不在营销页另造一套：
 *   - 方向标签「来我家」「去 TA 家」与邀请横幅一致
 *     （MinoPresentation/VisitInvitationWindowController.swift:13-14）
 *   - 按钮「接受」「拒绝」、标题「收到串门邀请」同上 :42,:392,:401
 *   - 邀请会排队，横幅里会显示「还有 N 个邀请」同上 :379
 * 机制事实的出处：
 *   - 24 小时未响应过期：apps/worker/src/application/visits.ts:99
 *   - 同时只能一场：apps/worker/migrations/0003_visits.sql:23-30 的部分唯一索引
 *   - 结束方式 declined/cancelled/expired/recalled/sent_home/friendship_closed：
 *     apps/worker/src/domain/visit.ts:2-8
 */
export const visit = {
  heading: '让宠物代你走一趟',
  body: '双方不必同时在线。邀请发出后一直等着，对方在方便的时候再决定接受或拒绝。',
  /** 与 App 邀请横幅同一套说法。 */
  directions: [
    { label: '来我家', detail: '邀请好友的宠物到你的桌面上做客' },
    { label: '去 TA 家', detail: '让自己的宠物离开这台 Mac，出现在好友的桌面上' },
  ],
  /**
   * 串门的真实编排来自 PetVisitMotionPhase
   * （MinoDomain/PetCharacterModels.swift:184-191）：
   * walkingIn / welcome / active / waveGoodbye / walkingOut 共五个阶段。
   * active 没有专属 clip，播的是这期间实际发生的互动，所以列成「陪着」。
   * 原来页面上那六步里的「转过身」并不是真实阶段，已去掉。
   *
   * facing 决定静帧是否水平镜像。App 就是用镜像表示朝向的
   * （PetAvatarNode.swift:103 `bodyContainer.xScale = facing == .right ? 1 : -1`，
   * PetCharacterSystem.swift:63 同理），所以「走出去」翻转一下是还原真实表现；
   * 否则第 1 步和第 5 步用的是同一张 walk 帧，看起来像走了两次同一个方向。
   */
  choreographyTitle: '一次串门经过五个阶段',
  choreography: [
    { label: '走进来', clip: 'walk', facing: 'right' },
    { label: '打招呼', clip: 'welcome', facing: 'right' },
    { label: '陪着', clip: 'play', facing: 'right' },
    { label: '挥手道别', clip: 'wave', facing: 'right' },
    { label: '走出去', clip: 'walk', facing: 'left' },
  ],
  /** 前置与边界。每条都是用户能直接感知的规则，不写实现名词。 */
  rulesTitle: '五条规则划定了它的边界',
  rules: [
    {
      label: '先成为好友，才谈串门',
      detail: '双方都同意的好友关系是前提。关系一旦关闭，正在进行和尚未答复的串门一并结束。',
    },
    {
      label: '须对方接受才成立',
      detail: '邀请可以拒绝。同时收到多个邀请会排队，横幅上写明还剩几个，逐个处理。',
    },
    {
      label: '二十四小时未响应即过期',
      detail: '邀请不会无限期挂着。超过一天没有答复，这次邀请自动作废，无需手动撤回。',
    },
    {
      label: '同时只进行一场',
      detail: '你的宠物一次只出现在一个人的桌面上，你的桌面一次也只接待一位客人。',
    },
    {
      label: '两侧都能结束',
      detail: '客人的主人可以把它召回，接待方也可以让客人回家。不存在无法结束的串门。',
    },
  ],
  /**
   * 互动分两组。
   * 通用四项在自己宠物和来访宠物身上都能做；
   * 贴贴、送花、托付文字信只在来访宠物的菜单里出现
   * （MinoPresentation/PetWindowController.swift:39-47 的两处 `if petID == .partner`）。
   * 原来页面把八项平铺成一排同色标签，这层区别丢了，而它恰好是串门的价值所在。
   * 另注：协议里还有 hug（时间线会记「接待主人抱了抱来访的小家伙」），
   * 但右键菜单没有入口，所以不写；原来那个「亲亲」在 App 里并不存在，
   * kiss 的标签就是「贴贴」。
   */
  interactionsTitle: '客人在场时，可做的事更多',
  commonActionsTitle: '日常也可进行',
  commonActions: ['摸摸', '投喂', '陪它玩', '一起散步'],
  guestOnlyTitle: '仅客人在场时出现',
  guestOnlyActions: [
    { label: '贴贴', detail: '自己宠物的菜单中没有这一项' },
    { label: '送花', detail: '同样只对来访的客人开放' },
    { label: '托付一封文字信', detail: '写给客人的主人，由它带回' },
  ],
  details: [
    '收到邀请时屏幕顶部出现横幅，主窗口关闭时同样可见，不中断当前操作。',
    /**
     * 依据 PRODUCT.md:22「真人动作需要访客原端 Agent 回复；服务端不代答」
     * 与 PRODUCT.md:11「不会在客户端离线时伪造宠物回应」。
     */
    '好友本人的动作只有在对方确实执行后才会发生，系统不会代为演示。',
    '对方设备未开机时，你做过的互动会留存，等对方上线后送达。',
    '谁来过、做了什么都记入时间线，可事后回看。',
  ],
} as const;

/**
 * 送信（第二块）。
 *
 * 方向必须写对：只有被访问的一方能写信，收件人是来访宠物的主人
 * （apps/worker/src/application/letters.ts:37 的 host 校验、:45 的 recipient）。
 * 也就是说信是「客人替它主人捎回去的」，不是「我托自己的宠物送出去」。
 * 页面原先写成后者，方向是反的。
 * 其余事实出处：
 *   - 必须依附一场进行中的串门：letters.ts:36
 *   - 串门结束时统一转为已送达：apps/worker/src/application/visits.ts:279-315
 *   - 送达之前收件人读不到（按未找到处理）：letters.ts:121-123
 *   - 正文上限 2000 字、纯文本无附件：apps/worker/src/routes/letters.ts:19
 *   - 加密保存、正文不进事件与日志：apps/worker/migrations/0006_letters.sql
 * 一处曾经写错、已改掉的断言：原来写「一次一封」，但 letters 表对 visit_id
 * 只有普通索引（0006_letters.sql 末行），visits.ts:279-299 结束时也是把这场串门下
 * 所有 attached 的信批量转为 delivered。一场串门可以托付多封，页面不能说只能一封。
 * App 内的措辞是「托付一封文字信」「宠物带回了一封信」
 * 「信封完好地随宠物回到了家，正文只对收件人可见」，页面沿用这套说法。
 */
export const letters = {
  heading: '让它带一封信回去',
  body: '好友的宠物在你桌面上做客时，你可以写一封信交给它。信随它回到家，才送达对方。',
  stepsTitle: '一封信的路径',
  steps: [
    { label: '写下正文', detail: '仅客人在场时可写，纯文本，单封上限两千字。' },
    { label: '交给客人', detail: '信随这次串门保存。此时对方只知道有信，读不到正文。' },
    { label: '它回到家', detail: '这次串门结束，信同时转为已送达。' },
    { label: '对方打开', detail: '从这一刻起才能读到正文。' },
  ],
  /** 与隐私区呼应，但这里只讲信本身，不重复整段隐私承诺。 */
  guaranteesTitle: '关于这封信',
  guarantees: [
    '正文加密保存，不写入事件记录，也不写入日志。',
    '除作者与收件人之外，无人可读。',
    '尚未实现端到端加密：服务端持有解密能力。',
  ],
} as const;

/**
 * 为什么这样设计（第三块）。
 *
 * 立意由项目所有者给定：各自忙碌的时候宠物代为往来，带回信件与互动，
 * 打开时才知道内容，因此有惊喜感。
 * 这一块不新增任何功能断言，只把前两块已经证实的机制翻译成体验上的理由。
 */
export const visitRationale = {
  heading: '延迟是设计的一部分',
  body: '串门没有做成即时通讯。两个人各自忙碌，宠物代为往来；等它回来，才知道带回了什么。',
  reasons: [
    {
      label: '不必同时在线',
      detail: '邀请可以等，互动会留存，信也不必即刻查看。谁有空谁先处理，没有人被要求立即回应。',
    },
    {
      label: '延迟本身是内容',
      detail: '信不是发出即达。它跟着宠物走完一趟才送达，打开之前不知道里面写了什么。',
    },
    {
      label: '往来需要成本',
      detail: '贴贴、送花、托付一封文字信都需要一次真实的串门。它们无法随手完成，因此值得被留意。',
    },
    {
      label: '边界始终由本人掌握',
      detail: '是否接受、何时结束、信写给谁，每一步都由本人决定，系统不代为安排。',
    },
  ],
} as const;

/**
 * 它不会做的事。
 *
 * 桌宠这个品类最大的顾虑不是「能干什么」，而是「会不会烦我、会不会偷看我」。
 * 这四条都逐条对着 apps/macos 的源码核过，不是营销话术：
 *   1. 养成数值没有随时间衰减的逻辑，也没有 Timer；
 *   2. 全项目没有 UNUserNotification / 系统通知申请；
 *   3. 全项目没有 AVAudio / NSSound / 任何音频文件；
 *   4. 全项目没有 CGEvent / CGWindowList / 屏幕捕获 / 辅助功能 API，
 *      连「主人在不在活动」这个字段都是写死的常量。
 * 任何新增一条都必须先在代码里验证得到，宁缺毋滥。
 */
export const notDoing = {
  heading: '它不会做的事',
  body: '在桌面上常驻的程序，首先要让人放心。以下四件事它不做，也不计划做。',
  items: [
    {
      title: '不会饿死',
      body: '没有随时间衰减的数值，也没有健康条。离开两周回来，它仍是原来的状态。',
    },
    {
      title: '不会催促',
      body: '不发系统通知，没有签到，也不用“它一直在等你”这类话施加压力。',
    },
    {
      title: '不会发声',
      body: '整个应用不含任何音频。会议中忘记它的存在，也不会有声音传出。',
    },
    {
      title: '不会读取屏幕',
      /** 「没有申请辅助功能权限」原在 FAQ 里，那条问答与本条重复已删除，把这句独有的披露挪来这里。 */
      body: '不读窗口标题，不截屏，不监听键盘与剪贴板，也没有申请辅助功能权限，无法判断你是否正在操作。',
    },
  ],
} as const;

/**
 * 隐私区。
 *
 * 原来分散在三处：本地反馈区讲“云端只保存事实”、密封信区讲信不进日志、
 * 工作方式区讲不上传屏幕坐标。对访客来说这是同一个问题——我的东西会被传走吗，
 * 所以合成一块回答完。
 */
export const privacy = {
  heading: '只有必要的数据会上传',
  body: '云端只保存四类内容：账号身份、好友关系、宠物的养成数值、串门记录。',
  boundaries: [
    '宠物在屏幕上的位置和当前动作不会上传。',
    '托它带走的信，只有收件人本人能读到正文。',
    '信的正文不写入日志，也不用于任何模型训练。',
    '即使后续引入更复杂的回应逻辑，它也无法修改养成数值、变更串门权限或读取信件。',
  ],
  /** 「密封」需要看得见：把正文位置留出来但不显示内容。 */
  sealedTitle: '一封已托付的信',
  sealedLabel: '有一封信',
  sealedNote: '正文只有收件人本人能读',
  /** 不含糊其辞：明确说明不是 E2EE。 */
  caveat: '信在传输和存储时都加密，但还不是端到端加密。',
} as const;

export const install = {
  heading: '一条命令完成安装',
  body: `${requirements.os}，${requirements.chip}。${requirements.note}。`,
  primary: {
    variant: 'nightly',
    label: '安装 nightly',
    command: `curl -fsSL ${installScriptUrl} | zsh`,
    note: '脚本会下载最新构建、校验哈希，安装到 ~/Applications/Mino.app 并打开。',
  },
  tag: {
    variant: 'tag',
    label: '指定正式版本',
    command: `curl -fsSL ${installScriptUrl} | MINO_INSTALL_RELEASE=v0.1.0 zsh`,
  },
  source: {
    variant: 'source',
    label: '从源码安装',
    command: 'Scripts/install-app.sh --release --open',
    note: '仓库尚无 Release 时使用这条。',
  },
  /** 诚实披露，必须显示在安装区内，不能折叠隐藏。 */
  disclosures: [
    '安装包未做 Developer ID 签名，首次打开会被系统拦截。',
    '按住 Control 单击 ~/Applications/Mino.app，选择“打开”即可继续。',
    '更新版本后需要重新登录一次。',
  ],
  nightlyReleaseUrl: `${site.repo}/releases/tag/nightly`,
  releasesUrl: `${site.repo}/releases`,
} as const;

/**
 * 常见问题。
 *
 * 这里收的是不值得在访客还在决定要不要装的时候占掉一屏、但必须能被查到的事。
 * 同时供 Seo.astro 生成 FAQPage 结构化数据。
 *
 * 只放页面别处没有答案的问题。曾经有四条问的是别处已经逐字答过的内容，
 * 已删除：机型要求和签名拦截在紧邻上方的 Install 区块（连常量都是同一个
 * requirements），角色不可更换在 Characters 区块出现了三次（标题、正文、
 * 徽标），读取屏幕在 NotDoing 的「不会读取屏幕」里。
 * 往这里加条目前先搜一遍 site.ts，重复的问答会让人以为两处说的不是一件事。
 */
export const faq = {
  heading: '其余需要知道的',
  items: [
    {
      q: '怎么登录？',
      a: '使用 GitHub 账号登录。QQ 登录需待资质与回调域名审核完成后才能接入。',
    },
    {
      q: '它会不会拖慢我的电脑？',
      a: '它常驻菜单栏，不占用 Dock。宠物只在你与它互动时播放动画，其余时间停在原处，不会自行在桌面上走动。',
    },
    {
      q: '它什么时候会联网？',
      a: '登录时、同步养成数值时，以及处理好友、串门与信件时。摸摸和投喂的反应在本地计算，不等待服务器返回。',
    },
    {
      /** notIncluded 用列表渲染：这八项平铺出来比塞进一段话里好查。 */
      q: '哪些功能还没做？',
      a: '以下能力尚未实现，列在这里以免安装后才发现：',
      list: [
        '账号搜索与推荐',
        '拉黑与举报',
        '系统推送',
        '图片明信片',
        '物品经济',
        '完整端到端加密',
        '发行签名',
        '自动更新',
      ],
    },
    {
      /** 原为两条（减弱动态效果、键盘与 VoiceOver），都属无障碍，合成一条。 */
      q: '支持无障碍操作吗？',
      a: '主要操作都有文字标签、键盘焦点与 VoiceOver 朗读，好友、串门、离线等状态不只靠颜色区分，均配有文字。开启系统的“减弱动态效果”后，宠物保持一张静态画面，仅保留淡入淡出，不再走动或缩放。',
    },
    {
      q: '技术栈是什么？',
      a: '客户端是 Swift 编写的原生 macOS 应用，服务端运行在 Cloudflare 上。源码在 GitHub 仓库中。',
    },
  ],
} as const;

export const finalCta = {
  heading: '在这台 Mac 上养一只',
  body: `${requirements.os}，${requirements.chip}。`,
  primaryCta: { label: '复制安装命令', href: '#install' },
} as const;

export const footer = {
  /**
   * 页面内锚点，不再指向 GitHub 上的 Markdown。
   * 访客要弄清这个产品是什么，不应该被赶到仓库里读文档；
   * 真要看源码，页面上的 GitHub 入口已经够了。
   */
  sections: [
    { label: '演示', href: '#demo' },
    { label: '角色', href: '#characters' },
    { label: '养成', href: '#growth' },
    { label: '串门', href: '#visit' },
    { label: '送信', href: '#letters' },
    { label: '不会做的事', href: '#not-doing' },
    { label: '隐私', href: '#privacy' },
    { label: '安装', href: '#install' },
    { label: '常见问题', href: '#faq' },
  ],
  /** Docs/DesignTokens.md 要求保留授权方官方入口声明。 */
  attribution: {
    text: '角色视觉参考来自 Moonlab Studio 官方入口。',
    href: 'https://linktr.ee/moonlab_studio',
  },
} as const;
