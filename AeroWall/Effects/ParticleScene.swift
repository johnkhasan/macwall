import SpriteKit

/// Transparent overlay rendered above the video. Particles are pushed away from the pointer
/// by a radial field whose position is fed from `WallpaperWindow.trackPointer`.
final class ParticleScene: SKScene {
    enum Kind: Equatable {
        case rain, snow, fireflies
    }

    private(set) var kind: Kind?
    private var intensity: Double = 0.5
    private var interactive = true
    private var emitter: SKEmitterNode?
    private let repulsor = SKFieldNode.radialGravityField()

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        physicsWorld.gravity = .zero

        repulsor.categoryBitMask = 1
        repulsor.region = SKRegion(radius: 160)
        repulsor.falloff = 0.5
        repulsor.minimumRadius = 20
        repulsor.isEnabled = false
        addChild(repulsor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(kind: Kind, intensity: Double, interactive: Bool) {
        self.interactive = interactive
        if !interactive { repulsor.isEnabled = false }
        guard kind != self.kind || abs(intensity - self.intensity) > 0.001 else { return }
        self.kind = kind
        self.intensity = intensity
        rebuild()
    }

    func setRepulsor(at point: CGPoint?) {
        guard interactive, let point else {
            repulsor.isEnabled = false
            return
        }
        repulsor.position = point
        repulsor.isEnabled = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if oldSize != size { rebuild() }
    }

    private func rebuild() {
        emitter?.removeFromParent()
        emitter = nil
        guard let kind, size.width > 0, size.height > 0 else { return }

        let width = size.width
        let height = size.height
        let density = CGFloat(max(0.1, intensity))
        let node = SKEmitterNode()
        node.targetNode = self
        node.fieldBitMask = 1
        node.particleColor = .white
        node.particleColorBlendFactor = 1

        switch kind {
        case .rain:
            node.particleTexture = Self.dropTexture
            node.position = CGPoint(x: width / 2, y: height + 40)
            node.particlePositionRange = CGVector(dx: width * 1.2, dy: 0)
            node.emissionAngle = -.pi / 2 - 0.12
            node.particleRotation = -0.12
            node.particleSpeed = 1100
            node.particleSpeedRange = 250
            node.particleBirthRate = width / 5 * density
            node.particleLifetime = (height + 80) / 850
            node.particleAlpha = 0.35
            node.particleAlphaRange = 0.15
            node.particleScale = 1
            node.particleScaleRange = 0.4
            repulsor.strength = -6

        case .snow:
            node.particleTexture = Self.softDotTexture
            node.position = CGPoint(x: width / 2, y: height + 20)
            node.particlePositionRange = CGVector(dx: width * 1.1, dy: 0)
            node.emissionAngle = -.pi / 2
            node.emissionAngleRange = 0.6
            node.particleSpeed = 70
            node.particleSpeedRange = 40
            node.particleBirthRate = width / 50 * density
            node.particleLifetime = (height + 40) / 45
            node.particleAlpha = 0.85
            node.particleAlphaRange = 0.15
            node.particleScale = 0.5
            node.particleScaleRange = 0.45
            node.xAcceleration = 4
            repulsor.strength = -1.5

        case .fireflies:
            node.particleTexture = Self.softDotTexture
            node.position = CGPoint(x: width / 2, y: height / 2)
            node.particlePositionRange = CGVector(dx: width, dy: height)
            node.emissionAngleRange = .pi * 2
            node.particleSpeed = 18
            node.particleSpeedRange = 14
            node.particleBirthRate = width * height / 120_000 * density
            node.particleLifetime = 7
            node.particleLifetimeRange = 3
            node.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.9, 0.9, 0], times: [0, 0.2, 0.7, 1])
            node.particleScale = 0.4
            node.particleScaleRange = 0.4
            node.particleColor = NSColor(red: 1, green: 0.85, blue: 0.45, alpha: 1)
            node.particleBlendMode = .add
            repulsor.strength = -1.5
        }

        addChild(node)
        // Start with a full screen of particles instead of an empty one filling up.
        node.advanceSimulationTime(TimeInterval(node.particleLifetime))
        emitter = node
    }

    // MARK: Textures

    private static func texture(size: CGSize, draw: @escaping (CGRect) -> Void) -> SKTexture {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        return SKTexture(image: image)
    }

    private static let dropTexture = texture(size: CGSize(width: 2, height: 30)) { rect in
        NSGradient(starting: .white.withAlphaComponent(0), ending: .white)?.draw(in: rect, angle: -90)
    }

    private static let softDotTexture = texture(size: CGSize(width: 24, height: 24)) { rect in
        NSGradient(colors: [.white, .white.withAlphaComponent(0.6), .white.withAlphaComponent(0)])?
            .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
    }
}
