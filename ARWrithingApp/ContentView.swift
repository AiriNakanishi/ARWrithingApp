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
    
    // ズーム・パン用の変数
    @State private var currentZoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    
    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    let baseParallax = CGSize(width: 30, height: 30)
    
    var body: some View {
        ZStack {
            ARViewContainer(isLocked: $isLocked)
                .scaleEffect((currentZoom * gestureZoom) * 1.5)
                .offset(
                    x: baseParallax.width + currentOffset.width + gestureOffset.width,
                    y: baseParallax.height + currentOffset.height + gestureOffset.height
                )
                .gesture(
                    DragGesture()
                        .updating($gestureOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            currentOffset.width += value.translation.width
                            currentOffset.height += value.translation.height
                        }
                )
                .edgesIgnoringSafeArea(.all)
                .gesture(
                    MagnificationGesture()
                        .updating($gestureZoom) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            currentZoom *= value
                            currentZoom = max(1.0, min(currentZoom, 5.0))
                        }
                )
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: gestureOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: gestureZoom)
                .animation(.easeOut(duration: 0.2), value: currentZoom)
            
            VStack {
                Spacer()
                Button(action: {
                    isLocked.toggle()
                }) {
                    Text(isLocked ? "解除" : "固定")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 100, height: 30)
                        .background(isLocked ? Color.red.opacity(0.3) : Color.blue.opacity(0.3) )
                        .cornerRadius(15)
                        .shadow(radius: 5)
                }
                .padding(.bottom, -20)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var isLocked: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.renderOptions.insert(.disableGroundingShadows)
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        let textContainer = Entity()
        let targetText = "北海道函館市亀田中野町一一六番地二"
        
        let lineThickness: Float = 0.0005
        let fixedLineSpacing: Float = 0.010 // 文字間隔（1cm）
        
        // 🌟 左右のレイアウト用のX座標を設定
        let leftXOffset: Float = -0.015  // 左側：お手本（-1.5cm）
        let rightXOffset: Float = 0.015  // 右側：枠とガイド（+1.5cm）
        
        var currentY: Float = 0.0
        
        let uiFont = UIFont(name: "KleeOne-Regular", size: 0.010)
                  ?? UIFont(name: "HiraMinProN-W6", size: 0.010)
                  ?? .systemFont(ofSize: 0.015, weight: .bold)
        
        let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, 100, nil)
        
        var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8))
        textMaterial.blending = .transparent(opacity: 1.0)
        
        for char in targetText {
            // 文字の幅と高さを計算
            let metrics = getCharacterMetrics(char: char, font: ctFont)
            
            // ==========================================
            // 🎨 ① 左側：お手本文字の描画
            // ==========================================
            let charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
            let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
            let charBounds = charEntity.visualBounds(relativeTo: nil)
            
            charEntity.position = [
                leftXOffset - charBounds.center.x,
                currentY - charBounds.center.y,
                0.001
            ]
            textContainer.addChild(charEntity)
            
            // ==========================================
            // 🎨 ② 右側：シンプルな文字の枠（長方形）
            // ==========================================
            let frameEntity = createRectangularFrame(
                width: metrics.width,
                height: metrics.height,
                thickness: lineThickness,
                color: UIColor.gray.withAlphaComponent(0.4) // 枠は邪魔にならない薄いグレー
            )
            frameEntity.position = [rightXOffset, currentY, 0]
            textContainer.addChild(frameEntity)
            
            // ==========================================
            // 🎨 ③ 右側：KanjiVGベースのガイド線（枠の中）
            // ==========================================
            let guideType = getKanjiVGMockGuide(for: char)
            let guideHeight = metrics.height // 🌟 ガイド線の長さを文字枠の高さに合わせる
            
            if case let .henTsukuri(splitX) = guideType {
                let boundaryLine = createLineEntity(
                    from: SIMD3<Float>(rightXOffset + splitX, currentY + guideHeight / 2, 0),
                    to: SIMD3<Float>(rightXOffset + splitX, currentY - guideHeight / 2, 0),
                    thickness: lineThickness,
                    color: UIColor.blue.withAlphaComponent(0.8)
                )
                textContainer.addChild(boundaryLine)
            }
            else if case let .center(centerX) = guideType {
                let centerLine = createLineEntity(
                    from: SIMD3<Float>(rightXOffset + centerX, currentY + guideHeight / 2, 0),
                    to: SIMD3<Float>(rightXOffset + centerX, currentY - guideHeight / 2, 0),
                    thickness: lineThickness,
                    color: UIColor.green.withAlphaComponent(0.8)
                )
                textContainer.addChild(centerLine)
            }
            
            // 次の文字へ
            currentY -= fixedLineSpacing
        }
        
        // まとめた箱の中心を原点に合わせる
        let totalBounds = textContainer.visualBounds(relativeTo: nil)
        textContainer.position = -totalBounds.center
        
        // 文字を寝かせる処理
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
// 📦 各種計算・生成関数
// ==========================================

/// 🌟 更新：文字の外接矩形（バウンディングボックス）の幅と高さのみを取得する関数
func getCharacterMetrics(char: Character, font: CTFont) -> (width: Float, height: Float) {
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    let uniChars = Array(String(char).utf16)
    let success = CTFontGetGlyphsForCharacters(font, uniChars, &glyphs, 1)
    
    guard success, let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        return (0.015, 0.015)
    }
    
    let bounds = path.boundingBoxOfPath
    let arScale: CGFloat = 0.00010
    
    let width = Float(bounds.width * arScale)
    let height = Float(bounds.height * arScale)
    
    // 最低でも1.5mm角のサイズを保証する
    return (max(width, 0.0015), max(height, 0.0015))
}

/// ガイドの種類を定義するEnum
enum GuideType {
    case henTsukuri(splitX: Float)
    case center(centerX: Float)
    case none
}

/// KanjiVGのデータから計算された「境界線」の位置を返すモック関数
func getKanjiVGMockGuide(for char: Character) -> GuideType {
    switch char {
    case "海": return .henTsukuri(splitX: -0.0015)
    case "館": return .henTsukuri(splitX: -0.001)
    case "町": return .henTsukuri(splitX: -0.0005)
    case "野": return .henTsukuri(splitX: -0.001)
        
    case "北": return .center(centerX: 0.0)
    case "中": return .center(centerX: 0.0)
        
    default: return .none
    }
}

// 線を描画する関数
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

/// 🌟 新規：シンプルな四角形（枠）を描画する関数
func createRectangularFrame(width: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity()
    let w = width / 2
    let h = height / 2
    
    let topLeft = SIMD3<Float>(-w, h, 0)
    let topRight = SIMD3<Float>(w, h, 0)
    let bottomLeft = SIMD3<Float>(-w, -h, 0)
    let bottomRight = SIMD3<Float>(w, -h, 0)
    
    let lines = [
        (topLeft, topRight), (topRight, bottomRight),
        (bottomRight, bottomLeft), (bottomLeft, topLeft)
    ]
    
    for lp in lines {
        frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color, opacity: color.cgColor.alpha))
    }
    
    return frame
}

#Preview {
    ContentView()
}
