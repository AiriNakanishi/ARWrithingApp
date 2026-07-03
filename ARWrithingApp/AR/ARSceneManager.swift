import SwiftUI
import RealityKit
import ARKit

struct ARSceneManager: UIViewRepresentable {
    @Binding var isLocked: Bool
    var selectedModes: Set<GuideMode>
    var baseSize: Float
    var isLeftHanded: Bool
    var targetText: String // 💡 修正：動的に文字を受け取れるように追加
    
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
        context.coordinator.lastRenderedText = targetText // 💡 初期文字を記録
        arView.session.delegate = context.coordinator
        
        // 💡 修正：メソッドに文字（targetText）を渡す
        let guideEntity = ARGuideRenderer.createBaseEntity(text: targetText)
        cursorAnchor.addChild(guideEntity)
        
        ARGuideRenderer.updateScene(root: cursorAnchor, modes: selectedModes, size: baseSize, isLeftHanded: isLeftHanded, text: targetText)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isLocked = isLocked
        guard let anchor = context.coordinator.cursorAnchor else { return }
        
        // 💡 修正：もし入力された文字が変わっていたら「大掃除＆再構築」を実行
        if context.coordinator.lastRenderedText != targetText {
            context.coordinator.lastRenderedText = targetText
            
            // 1. 楽屋（キャッシュ）を全消去
            ARGuideRenderer.clearCache()
            
            // 2. AR空間から古いガイド一式（GuideWrapper）を消去
            if let oldWrapper = anchor.findEntity(named: "GuideWrapper") {
                oldWrapper.removeFromParent()
            }
            
            // 3. 新しい文字で土台（ベース）を作り直してAR空間に追加
            let guideEntity = ARGuideRenderer.createBaseEntity(text: targetText)
            anchor.addChild(guideEntity)
        }
        
        // 💡 修正：更新メソッドにも文字（targetText）を渡す
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ARGuideRenderer.updateScene(root: anchor, modes: selectedModes, size: baseSize, isLeftHanded: isLeftHanded, text: targetText)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        weak var cursorAnchor: AnchorEntity?
        var isLocked = false
        var lastRaycastTime: TimeInterval = 0
        var lastRenderedText: String = "" // 💡 追加：直前に描画していた文字を記憶する箱
        
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
