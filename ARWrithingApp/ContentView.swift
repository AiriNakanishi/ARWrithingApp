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
        let fixedLineSpacing: Float = 0.012
        
        let leftXOffset: Float = -0.015
        let rightXOffset: Float = 0.015
        let fixedBoxSize: Float = 0.012
        
        var currentY: Float = 0.0
        
        let uiFont = UIFont(name: "KleeOne-Regular", size: 0.010)
                  ?? UIFont(name: "HiraMinProN-W6", size: 0.010)
                  ?? .systemFont(ofSize: 0.015, weight: .bold)
        
        var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8))
        textMaterial.blending = .transparent(opacity: 1.0)
        
        for char in targetText {
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
            // 🎨 ② 右側：均等な正方形の枠 ＋ 点線の十字ガイド
            // ==========================================
            let frameEntity = createRectangularFrame(
                width: fixedBoxSize,
                height: fixedBoxSize,
                thickness: lineThickness,
                color: UIColor.gray.withAlphaComponent(0.3)
            )
            frameEntity.position = [rightXOffset, currentY, 0]
            textContainer.addChild(frameEntity)
            
            let crosshairColor = UIColor.gray.withAlphaComponent(0.4)
            let vDashedLine = createDashedLineEntity(
                from: SIMD3<Float>(rightXOffset, currentY + fixedBoxSize / 2, 0),
                to: SIMD3<Float>(rightXOffset, currentY - fixedBoxSize / 2, 0),
                thickness: lineThickness * 0.8, color: crosshairColor
            )
            let hDashedLine = createDashedLineEntity(
                from: SIMD3<Float>(rightXOffset - fixedBoxSize / 2, currentY, 0),
                to: SIMD3<Float>(rightXOffset + fixedBoxSize / 2, currentY, 0),
                thickness: lineThickness * 0.8, color: crosshairColor
            )
            textContainer.addChild(vDashedLine)
            textContainer.addChild(hDashedLine)
            
            // ==========================================
            // 🎨 ③ 動的ガイド線の描画（透明度0.4に設定）
            // ==========================================
            let guideType = KanjiVGManager.shared.getGuide(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
            
            let drawGuides = { (baseX: Float) in
                if case let .henTsukuri(splitX) = guideType {
                    let boundaryLine = createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + fixedBoxSize / 2, 0),
                                                        to: SIMD3<Float>(baseX + splitX, currentY - fixedBoxSize / 2, 0),
                                                        thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(0.4))
                    textContainer.addChild(boundaryLine)
                }
                else if case let .center(centerX) = guideType {
                    let centerLine = createLineEntity(from: SIMD3<Float>(baseX + centerX, currentY + fixedBoxSize / 2, 0),
                                                      to: SIMD3<Float>(baseX + centerX, currentY - fixedBoxSize / 2, 0),
                                                      thickness: lineThickness * 1.5, color: UIColor.green.withAlphaComponent(0.4))
                    textContainer.addChild(centerLine)
                }
                else if case let .shinnyo(splitX, bottomY) = guideType {
                    let vLine = createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + fixedBoxSize / 2, 0),
                                                 to: SIMD3<Float>(baseX + splitX, currentY + bottomY, 0),
                                                 thickness: lineThickness * 1.5, color: UIColor.orange.withAlphaComponent(0.4))
                    let hLine = createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + bottomY, 0),
                                                 to: SIMD3<Float>(baseX + fixedBoxSize / 2, currentY + bottomY, 0),
                                                 thickness: lineThickness * 1.5, color: UIColor.orange.withAlphaComponent(0.4))
                    textContainer.addChild(vLine)
                    textContainer.addChild(hLine)
                }
                else if case let .kamae(leftX, rightX, topY, bottomY) = guideType {
                    let leftLine = createLineEntity(from: SIMD3<Float>(baseX + leftX, currentY + topY, 0),
                                                    to: SIMD3<Float>(baseX + leftX, currentY + bottomY, 0),
                                                    thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(0.4))
                    let rightLine = createLineEntity(from: SIMD3<Float>(baseX + rightX, currentY + topY, 0),
                                                     to: SIMD3<Float>(baseX + rightX, currentY + bottomY, 0),
                                                     thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(0.4))
                    let bottomLine = createLineEntity(from: SIMD3<Float>(baseX + leftX, currentY + bottomY, 0),
                                                      to: SIMD3<Float>(baseX + rightX, currentY + bottomY, 0),
                                                      thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(0.4))
                    textContainer.addChild(leftLine)
                    textContainer.addChild(rightLine)
                    textContainer.addChild(bottomLine)
                }
            }
            
            drawGuides(rightXOffset)
            drawGuides(leftXOffset)
            
            currentY -= fixedLineSpacing
        }
        
        let totalBounds = textContainer.visualBounds(relativeTo: nil)
        textContainer.position = -totalBounds.center
        
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

// 🌟 透明度バグを修正した描画関数
func createLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor) -> ModelEntity {
    let dx = p2.x - p1.x, dy = p2.y - p1.y
    let length = sqrt(dx*dx + dy*dy)
    let mesh = MeshResource.generateBox(size: [length, thickness, 0.0001])
    
    // カラーの透明度をそのままマテリアルに反映させるように修正
    var material = UnlitMaterial(color: color)
    if color.cgColor.alpha < 1.0 {
        material.blending = .transparent(opacity: 1.0)
    }
    
    let line = ModelEntity(mesh: mesh, materials: [material])
    line.position = [(p1.x + p2.x) / 2, (p1.y + p2.y) / 2, 0]
    line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1])
    return line
}

func createDashedLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor, dashLength: Float = 0.001, gapLength: Float = 0.001) -> Entity {
    let parentEntity = Entity()
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    let totalLength = sqrt(dx*dx + dy*dy)
    let dirX = dx / totalLength
    let dirY = dy / totalLength
    
    var currentDist: Float = 0
    while currentDist < totalLength {
        let segmentEnd = min(currentDist + dashLength, totalLength)
        let startPoint = SIMD3<Float>(p1.x + dirX * currentDist, p1.y + dirY * currentDist, p1.z)
        let endPoint = SIMD3<Float>(p1.x + dirX * segmentEnd, p1.y + dirY * segmentEnd, p1.z)
        
        let mesh = MeshResource.generateBox(size: [segmentEnd - currentDist, thickness, 0.0001])
        var material = UnlitMaterial(color: color)
        if color.cgColor.alpha < 1.0 { material.blending = .transparent(opacity: 1.0) }
        
        let line = ModelEntity(mesh: mesh, materials: [material])
        line.position = [(startPoint.x + endPoint.x) / 2, (startPoint.y + endPoint.y) / 2, 0]
        line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1])
        
        parentEntity.addChild(line)
        currentDist += dashLength + gapLength
    }
    return parentEntity
}

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
        frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color))
    }
    
    return frame
}
