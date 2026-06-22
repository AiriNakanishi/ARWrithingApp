import SwiftUI
import RealityKit
import ARKit

struct ARSceneManager: UIViewRepresentable {
    @Binding var isLocked: Bool
    var selectedModes: Set<GuideMode>
    var baseSize: Float
    
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
        
        context.coordinator.buildARScene(modes: selectedModes, size: baseSize)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isLocked = isLocked
        context.coordinator.buildARScene(modes: selectedModes, size: baseSize)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        weak var cursorAnchor: AnchorEntity?
        var isLocked = false
        
        var currentRenderedModes: Set<GuideMode> = []
        var currentRenderedSize: Float = 0.0
        
        func buildARScene(modes: Set<GuideMode>, size: Float) {
            guard let anchor = cursorAnchor else { return }
            
            // 🌟 もしボタン（モード）が切り替わっていたら、中身を作り直す
            if currentRenderedModes != modes {
                anchor.children.removeAll()
                // サイズを指定せず、常に固定サイズ（0.0105）で作る
                let guideEntity = ARGuideRenderer.createGuideEntity(modes: modes)
                anchor.addChild(guideEntity)
                currentRenderedModes = modes
            }
            
            // 🌟 もしスライダー（サイズ）が動いたら、倍率（Scale）だけを変更する
            if currentRenderedSize != size {
                // 名前をつけておいた大枠（GuideWrapper）を探す
                if let wrapper = anchor.findEntity(named: "GuideWrapper") {
                    // スライダーの数値を、基準サイズ（0.0105）で割って「何倍にするか」を計算
                    let multiplier = size / ARGuideRenderer.referenceSize
                    // GPUパワーで一瞬で拡大縮小！
                    wrapper.scale = SIMD3<Float>(repeating: multiplier)
                }
                currentRenderedSize = size
            }
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
