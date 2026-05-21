//
//  ContentView.swift
//  ARWrithingApp
//

import SwiftUI
import RealityKit
import ARKit
import CoreText // 🌟 追加：文字の形状データを解析するために必要

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
        // 🎨 1. 動的台形ガイドを並べる（プロトタイプ版）
        // ==========================================
        let textContainer = Entity()
        
        // 🌟 ここに書きたい文字を設定します
//        let targetText = "北海道函館市"
        let targetText = "上下中西瞳俐"
        
        let lineThickness: Float = 0.001 // 線の太さ（1mm）
        let fixedLineSpacing: Float = 0.018 // 🌟 文字ごとの間隔（1.8cm）。均等字間を実現します。
        var currentY: Float = 0.0
        
        // 解析に使うフォント（明朝体の太字などを指定。サイズ100を基準に計算します）
        let ctFont = CTFontCreateWithName("HiraMinProN-W6" as CFString, 100, nil)
        
        for char in targetText {
            // 🌟 魔法の関数で、文字ごとの「上底・下底・高さ」を計算
            let metrics = getCharacterMetrics(char: char, font: ctFont)
            
            // 計算されたパラメータを使って台形を生成
            let guideBox = createDynamicTrapezoid(
                topWidth: metrics.topWidth,
                bottomWidth: metrics.bottomWidth,
                height: metrics.height,
                thickness: lineThickness,
                color: UIColor.blue.withAlphaComponent(0.5)
            )

            // 文字の中心を基準に配置（均等字間）
            guideBox.position = [0, currentY, 0]
            
            textContainer.addChild(guideBox)
            
            // 次の文字のために基準位置を等間隔で下げる
            currentY -= fixedLineSpacing
        }
        
        // まとめた箱の中心を原点に合わせる
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
// 📦 【新規】CoreTextを使って文字の形を解析し、台形のサイズを計算する関数
// ==========================================
func getCharacterMetrics(char: Character, font: CTFont) -> (topWidth: Float, bottomWidth: Float, height: Float) {
    // 1文字を解析用に変換
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    let uniChars = Array(String(char).utf16)
    let success = CTFontGetGlyphsForCharacters(font, uniChars, &glyphs, 1)
    
    // ガード：空白や取得できない文字の場合はデフォルトサイズを返す
    guard success, let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        return (0.015, 0.015, 0.015) // 15mm角
    }
    
    let bounds = path.boundingBoxOfPath
    let midY = bounds.midY // Y軸の中心線
    
    // 上半分と下半分の最小X・最大Xを記録する変数
    var topMinX = bounds.maxX
    var topMaxX = bounds.minX
    var bottomMinX = bounds.maxX
    var bottomMaxX = bounds.minX
    
    // パス（文字の輪郭線）を構成するすべての座標をチェック
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
                // 上半分の座標
                topMinX = min(topMinX, p.x)
                topMaxX = max(topMaxX, p.x)
            } else {
                // 下半分の座標
                bottomMinX = min(bottomMinX, p.x)
                bottomMaxX = max(bottomMaxX, p.x)
            }
        }
    }
    
    // 座標が取得できなかった場合（極端な形状の対応）の安全策
    if topMinX > topMaxX { topMinX = bounds.midX; topMaxX = bounds.midX }
    if bottomMinX > bottomMaxX { bottomMinX = bounds.midX; bottomMaxX = bounds.midX }
    
    // ARのスケールに変換（フォントサイズ100を1.5cm = 0.015mに縮小）
    let arScale: CGFloat = 0.00015
    
    let tWidth = Float((topMaxX - topMinX) * arScale)
    let bWidth = Float((bottomMaxX - bottomMinX) * arScale)
    let height = Float(bounds.height * arScale)
    
    // 「一」などの文字が潰れないように最低2mm(0.002)は確保する
    let finalTopWidth = max(tWidth, 0.002)
    let finalBottomWidth = max(bWidth, 0.002)
    let finalHeight = max(height, 0.002)
    
    return (finalTopWidth, finalBottomWidth, finalHeight)
}


// ==========================================
// 📦 任意の2点間に「線」を引く魔法の関数
// ==========================================
func createLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor, opacity: CGFloat = 1.0) -> ModelEntity {
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    let length = sqrt(dx*dx + dy*dy)
    
    let mesh = MeshResource.generateBox(size: [length, thickness, 0.0001])
    var material = UnlitMaterial(color: color.withAlphaComponent(opacity))
    if color.cgColor.alpha < 1.0 || opacity < 1.0 {
        material.blending = .transparent(opacity: 1.0)
    }
    
    let line = ModelEntity(mesh: mesh, materials: [material])
    line.position = [(p1.x + p2.x) / 2, (p1.y + p2.y) / 2, 0]
    line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1])
    
    return line
}


// ==========================================
// 📦 【新規】計算結果から動的な「台形」を作る関数
// ==========================================
func createDynamicTrapezoid(topWidth: Float, bottomWidth: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity()
    
    // 台形の4つの角の座標を定義
    let top = SIMD3<Float>(0, height / 2, 0)
    let bottom = SIMD3<Float>(0, -height / 2, 0)
    
    let topLeft = SIMD3<Float>(-topWidth / 2, height / 2, 0)
    let topRight = SIMD3<Float>(topWidth / 2, height / 2, 0)
    let bottomLeft = SIMD3<Float>(-bottomWidth / 2, -height / 2, 0)
    let bottomRight = SIMD3<Float>(bottomWidth / 2, -height / 2, 0)
    
    // 結ぶ線の組み合わせ
    let lines: [(SIMD3<Float>, SIMD3<Float>)] = [
        (topLeft, topRight),       // 上底
        (topRight, bottomRight),   // 右辺
        (bottomRight, bottomLeft), // 下底
        (bottomLeft, topLeft)      // 左辺
    ]
    
    // 枠線を生成して組み立てる
    for linePoints in lines {
        let lineEntity = createLineEntity(from: linePoints.0, to: linePoints.1, thickness: thickness, color: color, opacity: color.cgColor.alpha)
        frame.addChild(lineEntity)
    }
    
    // 中心線を追加
    let centerV = createLineEntity(from: top, to: bottom, thickness: thickness, color: color, opacity: 0.3)
    frame.addChild(centerV)
    
    return frame
}

#Preview {
    ContentView()
}
