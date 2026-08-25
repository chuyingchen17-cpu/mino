import AppKit
import MinoDomain
import SwiftUI

package enum VisitPresentationDirection: Equatable, Sendable {
    /// A friend is offering their pet as the visitor on this Mac.
    case friendPetToMyDesktop
    /// A friend is asking the local pet to visit their desktop.
    case myPetToFriendDesktop

    package var actionLabel: String {
        switch self {
        case .friendPetToMyDesktop: "来我家"
        case .myPetToFriendDesktop: "去 TA 家"
        }
    }
}

package struct VisitInvitationPresentation: Identifiable, Equatable, Sendable {
    package let id: PetVisitID
    package let friendName: String
    package let petName: String
    package let direction: VisitPresentationDirection
    package let characterID: PetCharacterID

    package init(
        id: PetVisitID,
        friendName: String,
        petName: String,
        direction: VisitPresentationDirection,
        characterID: PetCharacterID? = nil
    ) {
        self.id = id
        self.friendName = friendName
        self.petName = petName
        self.direction = direction
        self.characterID = characterID ?? (
            direction == .friendPetToMyDesktop ? .retrieverYellow : .malteseWhite
        )
    }

    package var title: String { "收到串门邀请" }

    package var message: String {
        switch direction {
        case .friendPetToMyDesktop:
            "\(friendName) 想让 \(petName) 来你的桌面"
        case .myPetToFriendDesktop:
            "\(friendName) 邀请你的 \(petName) 去 TA 家"
        }
    }

    package var accessibilitySummary: String {
        "\(title)，\(message)"
    }
}

