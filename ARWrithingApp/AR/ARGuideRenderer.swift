import RealityKit
import UIKit
import CoreText

class ARGuideRenderer {
    // 🌟 基準となる固定サイズ（常にこのサイズで1度だけ作る）
    static let referenceSize: Float = 0.0105
    
    // 引数から baseSize を消去しました
    static func createGuideEntity(modes: Set<GuideMode>) -> Entity {
        let textContainer = Entity()
        let targetText = "北海道函館市亀田中野町一一六番地二"
        
        let fixedBoxSize: Float = referenceSize
        let fixedLineSpacing: Float = referenceSize
        let lineThickness: Float = referenceSize * 0.047
        let leftXOffset: Float = -referenceSize * 1.4
        let rightXOffset: Float = referenceSize * 1.4
        let dotRadius: Float = referenceSize * 0.076
        let dashLen: Float = referenceSize * 0.076
        
        let fontSize = CGFloat(referenceSize * 0.95)
        let uiFont = UIFont(name: "HiraMinProN-W3", size: fontSize) ?? UIFont(name: "HiraMinProN-W6", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .regular)
        let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, 100, nil)
        
        var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8)); textMaterial.blending = .transparent(opacity: 1.0)
        var traceMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.2)); traceMaterial.blending = .transparent(opacity: 1.0)
        let gaikeiShapes: [GuideShape] = [.triangle, .square, .square, .square, .square, .inv_triangle, .trapezoid, .square, .tall_rect, .square, .inv_triangle, .wide_rect, .wide_rect, .triangle, .square, .trapezoid, .wide_rect]
        let baseAlpha: CGFloat = 0.15
        
        var currentY: Float = 0.0
        
        for (index, char) in targetText.enumerated() {
            let charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
            let charBounds = charEntityVisualBounds(mesh: charMesh)
            
            let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
            charEntity.position = [leftXOffset - charBounds.x, currentY - charBounds.y, 0.001]
            textContainer.addChild(charEntity)
            
            if modes.contains(.nazoru) {
                let traceEntity = ModelEntity(mesh: charMesh, materials: [traceMaterial])
                traceEntity.position = [rightXOffset - charBounds.x, currentY - charBounds.y, 0.001]
                textContainer.addChild(traceEntity)
            }
            
            let offsets = [leftXOffset, rightXOffset]
            for offset in offsets {
                let frameEntity = createRectangularFrame(width: fixedBoxSize, height: fixedBoxSize, thickness: lineThickness, color: UIColor.gray.withAlphaComponent(baseAlpha))
                frameEntity.position = [offset, currentY, 0]
                textContainer.addChild(frameEntity)
                
                let crosshairColor = UIColor.gray.withAlphaComponent(baseAlpha)
                let vDashedLine = createDashedLineEntity(from: SIMD3<Float>(offset, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(offset, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 0.8, color: crosshairColor, dashLength: dashLen, gapLength: dashLen)
                let hDashedLine = createDashedLineEntity(from: SIMD3<Float>(offset - fixedBoxSize / 2, currentY, 0), to: SIMD3<Float>(offset + fixedBoxSize / 2, currentY, 0), thickness: lineThickness * 0.8, color: crosshairColor, dashLength: dashLen, gapLength: dashLen)
                textContainer.addChild(vDashedLine); textContainer.addChild(hDashedLine)
                
                if modes.contains(.gaikei) {
                    let shape = gaikeiShapes[index % gaikeiShapes.count]
                    var shapeW = fixedBoxSize, shapeH = fixedBoxSize
                    if shape == .wide_rect { shapeH = fixedBoxSize * 0.45 } else if shape == .tall_rect { shapeW = fixedBoxSize * 0.6 }
                    let gaikeiFrame = createGuideFrame(shape: shape, width: shapeW, height: shapeH, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))
                    gaikeiFrame.position = [offset, currentY, 0]
                    textContainer.addChild(gaikeiFrame)
                }
                
                if modes.contains(.daikei) {
                    let metrics = getCharacterMetrics(char: char, font: ctFont)
                    let daikeiFrame = createDynamicTrapezoid(topWidth: metrics.topWidth, bottomWidth: metrics.bottomWidth, height: metrics.height, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))
                    daikeiFrame.position = [offset, currentY, 0]
                    textContainer.addChild(daikeiFrame)
                }
                
                if modes.contains(.henTsukuri) {
                    let guideType = KanjiVGManager.shared.getGuide(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    if case let .henTsukuri(splitX) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(offset + splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(offset + splitX, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))) }
                    else if case let .center(centerX) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(offset + centerX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(offset + centerX, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))) }
                    else if case let .shinnyo(splitX, bottomY) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(offset + splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(offset + splitX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))); textContainer.addChild(createLineEntity(from: SIMD3<Float>(offset + splitX, currentY + bottomY, 0), to: SIMD3<Float>(offset + fixedBoxSize / 2, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))) }
                    else if case let .kamae(leftX, rightX, topY, bottomY) = guideType { textContainer.addChild(createLineEntity(from: SIMD3<Float>(offset + leftX, currentY + topY, 0), to: SIMD3<Float>(offset + leftX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))); textContainer.addChild(createLineEntity(from: SIMD3<Float>(offset + rightX, currentY + topY, 0), to: SIMD3<Float>(offset + rightX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))); textContainer.addChild(createLineEntity(from: SIMD3<Float>(offset + leftX, currentY + bottomY, 0), to: SIMD3<Float>(offset + rightX, currentY + bottomY, 0), thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))) }
                }
                
                if modes.contains(.shiten) {
                    let strokeStarts = KanjiVGManager.shared.getStrokeStarts(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    for point in strokeStarts {
                        let dotMesh = MeshResource.generateSphere(radius: dotRadius * 0.75)
                        var dotMat = UnlitMaterial(color: UIColor.red.withAlphaComponent(baseAlpha)); dotMat.blending = .transparent(opacity: 1.0)
                        let dotEntity = ModelEntity(mesh: dotMesh, materials: [dotMat])
                        dotEntity.position = [offset + point.x, currentY + point.y, 0.0002]
                        textContainer.addChild(dotEntity)
                    }
                }
                
                if modes.contains(.koten) {
                    let intersections = KanjiVGManager.shared.getIntersections(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    for point in intersections {
                        let dotMesh = MeshResource.generateSphere(radius: dotRadius)
                        var dotMat = UnlitMaterial(color: UIColor.magenta.withAlphaComponent(baseAlpha)); dotMat.blending = .transparent(opacity: 1.0)
                        let dotEntity = ModelEntity(mesh: dotMesh, materials: [dotMat])
                        dotEntity.position = [offset + point.x, currentY + point.y, 0.0002]
                        textContainer.addChild(dotEntity)
                    }
                }
            }
            
            currentY -= fixedLineSpacing
        }
        
        let totalBounds = textContainer.visualBounds(relativeTo: nil)
        textContainer.position = -totalBounds.center
        
        let flatWrapper = Entity()
        flatWrapper.addChild(textContainer)
        flatWrapper.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        
        // 🌟 マネージャーが後で探せるように「名前」をつけておく
        flatWrapper.name = "GuideWrapper"
        return flatWrapper
    }
    
    private static func charEntityVisualBounds(mesh: MeshResource) -> SIMD2<Float> {
        let dummyEntity = ModelEntity(mesh: mesh)
        let bounds = dummyEntity.visualBounds(relativeTo: nil)
        return SIMD2<Float>(bounds.center.x, bounds.center.y)
    }
}
