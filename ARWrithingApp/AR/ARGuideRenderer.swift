import RealityKit
import UIKit
import CoreText

class ARGuideRenderer {
    static func createGuideEntity(mode: GuideMode) -> Entity {
        let textContainer = Entity()
        let targetText = "北海道函館市亀田中野町一一六番地二"
        
        let lineThickness: Float = 0.0005
        let fixedLineSpacing: Float = 0.0105
        let fixedBoxSize: Float = 0.0105
        let leftXOffset: Float = -0.015, rightXOffset: Float = 0.015
        var currentY: Float = 0.0
        
        let uiFont = UIFont(name: "HiraMinProN-W3", size: 0.010) ?? UIFont(name: "HiraMinProN-W6", size: 0.010) ?? .systemFont(ofSize: 0.015, weight: .regular)
        let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, 100, nil)
        var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8)); textMaterial.blending = .transparent(opacity: 1.0)
        var traceMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.2)); traceMaterial.blending = .transparent(opacity: 1.0)
        let gaikeiShapes: [GuideShape] = [.triangle, .square, .square, .square, .square, .inv_triangle, .trapezoid, .square, .tall_rect, .square, .inv_triangle, .wide_rect, .wide_rect, .triangle, .square, .trapezoid, .wide_rect]
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
        
        let totalBounds = textContainer.visualBounds(relativeTo: nil)
        textContainer.position = -totalBounds.center
        
        let flatWrapper = Entity()
        flatWrapper.addChild(textContainer)
        flatWrapper.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        
        return flatWrapper
    }
}