package enum VisitInvitationWindowLayout {
    package static let preferredSize = CGSize(width: 640, height: 150)

    package static func frame(
        contentSize: CGSize = preferredSize,
        in visibleFrame: CGRect,
        margin: CGFloat = 16,
        topInset: CGFloat = 18
    ) -> CGRect {
        let safeMargin = min(
            max(margin, 0),
            max(min(visibleFrame.width, visibleFrame.height) / 2, 0)
        )
        let availableWidth = max(visibleFrame.width - safeMargin * 2, 1)
        let availableHeight = max(visibleFrame.height - safeMargin * 2, 1)
        let width = min(max(contentSize.width, 1), availableWidth)
        let height = min(max(contentSize.height, 1), availableHeight)
        let x = min(
            max(visibleFrame.midX - width / 2, visibleFrame.minX + safeMargin),
            visibleFrame.maxX - safeMargin - width
        )
        let requestedY = visibleFrame.maxY - max(topInset, safeMargin) - height
        let y = min(
            max(requestedY, visibleFrame.minY + safeMargin),
            visibleFrame.maxY - safeMargin - height
        )
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
package final class VisitInvitationWindowController: NSWindowController {
    package typealias ResponseHandler = (
        VisitInvitationPresentation,
        VisitResponse
    ) -> Void

    private let model = VisitInvitationBannerModel()
    private let visibleFrameProvider: @MainActor () -> CGRect
    private let reduceMotionProvider: @MainActor () -> Bool
    private let onResponse: ResponseHandler
    private var invitations: [VisitInvitationPresentation] = []
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?
    private var presentationGeneration = 0

    package init(
        visibleFrameProvider: @escaping @MainActor () -> CGRect = VisitInvitationWindowController.activeVisibleFrame,
        reduceMotionProvider: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        onResponse: @escaping ResponseHandler
    ) {
        self.visibleFrameProvider = visibleFrameProvider
        self.reduceMotionProvider = reduceMotionProvider
        self.onResponse = onResponse

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: VisitInvitationWindowLayout.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        let rootView = VisitInvitationBannerView(model: model) { [weak self] response in
            self?.submit(response)
        }
        let hostingView = VisitInvitationFirstMouseHostingView(rootView: rootView)
        hostingView.frame = panel.contentView?.bounds
            ?? CGRect(origin: .zero, size: VisitInvitationWindowLayout.preferredSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.title = "Mino 串门邀请"
        panel.setAccessibilityLabel(panel.title)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.positionPanel()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Reconciles the banner queue with the server-authoritative pending visits.
    /// The first item is shown; the rest are represented by the remaining count.
    package func replaceQueue(_ invitations: [VisitInvitationPresentation]) {
        var seen: Set<PetVisitID> = []
        let deduplicated = invitations.filter { seen.insert($0.id).inserted }
        let previousID = model.current?.id
        self.invitations = deduplicated

        if previousID != deduplicated.first?.id {
            model.resetOperation()
        }
        refreshPresentation()
    }

    package func enqueue(_ invitation: VisitInvitationPresentation) {
        if let index = invitations.firstIndex(where: { $0.id == invitation.id }) {
            invitations[index] = invitation
        } else {
            invitations.append(invitation)
        }
        refreshPresentation()
    }

    /// Call after the response mutation is accepted or the invitation is found
    /// to be stale. The controller advances to the next pending invitation.
    package func resolve(_ invitationID: PetVisitID) {
        invitations.removeAll { $0.id == invitationID }
        if model.current?.id == invitationID {
            model.resetOperation()
        }
        refreshPresentation()
    }

    /// Keeps the current invitation actionable after a retryable response error.
    package func failResponse(
        for invitationID: PetVisitID,
        message: String
    ) {
        guard model.current?.id == invitationID else { return }
        model.operationInProgress = false
        model.pendingResponse = nil
        model.errorMessage = message
    }

    package func dismissAll() {
        invitations.removeAll()
        model.resetOperation()
        refreshPresentation()
    }

    private func submit(_ response: VisitResponse) {
        guard let current = model.current, !model.operationInProgress else { return }
        model.operationInProgress = true
        model.pendingResponse = response
        model.errorMessage = nil
        onResponse(current, response)
    }

    private func refreshPresentation() {
        model.current = invitations.first
        model.remainingCount = max(invitations.count - 1, 0)
        guard model.current != nil else {
            dismissPanel()
            return
        }
        positionPanel()
        presentPanel()
    }

    private func positionPanel() {
        guard let panel = window else { return }
        let frame = VisitInvitationWindowLayout.frame(in: visibleFrameProvider())
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func presentPanel() {
        guard let panel = window else { return }
        presentationGeneration += 1
        if panel.isVisible {
            panel.alphaValue = 1
            return
        }

        let targetFrame = panel.frame
        if reduceMotionProvider() {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        panel.setFrameOrigin(CGPoint(x: targetFrame.minX, y: targetFrame.minY + 10))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MinoDesign.Motion.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func dismissPanel() {
        guard let panel = window, panel.isVisible else { return }
        presentationGeneration += 1
        let generation = presentationGeneration
        if reduceMotionProvider() {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = MinoDesign.Motion.quick
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard
                    let self,
                    let panel,
                    self.presentationGeneration == generation,
                    self.invitations.isEmpty
                else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private static func activeVisibleFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
    }

    // Package-visible probes keep AppKit behavior verifiable without exposing
    // window internals as product API.
    package var currentInvitation: VisitInvitationPresentation? { model.current }
    package var remainingInvitationCount: Int { model.remainingCount }
    package var operationInProgress: Bool { model.operationInProgress }
    package var responseErrorMessage: String? { model.errorMessage }
    package var isBannerVisible: Bool { window?.isVisible == true }

    package func triggerResponseForTesting(_ response: VisitResponse) {
        submit(response)
    }
}

@MainActor
private final class VisitInvitationBannerModel: ObservableObject {
    @Published var current: VisitInvitationPresentation?
    @Published var remainingCount = 0
    @Published var operationInProgress = false
    @Published var pendingResponse: VisitResponse?
    @Published var errorMessage: String?

    func resetOperation() {
        operationInProgress = false
        pendingResponse = nil
        errorMessage = nil
    }
}

@MainActor
private final class VisitInvitationFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private struct VisitInvitationBannerView: View {
    @ObservedObject var model: VisitInvitationBannerModel
    let onResponse: (VisitResponse) -> Void

    var body: some View {
        Group {
            if let invitation = model.current {
                HStack(spacing: MinoDesign.Spacing.md) {
                    PetCharacterAvatar(
                        characterID: invitation.characterID,
                        petName: invitation.petName,
                        size: 48,
                        clip: .welcome
                    )

                    VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                        HStack(spacing: MinoDesign.Spacing.xs) {
                            Text(invitation.title)
                                .font(MinoDesign.Typography.bodyStrong)
                                .foregroundStyle(Color.minoInk)
                            Text(invitation.direction.actionLabel)
                                .font(MinoDesign.Typography.caption.weight(.semibold))
                                .foregroundStyle(Color.minoCoral)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.minoCoralSoft, in: Capsule())
                        }
                        Text(invitation.message)
                            .font(MinoDesign.Typography.body)
                            .foregroundStyle(Color.minoMuted)
                            .lineLimit(2)
                        if let errorMessage = model.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(MinoDesign.Typography.caption)
                                .foregroundStyle(Color.minoDanger)
                                .lineLimit(1)
                                .accessibilityLabel("处理邀请失败，\(errorMessage)")
                        } else if model.remainingCount > 0 {
                            Text("还有 \(model.remainingCount) 个邀请")
                                .font(MinoDesign.Typography.caption)
                                .foregroundStyle(Color.minoFaint)
                                .accessibilityLabel("队列中还有 \(model.remainingCount) 个串门邀请")
                        }
                    }

                    Spacer(minLength: MinoDesign.Spacing.md)

                    HStack(spacing: MinoDesign.Spacing.xs) {
                        Button {
                            onResponse(.decline)
                        } label: {
                            responseLabel("拒绝", response: .decline)
                        }
                        .buttonStyle(VisitInvitationSecondaryButtonStyle())
                        .disabled(model.operationInProgress)
                        .accessibilityLabel("拒绝这次串门邀请")

                        Button {
                            onResponse(.accept)
                        } label: {
                            responseLabel("接受", response: .accept)
                        }
                        .buttonStyle(VisitInvitationPrimaryButtonStyle())
                        .disabled(model.operationInProgress)
                        .accessibilityLabel("接受这次串门邀请")
                    }
                }
                .padding(.horizontal, MinoDesign.Spacing.lg)
                .padding(.vertical, MinoDesign.Spacing.md)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(invitation.accessibilitySummary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.minoSurfaceRaised,
            in: RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous)
                .stroke(Color.minoCoral.opacity(0.24), lineWidth: 1)
        }
        .padding(8)
    }

    @ViewBuilder
    private func responseLabel(_ title: String, response: VisitResponse) -> some View {
        HStack(spacing: 6) {
            if model.operationInProgress,
               model.pendingResponse?.rawValue == response.rawValue {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
    }
}

private struct VisitInvitationPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.7))
            .padding(.horizontal, MinoDesign.Spacing.md)
            .frame(height: MinoDesign.Size.control)
            .background(
                isEnabled
                    ? (configuration.isPressed ? Color.minoCoralPressed : Color.minoCoral)
                    : Color.minoCoral.opacity(0.42),
                in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
            )
    }
}

private struct VisitInvitationSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.minoInk.opacity(isEnabled ? 0.82 : 0.42))
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: MinoDesign.Size.control)
            .background(
                Color.minoSurface.opacity(configuration.isPressed ? 0.58 : 1),
                in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                    .stroke(Color.minoLine, lineWidth: 1)
            }
    }
}
