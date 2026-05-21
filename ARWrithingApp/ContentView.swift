//
//  ContentView.swift
//  ARWrithingApp
//

import SwiftUI
import RealityKit
import ARKit
import CoreText

struct ContentView: View {
    @State private var isLocked = false
    
    var body: some View {
        ZStack {
            ARViewContainer(isLocked: $isLocked)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                Button(action: {
                    isLocked.toggle()
                }) {
                    Text(isLocked ? "解除" : "固定")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 200)
                        .background(isLocked ? Color.red : Color.blue)
                        .cornerRadius(15)
                        .shadow(radius: 5)
                }
                .padding(.bottom, 50)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var isLocked: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        
        // ==========================================
        // 🎨 1. 動的台形ガイドとお手本文字を並べる
        // ==========================================
        let textContainer = Entity()
//        let targetText = "北海道函館市" // 検証したい文字
        let targetText = "北海道函館市亀田中野町一一六番地二" // 検証したい文字
//        let targetText = "田上下寺目尺" // 検証したい文字
        
        let lineThickness: Float = 0.0005
        let fixedLineSpacing: Float = 0.010 // 文字間隔（1.8cm）
        let xOffset: Float = -0.015         // 🌟 左に2.5cmずらす
        var currentY: Float = 0.0
        
        // フォントの設定（解析用と3D文字描画用でフォントを揃える）
                // 🌟 KleeOneを最優先にし、見つからなければ明朝体にする
                let uiFont = UIFont(name: "KleeOne-Regular", size: 0.010)
                          ?? UIFont(name: "HiraMinProN-W6", size: 0.010)
                          ?? .systemFont(ofSize: 0.015, weight: .bold)
                
                // 🌟 描画用と同じフォント名を使って、解析用のCoreTextフォントを生成
                let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, 100, nil)
        
