import AppKit
import SwiftUI

/// 桌宠说话用的气泡。
///
/// 和普通圆角卡片的区别是底边中间有一条指向桌宠的尖角尾巴，所以形状必须自己
/// 画：`NSVisualEffectView` 只能给出矩形圆角，加不了尾巴。
///
/// 尺寸由文字量决定（`size(for:)`），不再写死，短句不会留下大片空白、长句也
/// 不会被截断。尾巴的横向位置可以单独调（`tailCenterX`）——气泡贴到屏幕边缘
/// 被夹住时，气泡中心会偏离桌宠，此时仍要让尖角对准桌宠。
final class PetSpeechBubbleView: NSView {
    /// 尾巴尺寸。高度会计入气泡总高，正文只排在尾巴以上的部分。
    static let tailSize = CGSize(width: 18, height: 10)
    /// 尖角不做成刀尖，留一点圆角，放大看不会毛刺。
    static let tailTipRadius: CGFloat = 3
    static let textInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
    /// 左右两侧至少要留这么长的直边。
    ///
    /// 单行气泡主体只有 34pt 高，直接用 `Radius.speechBubble`（18）会让两边的圆角
    /// 碰头，气泡塌成胶囊形，和多行时的圆角矩形不是一个东西。
    private static let minStraightEdge: CGFloat = 6

    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// 专门用来量文字的隐藏 label。
    ///
    /// 必须和真正显示的 label 配置完全一致：`boundingRect` 算出来的宽度会比
    /// NSTextField 实际排版需要的窄一两个点，短句就会被挤到第二行，而高度是按
    /// 一行给的，第二行被裁在视图外——看起来就是最后一个字凭空消失。
    private static let measuringLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false
        return label
    }()

    private let label = NSTextField(labelWithString: "")

    /// 尖角顶点的横坐标（视图内坐标）。默认对准气泡中线。
    var tailCenterX: CGFloat = 0 {
        didSet {
            guard tailCenterX != oldValue else { return }
            needsDisplay = true
        }
    }

    var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.font = Self.font
        label.textColor = NSColor(Color.minoInk)
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let insets = Self.textInsets
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            label.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            label.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -(Self.tailSize.height + insets.bottom)
            )
        ])
        tailCenterX = frameRect.width / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 文字排版后气泡应有的整体尺寸（含尾巴高度）。
    static func size(for text: String) -> CGSize {
        let insets = textInsets
        let horizontalPadding = insets.left + insets.right
        let maxTextWidth = MinoDesign.Size.petSpeechMaxWidth - horizontalPadding
        let label = measuringLabel
        label.stringValue = text
        // 先按上限收一次宽，量出真实需要的行宽（短句会小于上限）。
        label.preferredMaxLayoutWidth = maxTextWidth
        let textWidth = min(ceil(label.fittingSize.width), maxTextWidth)
        // 再按最终行宽量高度，否则多行文本的行数会和实际显示的不一致。
        label.preferredMaxLayoutWidth = textWidth
        let textHeight = ceil(label.fittingSize.height)

        let width = min(
            MinoDesign.Size.petSpeechMaxWidth,
            max(MinoDesign.Size.petSpeechMinWidth, textWidth + horizontalPadding)
        )
        let height = textHeight + insets.top + insets.bottom + tailSize.height
        return CGSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 描边占 1pt，路径向内缩半个点才能压在像素格线上，不然边会发虚。
        let path = NSBezierPath(cgPath: Self.bubblePath(
            in: bounds.insetBy(dx: 0.5, dy: 0.5),
            tailCenterX: tailCenterX
        ))
        NSColor(Color.minoSurface).setFill()
        path.fill()
        NSColor(Color.minoLine).withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// 动态颜色要在外观切换时重算，否则深浅色切换后气泡还是旧色。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        label.textColor = NSColor(Color.minoInk)
        needsDisplay = true
    }

    /// 圆角矩形主体 + 底边尖角，拼成一条闭合路径。
    ///
    /// 拼成一条而不是画两个图形，是为了让描边连续：分开画的话主体底边会有一道
    /// 横线横穿尾巴根部。
    private static func bubblePath(in rect: CGRect, tailCenterX: CGFloat) -> CGPath {
        let tail = tailSize
        // 主体底边抬到尾巴上方，尾巴占据 rect 最下面那条。
        let bodyBottom = rect.minY + tail.height
        let halfTail = tail.width / 2
        // 圆角不能大到把直边吃光：竖边要留 minStraightEdge，横边还得容下尾巴。
        let bodyHeight = rect.maxY - bodyBottom
        let radius = max(0, min(
            MinoDesign.Radius.speechBubble,
            (bodyHeight - minStraightEdge) / 2,
            (rect.width - tail.width) / 2
        ))
        // 尖角不能压到圆角上，否则路径自交。
        let tipX = min(
            max(tailCenterX, rect.minX + radius + halfTail),
            rect.maxX - radius - halfTail
        )
        let tailLeft = tipX - halfTail
        let tailRight = tipX + halfTail

        let bottomLeft = CGPoint(x: rect.minX, y: bodyBottom)
        let bottomRight = CGPoint(x: rect.maxX, y: bodyBottom)
        let topRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let topLeft = CGPoint(x: rect.minX, y: rect.maxY)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: tailRight, y: bodyBottom))
        path.addArc(tangent1End: bottomRight, tangent2End: topRight, radius: radius)
        path.addArc(tangent1End: topRight, tangent2End: topLeft, radius: radius)
        path.addArc(tangent1End: topLeft, tangent2End: bottomLeft, radius: radius)
        path.addArc(
            tangent1End: bottomLeft,
            tangent2End: CGPoint(x: tailLeft, y: bodyBottom),
            radius: radius
        )
        path.addLine(to: CGPoint(x: tailLeft, y: bodyBottom))
        path.addArc(
            tangent1End: CGPoint(x: tipX, y: rect.minY),
            tangent2End: CGPoint(x: tailRight, y: bodyBottom),
            radius: tailTipRadius
        )
        path.closeSubpath()
        return path
    }
}
