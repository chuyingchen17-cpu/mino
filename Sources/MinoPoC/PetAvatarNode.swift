import AppKit
import SpriteKit

@MainActor
final class PetAvatarNode: SKNode {
    private let speciesLayer = SKNode()
    private let bodyLayer = SKNode()
    private let faceLayer = SKNode()
    private let hatLayer = SKNode()
    private let accessoryLayer = SKNode()

    private var recipe: AvatarRecipe?

    override init() {
        super.init()

        speciesLayer.zPosition = 0
        bodyLayer.zPosition = 10
        accessoryLayer.zPosition = 20
        faceLayer.zPosition = 30
        hatLayer.zPosition = 40

        addChild(speciesLayer)
        addChild(bodyLayer)
        addChild(accessoryLayer)
        addChild(faceLayer)
        addChild(hatLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func apply(_ recipe: AvatarRecipe) {
        guard self.recipe != recipe else { return }
        self.recipe = recipe

        rebuildSpecies(recipe.species, color: recipe.bodyColor.nsColor)
        rebuildBody(color: recipe.bodyColor.nsColor)
        rebuildFace(recipe.eyeStyle)
        rebuildHat(recipe.hat)
        rebuildAccessory(recipe.accessory)
    }

    func setFacing(_ facing: PetFacing) {
        xScale = facing == .right ? 1 : -1
    }

    private func rebuildSpecies(_ species: AvatarSpecies, color: NSColor) {
        speciesLayer.removeAllChildren()

        switch species {
        case .cat:
            for x in [-24.0, 24.0] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x - 15, y: 28))
                path.addLine(to: CGPoint(x: x, y: 62))
                path.addLine(to: CGPoint(x: x + 15, y: 28))
                path.closeSubpath()
                let ear = SKShapeNode(path: path)
                ear.fillColor = color
                ear.strokeColor = color.blended(withFraction: 0.25, of: .black) ?? .black
                ear.lineWidth = 3
                speciesLayer.addChild(ear)
            }
        case .bunny:
            for x in [-20.0, 20.0] {
                let ear = SKShapeNode(ellipseOf: CGSize(width: 25, height: 62))
                ear.fillColor = color
                ear.strokeColor = color.blended(withFraction: 0.25, of: .black) ?? .black
                ear.lineWidth = 3
                ear.position = CGPoint(x: x, y: 48)
                speciesLayer.addChild(ear)

                let inner = SKShapeNode(ellipseOf: CGSize(width: 9, height: 38))
                inner.fillColor = NSColor.systemPink.withAlphaComponent(0.45)
                inner.strokeColor = .clear
                inner.position = CGPoint(x: x, y: 48)
                inner.zPosition = 1
                speciesLayer.addChild(inner)
            }
        }
    }

    private func rebuildBody(color: NSColor) {
        bodyLayer.removeAllChildren()
        let body = SKShapeNode(ellipseOf: CGSize(width: 88, height: 82))
        body.fillColor = color
        body.strokeColor = color.blended(withFraction: 0.25, of: .black) ?? .black
        body.lineWidth = 3
        bodyLayer.addChild(body)
    }

    private func rebuildFace(_ style: AvatarEyeStyle) {
        faceLayer.removeAllChildren()

        switch style {
        case .dots:
            for x in [-15.0, 15.0] {
                let eye = SKShapeNode(circleOfRadius: 4)
                eye.fillColor = .black
                eye.strokeColor = .clear
                eye.position = CGPoint(x: x, y: 9)
                faceLayer.addChild(eye)
            }
        case .happy:
            for (x, direction) in [(-15.0, 1.0), (15.0, -1.0)] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x - 6, y: 8))
                path.addLine(to: CGPoint(x: x, y: 13 + direction))
                path.addLine(to: CGPoint(x: x + 6, y: 8))
                let eye = SKShapeNode(path: path)
                eye.strokeColor = .black
                eye.lineWidth = 3
                eye.lineCap = .round
                faceLayer.addChild(eye)
            }
        }

        let mouthPath = CGMutablePath()
        mouthPath.move(to: CGPoint(x: -6, y: -7))
        mouthPath.addQuadCurve(to: CGPoint(x: 6, y: -7), control: CGPoint(x: 0, y: -14))
        let mouth = SKShapeNode(path: mouthPath)
        mouth.strokeColor = .black
        mouth.lineWidth = 2.5
        mouth.lineCap = .round
        faceLayer.addChild(mouth)
    }

    private func rebuildHat(_ style: AvatarHatStyle) {
        hatLayer.removeAllChildren()

        switch style {
        case .none:
            break
        case .beanie:
            let cap = SKShapeNode(rectOf: CGSize(width: 58, height: 23), cornerRadius: 10)
            cap.fillColor = .systemPink
            cap.strokeColor = .clear
            cap.position = CGPoint(x: 0, y: 42)
            hatLayer.addChild(cap)

            let pom = SKShapeNode(circleOfRadius: 8)
            pom.fillColor = .white
            pom.strokeColor = .clear
            pom.position = CGPoint(x: 0, y: 59)
            hatLayer.addChild(pom)
        case .flower:
            let center = CGPoint(x: 27, y: 39)
            for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 2) {
                let petal = SKShapeNode(circleOfRadius: 7)
                petal.fillColor = .systemPink
                petal.strokeColor = .clear
                petal.position = CGPoint(
                    x: center.x + cos(angle) * 8,
                    y: center.y + sin(angle) * 8
                )
                hatLayer.addChild(petal)
            }
            let middle = SKShapeNode(circleOfRadius: 5)
            middle.fillColor = .systemYellow
            middle.strokeColor = .clear
            middle.position = center
            hatLayer.addChild(middle)
        }
    }

    private func rebuildAccessory(_ style: AvatarAccessoryStyle) {
        accessoryLayer.removeAllChildren()

        switch style {
        case .none:
            break
        case .scarf:
            let band = SKShapeNode(rectOf: CGSize(width: 80, height: 13), cornerRadius: 6)
            band.fillColor = .systemOrange
            band.strokeColor = .clear
            band.position = CGPoint(x: 0, y: -22)
            accessoryLayer.addChild(band)

            let tail = SKShapeNode(rectOf: CGSize(width: 15, height: 32), cornerRadius: 5)
            tail.fillColor = .systemOrange
            tail.strokeColor = .clear
            tail.position = CGPoint(x: 26, y: -40)
            tail.zRotation = -0.2
            accessoryLayer.addChild(tail)
        case .necklace:
            let chainPath = CGMutablePath()
            chainPath.move(to: CGPoint(x: -26, y: -20))
            chainPath.addQuadCurve(to: CGPoint(x: 26, y: -20), control: CGPoint(x: 0, y: -42))
            let chain = SKShapeNode(path: chainPath)
            chain.strokeColor = .systemYellow
            chain.lineWidth = 3
            accessoryLayer.addChild(chain)

            let charm = SKShapeNode(circleOfRadius: 6)
            charm.fillColor = .systemPink
            charm.strokeColor = .clear
            charm.position = CGPoint(x: 0, y: -33)
            accessoryLayer.addChild(charm)
        }
    }
}

