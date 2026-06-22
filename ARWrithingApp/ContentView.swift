import SwiftUI
import RealityKit
import ARKit
import CoreText

enum GuideMode: String, CaseIterable, Identifiable {
    case nazoru = "なぞる"
    case gaikei = "外形"
    case daikei = "台形"
    case henTsukuri = "へんとつくり"
    case shiten = "始点"
    case koten = "交点"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    @State private var isLocked = false
    @State private var selectedMode: GuideMode = .koten
    
    @State private var currentZoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    let baseParallax = CGSize(width: 0, height: 0)
    
    var body: some View {
        ZStack {
            ARViewContainer(isLocked: $isLocked, selectedMode: selectedMode)
                .scaleEffect(currentZoom * gestureZoom)
                .offset(x: baseParallax.width + currentOffset.width + gestureOffset.width, y: baseParallax.height + currentOffset.height + gestureOffset.height)
                .gesture(DragGesture().updating($gestureOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in currentOffset.width += value.translation.width; currentOffset.height += value.translation.height })
                .edgesIgnoringSafeArea(.all)
                .gesture(MagnificationGesture().updating($gestureZoom) { value, state, _ in state = value }
                    .onEnded { value in currentZoom *= value; currentZoom = max(1.0, min(currentZoom, 5.0)) })
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: gestureOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: gestureZoom)
                .animation(.easeOut(duration: 0.2), value: currentZoom)
            
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Picker("ガイドモード", selection: $selectedMode) {
                        ForEach(GuideMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal).background(Color(UIColor.systemBackground).opacity(0.7)).cornerRadius(8)
                    
                    Button(action: { isLocked.toggle() }) {
                        Text(isLocked ? "解除" : "固定")
                            .font(.title2).fontWeight(.semibold).foregroundColor(.white)
                            .padding().frame(width: 120, height: 35)
                            .background(isLocked ? Color.red.opacity(0.4) : Color.blue.opacity(0.4) )
                            .cornerRadius(15).shadow(radius: 5)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
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
        context.coordinator.isLocked = isLocked; context.coordinator.buildARScene(mode: selectedMode)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?; weak var cursorAnchor: AnchorEntity?
        var isLocked = false; var currentRenderedMode: GuideMode? = nil
        
        func buildARScene(mode: GuideMode) {
            if currentRenderedMode == mode { return }
            guard let anchor = cursorAnchor else { return }
            anchor.children.removeAll(); currentRenderedMode = mode
            
            let textContainer = Entity()
            let targetText = "北海道函館市亀田中野町一一六番地二"
            let lineThickness: Float = 0.0005
            
            let fixedLineSpacing: Float = 0.0105
            // 🌟 修正: 枠のサイズを行間と同じにして、重ならないようにピッタリ合わせました
            let fixedBoxSize: Float = 0.0105
            let leftXOffset: Float = -0.015, rightXOffset: Float = 0.015
            var currentY: Float = 0.0
            
            let uiFont = UIFont(name: "HiraMinProN-W3", size: 0.010) ?? UIFont(name: "HiraMinProN-W6", size: 0.010) ?? .systemFont(ofSize: 0.015, weight: .regular)
            let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, 100, nil)
            var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8)); textMaterial.blending = .transparent(opacity: 1.0)
            var traceMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.2)); traceMaterial.blending = .transparent(opacity: 1.0)
            let gaikeiShapes: [GuideShape] = [.triangle, .square, .square, .square, .square, .inv_triangle, .trapezoid, .square, .tall_rect, .square, .inv_triangle, .wide_rect, .wide_rect, .triangle, .square, .trapezoid, .wide_rect]
            
            // 🌟 全体的な透過度（Alpha）のベース値
            let baseAlpha: CGFloat = 0.15
            
            for (index, char) in targetText.enumerated() {
                let charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
                let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
                let charBounds = charEntity.visualBounds(relativeTo: nil)
                charEntity.position = [leftXOffset - charBounds.center.x, currentY - charBounds.center.y, 0.001]
                textContainer.addChild(charEntity)
                
                let frameEntity = createRectangularFrame(width: fixedBoxSize, height: fixedBoxSize, thickness: lineThickness, color: UIColor.gray.withAlphaComponent(baseAlpha))
                frameEntity.position = [rightXOffset, currentY, 0]
                textContainer.addChild(frameEntity)
                
                // 🌟 修正: 十字の点線の透明度を 0.15 に統一
                let crosshairColor = UIColor.gray.withAlphaComponent(baseAlpha)
                let vDashedLine = createDashedLineEntity(from: SIMD3<Float>(rightXOffset, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(rightXOffset, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 0.8, color: crosshairColor)
                let hDashedLine = createDashedLineEntity(from: SIMD3<Float>(rightXOffset - fixedBoxSize / 2, currentY, 0), to: SIMD3<Float>(rightXOffset + fixedBoxSize / 2, currentY, 0), thickness: lineThickness * 0.8, color: crosshairColor)
                textContainer.addChild(vDashedLine); textContainer.addChild(hDashedLine)
                
                switch mode {
                case .nazoru:
                    let traceEntity = ModelEntity(mesh: charMesh, materials: [traceMaterial])
                    traceEntity.position = [rightXOffset - charBounds.center.x, currentY - charBounds.center.y, 0.001]
                    textContainer.addChild(traceEntity)
                case .gaikei:
                    let shape = gaikeiShapes[index % gaikeiShapes.count]
                    var shapeW = fixedBoxSize, shapeH = fixedBoxSize
                    if shape == .wide_rect { shapeH = fixedBoxSize * 0.45 } else if shape == .tall_rect { shapeW = fixedBoxSize * 0.6 }
                    // 🌟 図形の透明度も統一
                    let gaikeiFrame = createGuideFrame(shape: shape, width: shapeW, height: shapeH, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))
                    gaikeiFrame.position = [rightXOffset, currentY, 0]
                    textContainer.addChild(gaikeiFrame)
                case .daikei:
                    let metrics = getCharacterMetrics(char: char, font: ctFont)
                    let daikeiFrame = createDynamicTrapezoid(topWidth: metrics.topWidth, bottomWidth: metrics.bottomWidth, height: metrics.height, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))
                    daikeiFrame.position = [rightXOffset, currentY, 0]
                    textContainer.addChild(daikeiFrame)
                case .henTsukuri:
                    let guideType = KanjiVGManager.shared.getGuide(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    let drawGuides = { (baseX: Float) in
                        if case let .henTsukuri(splitX) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(baseX + splitX, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))) }
                        else if case let .center(centerX) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(baseX + centerX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(baseX + centerX, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 1.5, color: UIColor.green.withAlphaComponent(baseAlpha))) }
                        else if case let .shinnyo(splitX, bottomY) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(baseX + splitX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.orange.withAlphaComponent(baseAlpha))); textContainer.addChild(createLineEntity(from: SIMD3<Float>(baseX + splitX, currentY + bottomY, 0), to: SIMD3<Float>(baseX + fixedBoxSize / 2, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.orange.withAlphaComponent(baseAlpha))) }
                        else if case let .kamae(leftX, rightX, topY, bottomY) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(baseX + leftX, currentY + topY, 0), to: SIMD3<Float>(baseX + leftX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(baseAlpha))); textContainer.addChild(createLineEntity(from: SIMD3<Float>(baseX + rightX, currentY + topY, 0), to: SIMD3<Float>(baseX + rightX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(baseAlpha))); textContainer.addChild(createLineEntity(from: SIMD3<Float>(baseX + leftX, currentY + bottomY, 0), to: SIMD3<Float>(baseX + rightX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.purple.withAlphaComponent(baseAlpha))) }
                    }
                    drawGuides(rightXOffset); drawGuides(leftXOffset)
                case .shiten:
                    let strokeStarts = KanjiVGManager.shared.getStrokeStarts(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    let drawDots = { (baseX: Float) in
                        for point in strokeStarts {
                            let dotMesh = MeshResource.generateSphere(radius: 0.0006)
                            // 🌟 修正: 始点のドットの透明度を 0.15 に統一
                            var dotMat = UnlitMaterial(color: UIColor.red.withAlphaComponent(baseAlpha)); dotMat.blending = .transparent(opacity: 1.0)
                            let dotEntity = ModelEntity(mesh: dotMesh, materials: [dotMat])
                            dotEntity.position = [baseX + point.x, currentY + point.y, 0.0002]
                            textContainer.addChild(dotEntity)
                        }
                    }
                    drawDots(rightXOffset); drawDots(leftXOffset)
                case .koten:
                    let intersections = KanjiVGManager.shared.getIntersections(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    let drawKoten = { (baseX: Float) in
                        for point in intersections {
                            let dotMesh = MeshResource.generateSphere(radius: 0.0008)
                            // 🌟 修正: 交点のドットの透明度を 0.15 に統一
                            var dotMat = UnlitMaterial(color: UIColor.magenta.withAlphaComponent(baseAlpha))
                            dotMat.blending = .transparent(opacity: 1.0)
                            let dotEntity = ModelEntity(mesh: dotMesh, materials: [dotMat])
                            dotEntity.position = [baseX + point.x, currentY + point.y, 0.0002]
                            textContainer.addChild(dotEntity)
                        }
                    }
                    drawKoten(rightXOffset); drawKoten(leftXOffset)
                }
                currentY -= fixedLineSpacing
            }
            
            let totalBounds = textContainer.visualBounds(relativeTo: nil); textContainer.position = -totalBounds.center
            let flatWrapper = Entity(); flatWrapper.addChild(textContainer); flatWrapper.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            anchor.addChild(flatWrapper)
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView, let cursorAnchor = cursorAnchor else { return }
            guard !isLocked else { return }
            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if let result = arView.raycast(from: screenCenter, allowing: .estimatedPlane, alignment: .horizontal).first {
                let hitPosition = result.worldTransform.columns.3
                cursorAnchor.position = SIMD3<Float>(hitPosition.x, hitPosition.y + 0.001, hitPosition.z)
                let dx = frame.camera.transform.columns.3.x - cursorAnchor.position.x, dz = frame.camera.transform.columns.3.z - cursorAnchor.position.z
                cursorAnchor.orientation = simd_quatf(angle: atan2(dx, dz), axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }
}

