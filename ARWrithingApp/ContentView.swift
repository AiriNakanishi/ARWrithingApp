//
//  ContentView.swift
//  ARWrithingApp
//

import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    // 🌟 追加：文字が固定されているかどうかを判定する変数（最初はfalse＝固定されていない）
    @State private var isLocked = false
    
    var body: some View {
        // ZStackで、AR画面の上にボタンを重ねる
        ZStack {
            // ARViewContainerに isLocked の状態を渡す
            ARViewContainer(isLocked: $isLocked)
                .edgesIgnoringSafeArea(.all)
            
            // 🌟 画面の下に「固定ボタン」を配置
            VStack {
                Spacer()
                Button(action: {
                    // ボタンを押すたびに true / false が切り替わる
                    isLocked.toggle()
                }) {
                    Text(isLocked ? "解除" : "固定")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 200)
                        .background(isLocked ? Color.red : Color.blue) // ロック中は赤、解除中は青
                        .cornerRadius(15)
                        .shadow(radius: 5)
                }
                .padding(.bottom, 50) // 画面下からの余白
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    // ContentViewから isLocked の状態を受け取る
    @Binding var isLocked: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        
        // ==========================================
        // 🎨 1. 縦書きの文字を作る（1文字ずつ並べる）
        // ==========================================
        let address = "北海道函館市亀田中野町一一六番地二"
        let textContainer = Entity()
        
        var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.2))
        textMaterial.blending = .transparent(opacity: 1.0)
        
        let lineSpacing: Float = 0.0088
        var currentY: Float = 0.0
        
        let customFont = UIFont(name: "KleeOne-SemiBold", size: 0.005) ?? UIFont(name: "HiraMinProN-W6", size: 0.008) ?? .systemFont(ofSize: 0.008, weight: .bold)
        
        for char in address {
            let charMesh = MeshResource.generateText(
                String(char),
                extrusionDepth: 0.0,
                font: customFont
            )
            let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
            
            let charBounds = charEntity.visualBounds(relativeTo: nil)
            charEntity.position = [
                -charBounds.center.x,
                currentY,
                0
            ]
            
            textContainer.addChild(charEntity)
            currentY -= lineSpacing
        }
        
        let totalBounds = textContainer.visualBounds(relativeTo: nil)
        textContainer.position = -totalBounds.center
        
        // ==========================================
        // 🎨 2. 文字を寝かせる
        // ==========================================
        let flatWrapper = Entity()
        flatWrapper.addChild(textContainer)
        flatWrapper.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        
        let cursorAnchor = AnchorEntity(world: [0, 0, 0])
        cursorAnchor.addChild(flatWrapper)
        arView.scene.addAnchor(cursorAnchor)
        
        context.coordinator.arView = arView
        context.coordinator.cursorAnchor = cursorAnchor
        arView.session.delegate = context.coordinator
        
        return arView
    }
    
    // 🌟 SwiftUI側でボタンが押されたら、ここが呼ばれてCoordinatorに状態を伝える
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isLocked = isLocked
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        weak var cursorAnchor: AnchorEntity?
        
        // Coordinator側でもロック状態を持っておく
        var isLocked = false
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView, let cursorAnchor = cursorAnchor else { return }
            
            // 🌟 もしロックされていたら、ここから下の「座標・角度の更新」を無視して終了する！
            guard !isLocked else { return }
            
            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            if let result = arView.raycast(from: screenCenter, allowing: .estimatedPlane, alignment: .horizontal).first {
                
                let hitPosition = result.worldTransform.columns.3
                // 1ミリ浮かせる
                cursorAnchor.position = SIMD3<Float>(hitPosition.x, hitPosition.y + 0.001, hitPosition.z)
                
                let cameraPos = frame.camera.transform.columns.3
                let anchorPos = cursorAnchor.position
                
                let dx = cameraPos.x - anchorPos.x
                let dz = cameraPos.z - anchorPos.z
                let yaw = atan2(dx, dz)
                
                cursorAnchor.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }
}

// 距離計算ヘルパー（今回は使っていませんが残しておいてOKです）
func distance(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
    let dx = a.x - b.x
    let dy = a.y - b.y
    let dz = a.z - b.z
    return sqrt(dx*dx + dy*dy + dz*dz)
}

#Preview {
    ContentView()
}
