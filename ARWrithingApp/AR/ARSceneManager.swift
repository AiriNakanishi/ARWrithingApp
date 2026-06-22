import SwiftUI
import RealityKit
import ARKit

struct ARSceneManager: UIViewRepresentable {
    @Binding var isLocked: Bool
    var selectedModes: Set<GuideMode>
    var baseSize: Float
    var isLeftHanded: Bool
    
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
        
        // 🌟 起動時は最小限のベース（枠線とお手本）のみを作成する
        let guideEntity = ARGuideRenderer.createBaseEntity()
        cursorAnchor.addChild(guideEntity)
        
        ARGuideRenderer.updateScene(root: cursorAnchor, modes: selectedModes, size: baseSize, isLeftHanded: isLeftHanded)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isLocked = isLocked
        guard let anchor = context.coordinator.cursorAnchor else { return }
        
        // 🌟 切り替え時の安全網（Delay）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ARGuideRenderer.updateScene(root: anchor, modes: selectedModes, size: baseSize, isLeftHanded: isLeftHanded)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        weak var cursorAnchor: AnchorEntity?
        var isLocked = false
        var lastRaycastTime: TimeInterval = 0
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView, let cursorAnchor = cursorAnchor else { return }
            guard !isLocked else { return }
            
            let currentTime = ProcessInfo.processInfo.systemUptime
            if currentTime - lastRaycastTime < 0.05 { return }
            lastRaycastTime = currentTime
            
            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if let result = arView.raycast(from: screenCenter, allowing: .estimatedPlane, alignment: .horizontal).first {
                let hitPosition = result.worldTransform.columns.3
                let targetPos = SIMD3<Float>(hitPosition.x, hitPosition.y + 0.001, hitPosition.z)
                
                if simd_distance(cursorAnchor.position, targetPos) > 0.002 {
                    cursorAnchor.position = targetPos
                    let dx = frame.camera.transform.columns.3.x - cursorAnchor.position.x
                    let dz = frame.camera.transform.columns.3.z - cursorAnchor.position.z
                    cursorAnchor.orientation = simd_quatf(angle: atan2(dx, dz), axis: SIMD3<Float>(0, 1, 0))
                }
            }
        }
    }
}
