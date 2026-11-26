import RealityKit
import UIKit
import CoreText

enum GuideShape { case square, triangle, inv_triangle, rhombus, trapezoid, tall_rect, wide_rect }

class ARShapeBuilder {
    
    // =====================================================================
    // 🌟 1. 台形ガイド「描画用」のメトリクス計算
    // =====================================================================
    // 目的：文字全体をすっぽり包む、はみ出さない台形の「上辺・下辺・高さ」を測る
    // 仕組み：文字を画像化せず、フォントの「ベクターパス（線）」を直接なぞる。
    //     文字を「上下50%」にざっくり割り、上半分と下半分それぞれの最大幅を取得する。
    static func getTrapezoidMetrics(char: Character, font: CTFont) -> (topWidth: Float, bottomWidth: Float, height: Float) {
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        let uniChars = Array(String(char).utf16)
        
        guard CTFontGetGlyphsForCharacters(font, uniChars, &glyphs, 1),
              let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
            return (0.012, 0.012, 0.012)
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
            default: numPoints = 0
            }
            
            for i in 0..<numPoints {
                let p = points[i]
                // 💡 上下50%でざっくり分けて最大幅を記録（文字がはみ出さないようにするため）
                if p.y >= midY {
                    topMinX = min(topMinX, p.x)
                    topMaxX = max(topMaxX, p.x)
                } else {
                    bottomMinX = min(bottomMinX, p.x)
                    bottomMaxX = max(bottomMaxX, p.x)
                }
            }
        }
        
        if topMinX > topMaxX { topMinX = bounds.midX; topMaxX = bounds.midX }
        if bottomMinX > bottomMaxX { bottomMinX = bounds.midX; bottomMaxX = bounds.midX }
        
        return (
            max(Float((topMaxX - topMinX) * 0.00010), 0.0015),
            max(Float((bottomMaxX - bottomMinX) * 0.00010), 0.0015),
            max(Float(bounds.height * 0.00010), 0.0015)
        )
    }
    
    // =====================================================================
    // 🌟 2. 外形ガイド「分類用」のメトリクス計算（Python由来のロジック）
    // =====================================================================
    // 目的：文字が三角か、ひし形か、四角かなどの「特徴」を抽出する
    // 仕組み：文字を一度大きな画像にして二値化し、ピクセルを1つずつ調べる。
    //     「上下20%の局所的な幅」や「四隅の密度」を測り、形のすぼまり具合を計算する。
    static func getShapeClassificationMetrics(char: Character, uiFont: UIFont) -> (width: Float, height: Float, topWidth: Float, bottomWidth: Float, cornerRatio: Float) {
        
        // 解析用にフォントサイズを100にして文字潰れを防ぐ
        let analysisFont = UIFont(name: uiFont.fontName, size: 100) ?? .systemFont(ofSize: 100)
        let size = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return (0, 0, 0, 0, 1.0)
        }
        
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        
        let string = String(char)
        let attributes: [NSAttributedString.Key: Any] = [.font: analysisFont, .foregroundColor: UIColor.black]
        let textSize = string.size(withAttributes: attributes)
        let textRect = CGRect(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        string.draw(in: textRect, withAttributes: attributes)
        
        guard let cgImage = context.makeImage(),
              let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let pointer = CFDataGetBytePtr(pixelData) else {
            UIGraphicsEndImageContext()
            return (0, 0, 0, 0, 1.0)
        }
        UIGraphicsEndImageContext()
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        
        var xMin = width, xMax = 0
        var yMin = height, yMax = 0
        var activePixels: [(x: Int, y: Int)] = []
        
        // 画像を二値化して黒いピクセル（インク）を抽出
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (bytesPerRow * y) + (x * 4)
                let r = pointer[pixelIndex]
                if r < 128 {
                    if x < xMin { xMin = x }
                    if x > xMax { xMax = x }
                    if y < yMin { yMin = y }
                    if y > yMax { yMax = y }
                    activePixels.append((x: x, y: y))
                }
            }
        }
        
        if activePixels.isEmpty { return (0, 0, 0, 0, 1.0) }
        
        let w_raw = Float(xMax - xMin)
        let h_raw = Float(yMax - yMin)
        
        // 💡 上下20%の限界ラインを引く（特徴抽出のため）
        let topYLimit = Float(yMin) + h_raw * 0.202
        let botYLimit = Float(yMax) - h_raw * 0.202
        
        var topXMin = width, topXMax = 0
        var botXMin = width, botXMax = 0
        var cornersPixelCount = 0
        
        let cw = w_raw * 0.3
        let ch = h_raw * 0.3
        let cwLeft = Float(xMin) + cw
        let cwRight = Float(xMax) - cw
        let chTop = Float(yMin) + ch
        let chBot = Float(yMax) - ch
        
        for p in activePixels {
            let px = Float(p.x)
            let py = Float(p.y)
            
            if py < topYLimit {
                if p.x < topXMin { topXMin = p.x }
                if p.x > topXMax { topXMax = p.x }
            }
            if py > botYLimit {
                if p.x < botXMin { botXMin = p.x }
                if p.x > botXMax { botXMax = p.x }
            }
            
            let inTopLeft = (px < cwLeft) && (py < chTop)
            let inTopRight = (px > cwRight) && (py < chTop)
            let inBotLeft = (px < cwLeft) && (py > chBot)
            let inBotRight = (px > cwRight) && (py > chBot)
            
            if inTopLeft || inTopRight || inBotLeft || inBotRight {
                cornersPixelCount += 1
            }
        }
        
        let scale = Float(0.0105 / 100.0)
        let w = w_raw * scale
        let h = h_raw * scale
        let topW = (topXMax >= topXMin ? Float(topXMax - topXMin) : 0) * scale
        let botW = (botXMax >= botXMin ? Float(botXMax - botXMin) : 0) * scale
        let cornerRatio = Float(cornersPixelCount) / Float(activePixels.count)
        
        return (width: w, height: h, topWidth: topW, bottomWidth: botW, cornerRatio: cornerRatio)
    }

    // =====================================================================
    // 🌟 3. AR空間への描画用ツール（既存のまま）
    // =====================================================================
    static func createLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor) -> ModelEntity {
        let dx = p2.x - p1.x, dy = p2.y - p1.y, mesh = MeshResource.generateBox(size: [sqrt(dx*dx + dy*dy), thickness, 0.0001])
        var material = UnlitMaterial(color: color); if color.cgColor.alpha < 1.0 { material.blending = .transparent(opacity: 1.0) }
        let line = ModelEntity(mesh: mesh, materials: [material]); line.position = [(p1.x + p2.x) / 2, (p1.y + p2.y) / 2, 0]; line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1]); return line
    }

    static func createDashedLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>, thickness: Float, color: UIColor, dashLength: Float = 0.0008, gapLength: Float = 0.0008) -> Entity {
        let parentEntity = Entity(), dx = p2.x - p1.x, dy = p2.y - p1.y, totalLength = sqrt(dx*dx + dy*dy), dirX = dx / totalLength, dirY = dy / totalLength; var currentDist: Float = 0
        while currentDist < totalLength {
            let segmentEnd = min(currentDist + dashLength, totalLength), startPoint = SIMD3<Float>(p1.x + dirX * currentDist, p1.y + dirY * currentDist, p1.z), endPoint = SIMD3<Float>(p1.x + dirX * segmentEnd, p1.y + dirY * segmentEnd, p1.z)
            let line = ModelEntity(mesh: MeshResource.generateBox(size: [segmentEnd - currentDist, thickness, 0.0001]), materials: [UnlitMaterial(color: color)]); line.position = [(startPoint.x + endPoint.x) / 2, (startPoint.y + endPoint.y) / 2, 0]; line.orientation = simd_quatf(angle: atan2(dy, dx), axis: [0, 0, 1]); parentEntity.addChild(line); currentDist += dashLength + gapLength
        }
        return parentEntity
    }

    static func createRectangularFrame(width: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
        let frame = Entity(), w = width / 2, h = height / 2, topLeft = SIMD3<Float>(-w, h, 0), topRight = SIMD3<Float>(w, h, 0), bottomLeft = SIMD3<Float>(-w, -h, 0), bottomRight = SIMD3<Float>(w, -h, 0)
        for lp in [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)] { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
        return frame
    }

    static func createGuideFrame(shape: GuideShape, width: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
        let frame = Entity(), top = SIMD3<Float>(0, height / 2, 0), bottom = SIMD3<Float>(0, -height / 2, 0), topLeft = SIMD3<Float>(-width / 2, height / 2, 0), topRight = SIMD3<Float>(width / 2, height / 2, 0), bottomLeft = SIMD3<Float>(-width / 2, -height / 2, 0), bottomRight = SIMD3<Float>(width / 2, -height / 2, 0), left = SIMD3<Float>(-width / 2, 0, 0), right = SIMD3<Float>(width / 2, 0, 0), trapezoidTopLeft = SIMD3<Float>(-width / 4, height / 2, 0), trapezoidTopRight = SIMD3<Float>(width / 4, height / 2, 0); var lines: [(SIMD3<Float>, SIMD3<Float>)] = []
        switch shape {
        case .square, .tall_rect, .wide_rect:
            lines = [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)]
        case .triangle:
            lines = [(top, bottomRight), (bottomRight, bottomLeft), (bottomLeft, top)]
        case .inv_triangle:
            lines = [(topLeft, topRight), (topRight, bottom), (bottom, topLeft)]
        case .trapezoid:
            lines = [(trapezoidTopLeft, trapezoidTopRight), (trapezoidTopRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, trapezoidTopLeft)]
        case .rhombus:
            lines = [(top, right), (right, bottom), (bottom, left), (left, top)]
        }
        for lp in lines { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
        return frame
    }

    static func createDynamicTrapezoid(topWidth: Float, bottomWidth: Float, height: Float, thickness: Float, color: UIColor) -> Entity {
        let frame = Entity(), topLeft = SIMD3<Float>(-topWidth / 2, height / 2, 0), topRight = SIMD3<Float>(topWidth / 2, height / 2, 0), bottomLeft = SIMD3<Float>(-bottomWidth / 2, -height / 2, 0), bottomRight = SIMD3<Float>(bottomWidth / 2, -height / 2, 0)
        for lp in [(topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft), (bottomLeft, topLeft)] { frame.addChild(createLineEntity(from: lp.0, to: lp.1, thickness: thickness, color: color)) }
        return frame
    }
}
