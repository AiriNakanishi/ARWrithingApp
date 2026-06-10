import SwiftUI
import RealityKit
import ARKit
import CoreText

// 🌟 モードに「始点」を追加
enum GuideMode: String, CaseIterable, Identifiable {
    case nazoru = "なぞる"
    case gaikei = "外形"
    case daikei = "台形"
    case henTsukuri = "へんとつくり"
    case shiten = "始点"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    @State private var isLocked = false
    @State private var selectedMode: GuideMode = .shiten // 🌟 テスト用に初期値を「始点」に
    
    @State private var currentZoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    let baseParallax = CGSize(width: 30, height: 30)
    
    var body: some View {
        ZStack {
            ARViewContainer(isLocked: $isLocked, selectedMode: selectedMode)
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
                
                VStack(spacing: 15) {
                    Picker("ガイドモード", selection: $selectedMode) {
                        ForEach(GuideMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .background(Color(UIColor.systemBackground).opacity(0.7))
                    .cornerRadius(8)
                    
                    Button(action: {
                        isLocked.toggle()
                    }) {
                        Text(isLocked ? "解除" : "固定")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 120, height: 35)
                            .background(isLocked ? Color.red.opacity(0.4) : Color.blue.opacity(0.4) )
                            .cornerRadius(15)
                            .shadow(radius: 5)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
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
            if currentRenderedMode == mode && isLocked { return }
            guard let anchor = cursorAnchor else { return }
            
            anchor.children.removeAll()
            currentRenderedMode = mode
            
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
            let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, 100, nil)
            
            var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8))
            textMaterial.blending = .transparent(opacity: 1.0)
            
            var traceMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.2))
            traceMaterial.blending = .transparent(opacity: 1.0)
            
            let gaikeiShapes: [GuideShape] = [
                .triangle, .square, .square, .square, .square, .inv_triangle, .trapezoid,
                .square, .tall_rect, .square, .inv_triangle, .wide_rect, .wide_rect,
                .triangle, .square, .trapezoid, .wide_rect
            ]
            
