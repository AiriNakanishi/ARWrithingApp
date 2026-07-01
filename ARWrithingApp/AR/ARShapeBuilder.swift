import RealityKit
import UIKit
import CoreText

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
