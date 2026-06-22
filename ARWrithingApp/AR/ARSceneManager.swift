import SwiftUI
import RealityKit
import ARKit

struct ARSceneManager: UIViewRepresentable {
    @Binding var isLocked: Bool
    var selectedMode: GuideMode
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.renderOptions.insert(.disableGroundingShadows)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        
        let cursorAnchor = AnchorEntity(world: [0, 0, 0])
        arView.scene.addAnchor(cursorAnchor)
        
        context.coordinator.arView = arView
        context.coordinator.cursorAnchor = cursorAnchor
        arView.session.delegate = context.coordinator
        
        context.coordinator.buildARScene(mode: selectedMode)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isLocked = isLocked
        context.coordinator.buildARScene(mode: selectedMode)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        weak var cursorAnchor: AnchorEntity?
        var isLocked = false
        var currentRenderedMode: GuideMode? = nil
        
        func buildARScene(mode: GuideMode) {
            if currentRenderedMode == mode { return }
            guard let anchor = cursorAnchor else { return }
            
            anchor.children.removeAll()
            currentRenderedMode = mode
            
            // 🌟 実際の3Dモデル作成は ARGuideRenderer に丸投げします！
            let guideEntity = ARGuideRenderer.createGuideEntity(mode: mode)
            anchor.addChild(guideEntity)
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView, let cursorAnchor = cursorAnchor else { return }
            guard !isLocked else { return }
            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if let result = arView.raycast(from: screenCenter, allowing: .estimatedPlane, alignment: .horizontal).first {
                let hitPosition = result.worldTransform.columns.3
                cursorAnchor.position = SIMD3<Float>(hitPosition.x, hitPosition.y + 0.001, hitPosition.z)
                let dx = frame.camera.transform.columns.3.x - cursorAnchor.position.x
                let dz = frame.camera.transform.columns.3.z - cursorAnchor.position.z
                cursorAnchor.orientation = simd_quatf(angle: atan2(dx, dz), axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }
}