            for (index, char) in targetText.enumerated() {
                // ① 左側のお手本
                let charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
                let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
                let charBounds = charEntity.visualBounds(relativeTo: nil)
                
                charEntity.position = [leftXOffset - charBounds.center.x, currentY - charBounds.center.y, 0.001]
                textContainer.addChild(charEntity)
                
                // ② 右側の十字ノート枠
                let frameEntity = createRectangularFrame(width: fixedBoxSize, height: fixedBoxSize, thickness: lineThickness, color: UIColor.gray.withAlphaComponent(0.3))
                frameEntity.position = [rightXOffset, currentY, 0]
                textContainer.addChild(frameEntity)
                
                let crosshairColor = UIColor.gray.withAlphaComponent(0.4)
                let vDashedLine = createDashedLineEntity(from: SIMD3<Float>(rightXOffset, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(rightXOffset, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 0.8, color: crosshairColor)
                let hDashedLine = createDashedLineEntity(from: SIMD3<Float>(rightXOffset - fixedBoxSize / 2, currentY, 0), to: SIMD3<Float>(rightXOffset + fixedBoxSize / 2, currentY, 0), thickness: lineThickness * 0.8, color: crosshairColor)
                textContainer.addChild(vDashedLine)
                textContainer.addChild(hDashedLine)
                
                // ③ モードごとの描画
                switch mode {
                case .nazoru:
                    let traceEntity = ModelEntity(mesh: charMesh, materials: [traceMaterial])
                    traceEntity.position = [rightXOffset - charBounds.center.x, currentY - charBounds.center.y, 0.001]
                    textContainer.addChild(traceEntity)
                    
                case .gaikei:
                    let shape = gaikeiShapes[index % gaikeiShapes.count]
                    var shapeW = fixedBoxSize
                    var shapeH = fixedBoxSize
                    if shape == .wide_rect { shapeH = fixedBoxSize * 0.45 }
                    else if shape == .tall_rect { shapeW = fixedBoxSize * 0.6 }
                    
                    let gaikeiFrame = createGuideFrame(shape: shape, width: shapeW, height: shapeH, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(0.4))
                    gaikeiFrame.position = [rightXOffset, currentY, 0]
                    textContainer.addChild(gaikeiFrame)
                    
                case .daikei:
                    let metrics = getCharacterMetrics(char: char, font: ctFont)
                    let daikeiFrame = createDynamicTrapezoid(topWidth: metrics.topWidth, bottomWidth: metrics.bottomWidth, height: metrics.height, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(0.4))
                    daikeiFrame.position = [rightXOffset, currentY, 0]
                    textContainer.addChild(daikeiFrame)
                    
                case .henTsukuri:
                    let guideType = KanjiVGManager.shared.getGuide(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    let drawGuides = { (baseX: Float) in
                        if case let .henTsukuri(splitX) = guideType {
                            let boundaryLine = createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(baseX + splitX, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(0.4))
                            textContainer.addChild(boundaryLine)
                        } else if case let .center(centerX) = guideType {
                            let centerLine = createLineEntity(from: SIMD3<Float>(baseX + centerX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(baseX + centerX, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 1.5, color: UIColor.green.withAlphaComponent(0.4))
                            textContainer.addChild(centerLine)
                        } else if case let .shinnyo(splitX, bottomY) = guideType {
                            let vLine = createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(baseX + splitX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.orange.withAlphaComponent(0.4))
                            let hLine = createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + bottomY, 0), to: SIMD3<Float>(baseX + fixedBoxSize / 2, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.orange.withAlphaComponent(0.4))
                            textContainer.addChild(vLine)
                            textContainer.addChild(hLine)
                        } else if case let .kamae(leftX, rightX, topY, bottomY) = guideType {
                            let leftLine = createLineEntity(from: SIMD3<Float>(baseX + leftX, currentY + topY, 0), to: SIMD3<Float>(baseX + leftX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(0.4))
                            let rightLine = createLineEntity(from: SIMD3<Float>(baseX + rightX, currentY + topY, 0), to: SIMD3<Float>(baseX + rightX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(0.4))
                            let bottomLine = createLineEntity(from: SIMD3<Float>(baseX + leftX, currentY + bottomY, 0), to: SIMD3<Float>(baseX + rightX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(0.4))
                            textContainer.addChild(leftLine)
                            textContainer.addChild(rightLine)
                            textContainer.addChild(bottomLine)
                        }
                    }
                    drawGuides(rightXOffset)
                    drawGuides(leftXOffset)
                    
                case .shiten:
                                    // 🌟 5. 始点：一画ごとの始まりに半透明の赤いドット（球体）を配置
                                    let strokeStarts = KanjiVGManager.shared.getStrokeStarts(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                                    let drawDots = { (baseX: Float) in
                                        for point in strokeStarts {
                                            let dotMesh = MeshResource.generateSphere(radius: 0.0006) // 0.6ミリの小さな球
                                            
                                            // 🌟 変更ポイント：0.8だった透明度を、他のガイドと同じ 0.4 に下げて透けさせました
                                            var dotMat = UnlitMaterial(color: UIColor.red.withAlphaComponent(0.4))
                                            dotMat.blending = .transparent(opacity: 1.0)
                                            let dotEntity = ModelEntity(mesh: dotMesh, materials: [dotMat])
                                            
                                            // 枠の中の正しい位置に配置（ちらつき防止のため0.0002浮かせます）
                                            dotEntity.position = [baseX + point.x, currentY + point.y, 0.0002]
                                            textContainer.addChild(dotEntity)
                                        }
                                    }
                                    drawDots(rightXOffset)
                                    drawDots(leftXOffset)
                }
                
                currentY -= fixedLineSpacing
            }
            
            let totalBounds = textContainer.visualBounds(relativeTo: nil)
            textContainer.position = -totalBounds.center
            
            let flatWrapper = Entity()
            flatWrapper.addChild(textContainer)
            flatWrapper.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            
            anchor.addChild(flatWrapper)
        }
        
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
// 📦 統合ヘルパー・図形生成関数スタック
// ==========================================
enum GuideShape { case square, triangle, inv_triangle, rhombus, trapezoid, tall_rect, wide_rect }

func getCharacterMetrics(char: Character, font: CTFont) -> (topWidth: Float, bottomWidth: Float, height: Float) {
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    let uniChars = Array(String(char).utf16)
    let success = CTFontGetGlyphsForCharacters(font, uniChars, &glyphs, 1)
    guard success, let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return (0.012, 0.012, 0.012) }
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
            if p.y >= midY { topMinX = min(topMinX, p.x); topMaxX = max(topMaxX, p.x) }
            else { bottomMinX = min(bottomMinX, p.x); bottomMaxX = max(bottomMaxX, p.x) }
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

func createLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor) -> ModelEntity {
    let dx = p2.x - p1.x, dy = p2.y - p1.y
    let length = sqrt(dx*dx + dy*dy)
    let mesh = MeshResource.generateBox(size: [length, thickness, 0.0001])
    var material = UnlitMaterial(color: color)
    if color.cgColor.alpha < 1.0 { material.blending = .transparent(opacity: 1.0) }
    let line = ModelEntity(mesh: mesh, materials: [material])
    line.position = [(p1.x + p2.x) / 2, (p1.y + p2.y) / 2, 0]
    line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1])
    return line
}

func createDashedLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor, dashLength: Float = 0.0008, gapLength: Float = 0.0008) -> Entity {
    let parentEntity = Entity()
    let dx = p2.x - p1.x, dy = p2.y - p1.y
    let totalLength = sqrt(dx*dx + dy*dy)
    let dirX = dx / totalLength, dirY = dy / totalLength
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
    let w = width / 2, h = height / 2
    let topLeft = SIMD3<Float>(-w, h, 0), topRight = SIMD3<Float>(w, h, 0)
    let bottomLeft = SIMD3<Float>(-w, -h, 0), bottomRight = SIMD3<Float>(w, -h, 0)
    let lines = [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)]
    for lp in lines { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
    return frame
}

func createGuideFrame(shape: GuideShape, width: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity()
    let top = SIMD3<Float>(0, height / 2, 0), bottom = SIMD3<Float>(0, -height / 2, 0)
    let topLeft = SIMD3<Float>(-width / 2, height / 2, 0), topRight = SIMD3<Float>(width / 2, height / 2, 0)
    let bottomLeft = SIMD3<Float>(-width / 2, -height / 2, 0), bottomRight = SIMD3<Float>(width / 2, -height / 2, 0)
    let left = SIMD3<Float>(-width / 2, 0, 0), right = SIMD3<Float>(width / 2, 0, 0)
    let trapezoidTopLeft = SIMD3<Float>(-width / 4, height / 2, 0), trapezoidTopRight = SIMD3<Float>(width / 4, height / 2, 0)
    var lines: [(SIMD3<Float>, SIMD3<Float>)] = []
    switch shape {
    case .square, .tall_rect, .wide_rect: lines = [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)]
    case .triangle: lines = [(top, bottomRight), (bottomRight, bottomLeft), (bottomLeft, top)]
    case .inv_triangle: lines = [(topLeft, topRight), (topRight, bottom), (bottom, topLeft)]
    case .rhombus: lines = [(top, right), (right, bottom), (bottom, left), (left, top)]
    case .trapezoid: lines = [(trapezoidTopLeft, trapezoidTopRight), (trapezoidTopRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, trapezoidTopLeft)]
    }
    for lp in lines { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
    return frame
}

func createDynamicTrapezoid(topWidth: Float, bottomWidth: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity()
    let topLeft = SIMD3<Float>(-topWidth / 2, height / 2, 0), topRight = SIMD3<Float>(topWidth / 2, height / 2, 0)
    let bottomLeft = SIMD3<Float>(-bottomWidth / 2, -height / 2, 0), bottomRight = SIMD3<Float>(bottomWidth / 2, -height / 2, 0)
    let lines = [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)]
    for lp in lines { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
    return frame
}
