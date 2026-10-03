import SpriteKit

class ParticleScene: SKScene {
    var emitter: SKEmitterNode?
    
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        
        // Emitter setup (assuming Rain.sks exists or using default particles)
        emitter = SKEmitterNode()
        if let emitter = emitter {
            emitter.particleTexture = SKTexture(imageNamed: "spark")
            emitter.position = CGPoint(x: size.width / 2, y: size.height)
            emitter.particlePositionRange = CGVector(dx: size.width, dy: 0)
            emitter.particleBirthRate = 50
            emitter.particleLifetime = 5
            emitter.particleSpeed = -100
            addChild(emitter)
        }
        
        startMouseTracking()
    }
    
    private func startMouseTracking() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            let mouseLocation = NSEvent.mouseLocation
            // self?.updateMouseLocation(mouseLocation)
        }
    }
    
    func updateMouseLocation(_ location: CGPoint) {
        // Repel logic
    }
}