        // 文字のマテリアル（少し透け感のある黒）
        var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8))
        textMaterial.blending = .transparent(opacity: 1.0)
        
        for char in targetText {
            // 文字ごとの「上底・下底・高さ」を計算
            let metrics = getCharacterMetrics(char: char, font: ctFont)
            
            // ---------------------------------
            // ① 中央のガイド（本番用）
            // ---------------------------------
            let mainGuide = createDynamicTrapezoid(
                topWidth: metrics.topWidth,
                bottomWidth: metrics.bottomWidth,
                height: metrics.height,
                thickness: lineThickness,
                color: UIColor.blue.withAlphaComponent(0.5)
            )
            mainGuide.position = [0, currentY, 0]
            textContainer.addChild(mainGuide)
            
            // ---------------------------------
            // ② 左側のお手本用ガイド（比較用）
            // ---------------------------------
            let exemplarGuide = createDynamicTrapezoid(
                topWidth: metrics.topWidth,
                bottomWidth: metrics.bottomWidth,
                height: metrics.height,
                thickness: lineThickness,
                color: UIColor.red.withAlphaComponent(0.4) // 🌟 わかりやすいように色を赤に変更
            )
            exemplarGuide.position = [xOffset, currentY, 0]
            textContainer.addChild(exemplarGuide)
            
            // ---------------------------------
            // ③ 左側のお手本文字
            // ---------------------------------
            let charMesh = MeshResource.generateText(
                String(char),
                extrusionDepth: 0.0,
                font: uiFont
            )
            let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
            let charBounds = charEntity.visualBounds(relativeTo: nil)
            
            // 🌟 文字の中心が、ガイドの中心(xOffset, currentY)にぴったり重なるように配置
            charEntity.position = [
                xOffset - charBounds.center.x,
                currentY - charBounds.center.y,
                0.001
            ]
            textContainer.addChild(charEntity)
            
            // 次の文字へ
            currentY -= fixedLineSpacing
        }
        
        // まとめた箱の中心を原点に合わせる
        let totalBounds = textContainer.visualBounds(relativeTo: nil)
        textContainer.position = -totalBounds.center
        
        // ==========================================
        // 🎨 2. 文字を寝かせる処理
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
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isLocked = isLocked
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        weak var cursorAnchor: AnchorEntity?
        var isLocked = false
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView, let cursorAnchor = cursorAnchor else { return }
            guard !isLocked else { return }
            
            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if let result = arView.raycast(from: screenCenter, allowing: .estimatedPlane, alignment: .horizontal).first {
                let hitPosition = result.worldTransform.columns.3
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

// ==========================================
// 📦 各種計算・生成関数（変更なし）
// ==========================================
func getCharacterMetrics(char: Character, font: CTFont) -> (topWidth: Float, bottomWidth: Float, height: Float) {
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    let uniChars = Array(String(char).utf16)
    let success = CTFontGetGlyphsForCharacters(font, uniChars, &glyphs, 1)
    
    guard success, let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        return (0.015, 0.015, 0.015)
    }
    
    let bounds = path.boundingBoxOfPath
    let midY = bounds.midY
    
    var topMinX = bounds.maxX, topMaxX = bounds.minX
    var bottomMinX = bounds.maxX, bottomMaxX = bounds.minX
    
    path.applyWithBlock { elementPointer in
        let element = elementPointer.pointee
        let points = element.points
        let numPoints: Int
        
        switch element.type {
        case .moveToPoint, .addLineToPoint: numPoints = 1
        case .addQuadCurveToPoint: numPoints = 2
        case .addCurveToPoint: numPoints = 3
        case .closeSubpath: numPoints = 0
        @unknown default: numPoints = 0
        }
        
        for i in 0..<numPoints {
            let p = points[i]
            if p.y >= midY {
                topMinX = min(topMinX, p.x); topMaxX = max(topMaxX, p.x)
            } else {
                bottomMinX = min(bottomMinX, p.x); bottomMaxX = max(bottomMaxX, p.x)
            }
        }
    }
    
    if topMinX > topMaxX { topMinX = bounds.midX; topMaxX = bounds.midX }
    if bottomMinX > bottomMaxX { bottomMinX = bounds.midX; bottomMaxX = bounds.midX }
    
    let arScale: CGFloat = 0.00010
    let tWidth = Float((topMaxX - topMinX) * arScale)
    let bWidth = Float((bottomMaxX - bottomMinX) * arScale)
    let height = Float(bounds.height * arScale)
    
    return (max(tWidth, 0.0015), max(bWidth, 0.0015), max(height, 0.0015))
}

func createLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor, opacity: CGFloat = 1.0) -> ModelEntity {
    let dx = p2.x - p1.x, dy = p2.y - p1.y
    let length = sqrt(dx*dx + dy*dy)
    let mesh = MeshResource.generateBox(size: [length, thickness, 0.0001])
    
    var material = UnlitMaterial(color: color.withAlphaComponent(opacity))
    if color.cgColor.alpha < 1.0 || opacity < 1.0 { material.blending = .transparent(opacity: 1.0) }
    
    let line = ModelEntity(mesh: mesh, materials: [material])
    line.position = [(p1.x + p2.x) / 2, (p1.y + p2.y) / 2, 0]
    line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1])
    return line
}

func createDynamicTrapezoid(topWidth: Float, bottomWidth: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity()
    let top = SIMD3<Float>(0, height / 2, 0)
    let bottom = SIMD3<Float>(0, -height / 2, 0)
    let topLeft = SIMD3<Float>(-topWidth / 2, height / 2, 0)
    let topRight = SIMD3<Float>(topWidth / 2, height / 2, 0)
    let bottomLeft = SIMD3<Float>(-bottomWidth / 2, -height / 2, 0)
    let bottomRight = SIMD3<Float>(bottomWidth / 2, -height / 2, 0)
    
    let lines: [(SIMD3<Float>, SIMD3<Float>)] = [
        (topLeft, topRight), (topRight, bottomRight),
        (bottomRight, bottomLeft), (bottomLeft, topLeft)
    ]
    for lp in lines {
        frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color, opacity: color.cgColor.alpha))
    }
    frame.addChild(createLineEntity(from: top, to: bottom, thickness: thickness, color: color, opacity: 0.3))
    return frame
}

#Preview {
    ContentView()
}
