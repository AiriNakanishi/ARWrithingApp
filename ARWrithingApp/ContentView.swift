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
        
//        //外形表示↓
//        // ==========================================
//                // 🎨 1. 外形ガイドを並べる
//                // ==========================================
//                let textContainer = Entity()
//                
//                // 🌟 文字ごとの「形」と「サイズ(幅, 高さ)」を自分で自由に設定できるリスト！
//                // ※ 0.015 = 15ミリ(1.5cm)
//                let guideData: [(shape: GuideShape, w: Float, h: Float)] = [
//                    (.rectangle, 0.015, 0.015),        // 1文字目：四角形
//                    (.triangle, 0.018, 0.015),         // 2文字目：三角形（少し幅広）
//                    (.invertedTriangle, 0.015, 0.018), // 3文字目：逆三角形（少し縦長）
//                    (.rhombus, 0.018, 0.018),          // 4文字目：ひし形
//                    (.rectangle, 0.012, 0.015),         // 5文字目：細い四角形
//                    (.trapezoid, 0.015, 0.015)
//                ]
//                
//                let lineThickness: Float = 0.001 // 線の太さ（1mm）
//                let margin: Float = 0.003        // 文字と文字の隙間（3mm）
//                var currentY: Float = 0.0
//                
//                for data in guideData {
//                    // リストに書いた「形・幅・高さ」を使ってガイドを作る
//                    let guideBox = createGuideFrame(shape: data.shape, width: data.w, height: data.h, thickness: lineThickness, color: UIColor.blue.withAlphaComponent(0.5))
//
//                    // 自分の高さの半分だけ下にずらして配置
//                    let posY = currentY - (data.h / 2)
//                    guideBox.position = [0, posY, 0]
//                    
//                    textContainer.addChild(guideBox)
//                    
//                    // 次の文字のために基準位置を下げる
//                    currentY -= (data.h + margin)
//                }
//                
//                // まとめた箱の中心を原点に合わせる
//                let totalBounds = textContainer.visualBounds(relativeTo: nil)
//                textContainer.position = -totalBounds.center
//        
//        //外形表示↑
        
//        お手本の文字をなぞる↓
        // ==========================================
        // 🎨 1. 縦書きの文字を作る（1文字ずつ並べる）
        // ==========================================
//        let address = "北海道函館市亀田中野町一一六番地二"
        let address = "田上下寺目尺"
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
        //お手本の文字をなぞる↑
//
        
        
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


// 🌟 追加：外形の「形」をえらべるようにするリスト（列挙型）
enum GuideShape {
    case rectangle        // 四角形
    case triangle         // 三角形（上が尖っている）
    case invertedTriangle // 逆三角形（下が尖っている）
    case rhombus          // ひし形
    case trapezoid
}

// ==========================================
// 📦 任意の2点間に「線」を引く魔法の関数
// ==========================================
func createLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor, opacity: CGFloat = 1.0) -> ModelEntity {
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    let length = sqrt(dx*dx + dy*dy) // ピタゴラスの定理で長さを計算
    
    let mesh = MeshResource.generateBox(size: [length, thickness, 0.0001])
    
    var material = UnlitMaterial(color: color.withAlphaComponent(opacity))
    if color.cgColor.alpha < 1.0 {
            material.blending = .transparent(opacity: 1.0)
        }
    if opacity < 1.0 {
        material.blending = .transparent(opacity: 1.0)
    }
    
    let line = ModelEntity(mesh: mesh, materials: [material])
    
    // 中間地点に配置
    line.position = [(p1.x + p2.x) / 2, (p1.y + p2.y) / 2, 0]
    
    // 角度を計算して斜めに回転させる
    let angle = atan2(dy, dx)
    line.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
    
    return line
}

// ==========================================
// 📦 様々な形の「外形ガイド」と「中心線」を作る関数
// ==========================================
func createGuideFrame(shape: GuideShape, width: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity()
    
    // 頂点の座標を定義（中心を 0,0,0 としたときの上下左右の端っこ）
    let top = SIMD3<Float>(0, height / 2, 0)
    let bottom = SIMD3<Float>(0, -height / 2, 0)
    let topLeft = SIMD3<Float>(-width / 2, height / 2, 0)
    let topRight = SIMD3<Float>(width / 2, height / 2, 0)
    let bottomLeft = SIMD3<Float>(-width / 2, -height / 2, 0)
    let bottomRight = SIMD3<Float>(width / 2, -height / 2, 0)
    let left = SIMD3<Float>(-width / 2, 0, 0)
    let right = SIMD3<Float>(width / 2, 0, 0)
    
    let trapezoidTopLeft = SIMD3<Float>(-width / 4, height / 2, 0)
        let trapezoidTopRight = SIMD3<Float>(width / 4, height / 2, 0)
    // 結ぶ線の組み合わせを入れるリスト
    var lines: [(SIMD3<Float>, SIMD3<Float>)] = []
    
    switch shape {
    case .rectangle: // 四角形
        lines = [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)]
    case .triangle: // 三角形（「大」や「人」など下半身が広い字）
        lines = [(top, bottomRight), (bottomRight, bottomLeft), (bottomLeft, top)]
    case .invertedTriangle: // 逆三角形（「甲」や「可」など頭がでっかい字）
        lines = [(topLeft, topRight), (topRight, bottom), (bottom, topLeft)]
    case .rhombus: // ひし形（「今」や「令」など真ん中が膨らむ字）
        lines = [(top, right), (right, bottom), (bottom, left), (left, top)]
    case .trapezoid: // 🌟 台形（上の辺が短く、下の辺が長い）
            lines = [(trapezoidTopLeft, trapezoidTopRight), (trapezoidTopRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, trapezoidTopLeft)]
        }
    
    // 枠線を生成して組み立てる
    for linePoints in lines {
        let lineEntity = createLineEntity(from: linePoints.0, to: linePoints.1, thickness: thickness, color: color,opacity: color.cgColor.alpha)
        frame.addChild(lineEntity)
    }
    
    // 🌟 縦の中心線のみを少し薄くして追加
    let centerV = createLineEntity(from: top, to: bottom, thickness: thickness, color: color, opacity: 0.3)
    frame.addChild(centerV)
    
    return frame
}

#Preview {
    ContentView()
}