// ==========================================
// 📦 統合ヘルパー・図形生成関数スタック
// ==========================================
enum GuideShape { case square, triangle, inv_triangle, rhombus, trapezoid, tall_rect, wide_rect }

func getCharacterMetrics(char: Character, font: CTFont) -> (topWidth: Float, bottomWidth: Float, height: Float) {
    var glyphs = [CGGlyph](repeating: 0, count: 1); let uniChars = Array(String(char).utf16)
    guard CTFontGetGlyphsForCharacters(font, uniChars, &glyphs, 1), let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return (0.012, 0.012, 0.012) }
    let bounds = path.boundingBoxOfPath; let midY = bounds.midY
    var topMinX = bounds.maxX, topMaxX = bounds.minX, bottomMinX = bounds.maxX, bottomMaxX = bounds.minX
    path.applyWithBlock { elementPointer in
        let element = elementPointer.pointee, points = element.points, numPoints: Int
        switch element.type { case .moveToPoint, .addLineToPoint: numPoints = 1; case .addQuadCurveToPoint: numPoints = 2; case .addCurveToPoint: numPoints = 3; default: numPoints = 0 }
        for i in 0..<numPoints { let p = points[i]; if p.y >= midY { topMinX = min(topMinX, p.x); topMaxX = max(topMaxX, p.x) } else { bottomMinX = min(bottomMinX, p.x); bottomMaxX = max(bottomMaxX, p.x) } }
    }
    if topMinX > topMaxX { topMinX = bounds.midX; topMaxX = bounds.midX }; if bottomMinX > bottomMaxX { bottomMinX = bounds.midX; bottomMaxX = bounds.midX }
    return (max(Float((topMaxX - topMinX) * 0.00010), 0.0015), max(Float((bottomMaxX - bottomMinX) * 0.00010), 0.0015), max(Float(bounds.height * 0.00010), 0.0015))
}
func createLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor) -> ModelEntity {
    let dx = p2.x - p1.x, dy = p2.y - p1.y, mesh = MeshResource.generateBox(size: [sqrt(dx*dx + dy*dy), thickness, 0.0001])
    var material = UnlitMaterial(color: color); if color.cgColor.alpha < 1.0 { material.blending = .transparent(opacity: 1.0) }
    let line = ModelEntity(mesh: mesh, materials: [material]); line.position = [(p1.x + p2.x) / 2, (p1.y + p2.y) / 2, 0]; line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1]); return line
}
func createDashedLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor, dashLength: Float = 0.0008, gapLength: Float = 0.0008) -> Entity {
    let parentEntity = Entity(), dx = p2.x - p1.x, dy = p2.y - p1.y, totalLength = sqrt(dx*dx + dy*dy), dirX = dx / totalLength, dirY = dy / totalLength; var currentDist: Float = 0
    while currentDist < totalLength {
        let segmentEnd = min(currentDist + dashLength, totalLength), startPoint = SIMD3<Float>(p1.x + dirX * currentDist, p1.y + dirY * currentDist, p1.z), endPoint = SIMD3<Float>(p1.x + dirX * segmentEnd, p1.y + dirY * segmentEnd, p1.z)
        let line = ModelEntity(mesh: MeshResource.generateBox(size: [segmentEnd - currentDist, thickness, 0.0001]), materials: [UnlitMaterial(color: color)]); line.position = [(startPoint.x + endPoint.x) / 2, (startPoint.y + endPoint.y) / 2, 0]; line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1]); parentEntity.addChild(line); currentDist += dashLength + gapLength
    }
    return parentEntity
}
func createRectangularFrame(width: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity(), w = width / 2, h = height / 2, topLeft = SIMD3<Float>(-w, h, 0), topRight = SIMD3<Float>(w, h, 0), bottomLeft = SIMD3<Float>(-w, -h, 0), bottomRight = SIMD3<Float>(w, -h, 0)
    for lp in [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)] { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
    return frame
}
func createGuideFrame(shape: GuideShape, width: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity(), top = SIMD3<Float>(0, height / 2, 0), bottom = SIMD3<Float>(0, -height / 2, 0), topLeft = SIMD3<Float>(-width / 2, height / 2, 0), topRight = SIMD3<Float>(width / 2, height / 2, 0), bottomLeft = SIMD3<Float>(-width / 2, -height / 2, 0), bottomRight = SIMD3<Float>(width / 2, -height / 2, 0), left = SIMD3<Float>(-width / 2, 0, 0), right = SIMD3<Float>(width / 2, 0, 0), trapezoidTopLeft = SIMD3<Float>(-width / 4, height / 2, 0), trapezoidTopRight = SIMD3<Float>(width / 4, height / 2, 0); var lines: [(SIMD3<Float>, SIMD3<Float>)] = []
    switch shape { case .square, .tall_rect, .wide_rect: lines = [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)]; case .triangle: lines = [(top, bottomRight), (bottomRight, bottomLeft), (bottomLeft, top)]; case .inv_triangle: lines = [(topLeft, topRight), (topRight, bottom), (bottom, topLeft)]; case .rhombus: lines = [(top, right), (right, bottom), (bottom, left), (left, top)]; case .trapezoid: lines = [(trapezoidTopLeft, trapezoidTopRight), (trapezoidTopRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, trapezoidTopLeft)] }
    for lp in lines { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
    return frame
}
func createDynamicTrapezoid(topWidth: Float, bottomWidth: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
    let frame = Entity(), topLeft = SIMD3<Float>(-topWidth / 2, height / 2, 0), topRight = SIMD3<Float>(topWidth / 2, height / 2, 0), bottomLeft = SIMD3<Float>(-bottomWidth / 2, -height / 2, 0), bottomRight = SIMD3<Float>(bottomWidth / 2, -height / 2, 0)
    for lp in [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)] { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
    return frame
}
