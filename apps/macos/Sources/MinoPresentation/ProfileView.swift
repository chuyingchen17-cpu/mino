import AppKit
import MinoDomain
import SwiftUI

struct ProfileView: View {
    let profile: CurrentProfile?
    let identity: SharedSpaceIdentity
    let careState: PetCareState
    let cloudSyncState: CloudSyncState
    let authenticationState: SharedSpaceAuthenticationState
    let githubDeviceCodeWasAutoCopied: Bool
    let authenticationOperationInProgress: Bool
    let authenticationErrorMessage: String?
    let profileOperationInProgress: Bool
    let profileErrorMessage: String?
    let profileSuccessMessage: String?
    let characterID: PetCharacterID?
    let perform: (ProfileAction) -> Void

    @State private var accountName = ""
    @State private var petName = ""
    @State private var manuallyCopiedGitHubCode: String?

    init(
        profile: CurrentProfile?,
        identity: SharedSpaceIdentity,
        careState: PetCareState,
        cloudSyncState: CloudSyncState,
        authenticationState: SharedSpaceAuthenticationState,
        githubDeviceCodeWasAutoCopied: Bool,
        authenticationOperationInProgress: Bool,
        authenticationErrorMessage: String?,
        profileOperationInProgress: Bool,
        profileErrorMessage: String?,
        profileSuccessMessage: String?,
        characterID: PetCharacterID?,
        perform: @escaping (ProfileAction) -> Void
    ) {
        self.profile = profile
        self.identity = identity
        self.careState = careState
        self.cloudSyncState = cloudSyncState
        self.authenticationState = authenticationState
        self.githubDeviceCodeWasAutoCopied = githubDeviceCodeWasAutoCopied
        self.authenticationOperationInProgress = authenticationOperationInProgress
        self.authenticationErrorMessage = authenticationErrorMessage
        self.profileOperationInProgress = profileOperationInProgress
        self.profileErrorMessage = profileErrorMessage
        self.profileSuccessMessage = profileSuccessMessage
        self.characterID = characterID
        self.perform = perform
        _accountName = State(initialValue: profile?.accountName ?? "")
        _petName = State(initialValue: profile?.petName ?? identity.localPetName)
    }

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(title: "你的 Mino", subtitle: "账号、身份和宠物资料")
            ScrollView {
                VStack(alignment: .leading, spacing: MinoDesign.Spacing.md) {
                    authenticationSection
                    careSection
                    profileSection
                }
                .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                .padding(.horizontal, MinoDesign.Spacing.xxxl)
                .padding(.bottom, MinoDesign.Spacing.xxxl)
            }
        }
        .background(Color.minoCanvas)
        .onChange(of: profile?.accountName) { _, value in
            if let value { accountName = value }
        }
        .onChange(of: profile?.petName) { _, value in
            if let value { petName = value }
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.md) {
            switch authenticationState {
            case .offline:
                accountStatus(
                    symbol: "wifi.slash",
                    tint: .minoWarning,
                    title: "账号服务暂不可用",
                    detail: "当前未连接 Mino 云服务。本机互动仍可继续，好友和事件暂时无法同步。"
                )
            case .signedOut:
                HStack(alignment: .center, spacing: MinoDesign.Spacing.md) {
                    accountStatus(
                        symbol: "person.crop.circle.badge.plus",
                        tint: .minoCoral,
                        title: "登录你的 Mino",
                        detail: "用 GitHub 建立账号，在多台 Mac 上同步好友、串门和事件线。"
                    )
                    Spacer(minLength: MinoDesign.Spacing.md)
                    Button {
                        perform(.signInWithGitHub)
                    } label: {
                        Label("使用 GitHub 登录", systemImage: "person.badge.key.fill")
                    }
                    .buttonStyle(MinoCompactButtonStyle())
                    .disabled(authenticationOperationInProgress)
                }
            case .waitingForGitHub(let userCode, let verificationURL):
                accountStatus(
                    symbol: "key.fill",
                    tint: .minoCoral,
                    title: "在 GitHub 完成授权",
                    detail: githubDeviceCodeWasAutoCopied
                        ? "完整匹配码已复制。GitHub 会把它显示成 8 格；点第一格后按 ⌘V，会一次填满。"
                        : "请复制下面的完整匹配码，再到 GitHub 点第一格并按 ⌘V，一次填满 8 格。"
                )
                HStack(spacing: MinoDesign.Spacing.sm) {
                    Text(userCode)
                        .font(MinoDesign.Typography.code)
                        .textSelection(.enabled)
                        .accessibilityLabel("GitHub 匹配码 \(userCode)")
                        .foregroundStyle(Color.minoInk)
                        .padding(.horizontal, MinoDesign.Spacing.md)
                        .frame(height: MinoDesign.Size.primaryControl)
                        .background(Color.minoCoralSoft, in: RoundedRectangle(
                            cornerRadius: MinoDesign.Radius.control,
                            style: .continuous
                        ))
                    Button {
                        if GitHubDeviceCodeClipboard.copy(userCode) {
                            manuallyCopiedGitHubCode = GitHubDeviceCodeClipboard.normalizedCode(userCode)
                        }
                    } label: {
                        Label(
                            manuallyCopiedGitHubCode == GitHubDeviceCodeClipboard.normalizedCode(userCode)
                                ? "已复制"
                                : (githubDeviceCodeWasAutoCopied ? "再次复制" : "复制匹配码"),
                            systemImage: manuallyCopiedGitHubCode == GitHubDeviceCodeClipboard.normalizedCode(userCode)
                                ? "checkmark"
                                : "doc.on.doc"
                        )
                    }
                    .buttonStyle(MinoSecondaryButtonStyle())
                    .help("复制完整 GitHub 匹配码")
                    Button {
                        NSWorkspace.shared.open(verificationURL)
                    } label: {
                        Label("打开 GitHub", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(MinoCompactButtonStyle())
                }
                Button("取消登录") {
                    perform(.cancelSignIn)
                }
                .buttonStyle(MinoTextButtonStyle())
            case .signedIn:
                HStack(alignment: .center, spacing: MinoDesign.Spacing.md) {
                    accountStatus(
                        symbol: signedInAccountStatus.symbol,
                        tint: signedInAccountStatus.tint,
                        title: signedInAccountStatus.title,
                        detail: signedInAccountStatus.detail
                    )
                    Spacer(minLength: MinoDesign.Spacing.md)
                    Button("退出登录") {
                        perform(.signOut)
                    }
                    .buttonStyle(MinoDangerTextButtonStyle())
                    .disabled(authenticationOperationInProgress)
                }
            }

            if authenticationOperationInProgress {
                ProgressView("正在连接 GitHub…")
                    .controlSize(.small)
                    .font(MinoDesign.Typography.caption)
            }
            if let authenticationErrorMessage {
                MinoFeedbackRow(
                    message: authenticationErrorMessage,
                    symbol: "exclamationmark.circle.fill",
                    tint: .minoDanger
                )
            }
        }
        .minoCard()
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("个人资料")
                    .font(MinoDesign.Typography.sectionTitle)
                    .foregroundStyle(Color.minoInk)
                Spacer()
                if let joinedDateText {
                    Text("加入于 \(joinedDateText)")
                        .font(MinoDesign.Typography.caption)
                        .foregroundStyle(Color.minoFaint)
                }
            }

            if let characterID {
                ReadOnlyPetCharacterCard(
                    characterID: characterID,
                    petName: petName.isEmpty ? identity.localPetName : petName,
                    detail: "这是你的固定角色。角色无法更换，宠物名字可以继续修改。",
                    characterSize: 88
                )
            } else {
                HStack(spacing: MinoDesign.Spacing.md) {
                    PetCharacterPairView(size: 62)
                    VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                        Text("角色尚未确认")
                            .font(MinoDesign.Typography.sectionTitle)
                            .foregroundStyle(Color.minoInk)
                        Text("GitHub 登录完成并恢复账号后，你会从两个角色中永久选择一个。")
                            .font(MinoDesign.Typography.caption)
                            .foregroundStyle(Color.minoMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(MinoDesign.Spacing.md)
                .background(Color.minoCanvas, in: RoundedRectangle(
                    cornerRadius: MinoDesign.Radius.card,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                        .stroke(Color.minoLine.opacity(0.62), lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }

            if let accountID = visibleAccountID {
                VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
                    Text("账号 ID")
                        .font(MinoDesign.Typography.label)
                        .foregroundStyle(Color.minoMuted)
                    HStack(spacing: MinoDesign.Spacing.sm) {
                        Text(accountID)
                            .font(MinoDesign.Typography.caption.monospaced())
                            .foregroundStyle(Color.minoInk)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: MinoDesign.Spacing.sm)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(accountID, forType: .string)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(MinoSecondaryButtonStyle())
                    }
                }
                .padding(MinoDesign.Spacing.sm)
                .background(Color.minoCanvas, in: RoundedRectangle(
                    cornerRadius: MinoDesign.Radius.control,
                    style: .continuous
                ))
            }

            VStack(alignment: .leading, spacing: MinoDesign.Spacing.md) {
                profileField(
                    title: "账号昵称",
                    hint: "好友会看到这个名字",
                    text: $accountName
                )
                profileField(
                    title: "宠物名字",
                    hint: "显示在桌面、好友列表和事件线中",
                    text: $petName
                )
            }
            .frame(maxWidth: MinoDesign.Size.formMax, alignment: .leading)

            HStack(spacing: MinoDesign.Spacing.sm) {
                Button {
                    perform(.saveProfile(accountName: accountName, petName: petName))
                } label: {
                    if profileOperationInProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("保存资料", systemImage: "checkmark")
                    }
                }
                .buttonStyle(MinoCompactButtonStyle())
                .disabled(profileOperationInProgress || accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let profileErrorMessage {
                MinoFeedbackRow(
                    message: profileErrorMessage,
                    symbol: "exclamationmark.circle.fill",
                    tint: .minoDanger
                )
            }
            if let profileSuccessMessage {
                MinoFeedbackRow(
                    message: profileSuccessMessage,
                    symbol: "checkmark.circle.fill",
                    tint: .minoMint
                )
            }
        }
        .minoCard()
    }

    private var careSection: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                    Text("今日状态")
                        .font(MinoDesign.Typography.sectionTitle)
                        .foregroundStyle(Color.minoInk)
                    Text(careSyncDetail)
                        .font(MinoDesign.Typography.caption)
                        .foregroundStyle(Color.minoMuted)
                }
                Spacer()
                Label(
                    cloudSyncState.statusText,
                    systemImage: cloudSyncState.systemImage
                )
                .font(MinoDesign.Typography.caption.weight(.semibold))
                .foregroundStyle(syncTint)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: MinoDesign.Spacing.md
            ) {
                CareMetric(title: "饱腹", symbol: "fork.knife", value: careState.fullness, tint: .minoCoral)
                CareMetric(title: "精力", symbol: "bolt.fill", value: careState.energy, tint: .minoWarning)
                CareMetric(title: "心情", symbol: "face.smiling.fill", value: careState.mood, tint: .minoMint)
                CareMetric(title: "亲密", symbol: "heart.fill", value: careState.bond, tint: .minoCoral)
            }
        }
        .minoCard()
    }

    private var signedInAccountStatus: (symbol: String, tint: Color, title: String, detail: String) {
        switch cloudSyncState {
        case .localOnly:
            ("macbook", .minoWarning, "当前仅保存在此 Mac", "本地互动照常可用；登录会话恢复后再同步好友和事件。")
        case .connecting:
            ("arrow.triangle.2.circlepath", .minoCoral, "正在恢复账号", "正在连接 Mino 云服务，当前显示本地状态。")
        case .synced:
            ("checkmark.seal.fill", .minoMint, "GitHub 已连接", "好友、串门与事件已同步到你的账号。")
        case .pending:
            ("clock.arrow.circlepath", .minoWarning, "GitHub 已连接", "本地更改已经生效，会在网络恢复后自动同步。")
        case .unavailable:
            ("wifi.slash", .minoDanger, "GitHub 已连接，云端暂不可用", "继续显示上次同步内容；本地互动会稍后同步。")
        }
    }

    private var syncTint: Color {
        switch cloudSyncState {
        case .localOnly, .pending: .minoWarning
        case .connecting: .minoCoral
        case .synced: .minoMint
        case .unavailable: .minoDanger
        }
    }

    private var careSyncDetail: String {
        switch cloudSyncState {
        case .localOnly: "状态只保存在这台 Mac"
        case .connecting: "正在连接云端，当前显示本地状态"
        case .synced: "互动先在本机生效，再与云端安静校正"
        case .pending: "互动已在本机生效，等待网络恢复后同步"
        case .unavailable: "云端暂不可用，当前显示本机与上次同步状态"
        }
    }

    private var visibleAccountID: String? {
        guard hasEstablishedProfile else { return nil }
        return profile?.accountID.rawValue
    }

    private var joinedDateText: String? {
        guard let profile, hasEstablishedProfile else { return nil }
        return profile.createdAt.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    private var hasEstablishedProfile: Bool {
        switch authenticationState {
        case .offline, .signedIn: true
        case .signedOut, .waitingForGitHub: false
        }
    }

    @ViewBuilder
    private func accountStatus(
        symbol: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: MinoDesign.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: MinoDesign.Size.icon, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                Text(title)
                    .font(MinoDesign.Typography.sectionTitle)
                    .foregroundStyle(Color.minoInk)
                Text(detail)
                    .font(MinoDesign.Typography.body)
                    .foregroundStyle(Color.minoMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func profileField(
        title: String,
        hint: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
            Text(title)
                .font(MinoDesign.Typography.label)
                .foregroundStyle(Color.minoInk)
            TextField(title, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            Text(hint)
                .font(MinoDesign.Typography.caption)
                .foregroundStyle(Color.minoFaint)
        }
    }
}

struct CareMetric: View {
    let title: String
    let symbol: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
            HStack(spacing: MinoDesign.Spacing.xs) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(MinoDesign.Typography.label)
                    .foregroundStyle(Color.minoInk)
                Spacer()
                Text("\(value)")
                    .font(MinoDesign.Typography.bodyStrong.monospacedDigit())
                    .foregroundStyle(Color.minoInk)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.minoLine.opacity(0.62))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                }
            }
            .frame(height: 8)
            Text(careDescription)
                .font(MinoDesign.Typography.caption)
                .foregroundStyle(Color.minoMuted)
        }
        .padding(MinoDesign.Spacing.sm)
        .background(Color.minoCanvas, in: RoundedRectangle(
            cornerRadius: MinoDesign.Radius.control,
            style: .continuous
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)，\(careDescription)")
    }

    private var careDescription: String {
        switch PetCareBand(value: value) {
        case .low: "需要照顾"
        case .steady: "状态平稳"
        case .high: "状态很好"
        }
    }
}

