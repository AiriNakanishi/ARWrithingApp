import Foundation
import simd

enum GuideType {
    case henTsukuri(splitX: Float)
    case center(centerX: Float)
    case shinnyo(splitX: Float, bottomY: Float)
    case kamae(leftX: Float, rightX: Float, topY: Float, bottomY: Float)
    case none
}

class KanjiVGManager: NSObject, XMLParserDelegate {
    static let shared = KanjiVGManager()
    
    private var leftBox = BoundingBox()
    private var rightBox = BoundingBox()
    private var nyoBox = BoundingBox()
    private var kamaeBox = BoundingBox()
    private var innerBox = BoundingBox()
    
    private var currentPosition: String = ""
    private var positionStack: [String] = []
    private let majorPositions = ["left", "right", "nyo", "kamae", "tare", "nyoc", "kamaec"]
    
    struct BoundingBox {
        var minX: Float = 109, maxX: Float = 0
        var minY: Float = 109, maxY: Float = 0
        var isValid: Bool { return minX <= maxX && minY <= maxY }
        mutating func update(x: Float, y: Float) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        mutating func reset() { minX = 109; maxX = 0; minY = 109; maxY = 0 }
    }
    
    // ==========================================
    // 💡 ガイドデータ取得メソッド群
    // ==========================================
    
    func getGuide(for char: Character, boxWidth: Float, boxHeight: Float) -> GuideType {
        guard let unicodeScalar = char.unicodeScalars.first else { return .none }
        let hexString = String(format: "%05x", unicodeScalar.value)
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "KanjiVGData")
                     ?? Bundle.main.url(forResource: hexString, withExtension: "svg") else { return .none }
        
        leftBox.reset(); rightBox.reset(); nyoBox.reset(); kamaeBox.reset(); innerBox.reset()
        currentPosition = ""; positionStack = []
        
        guard let parser = XMLParser(contentsOf: url) else { return .none }
        parser.delegate = self
        parser.parse()
        
        if char == "函" {
            if nyoBox.isValid { kamaeBox = nyoBox; nyoBox.reset() }
            if leftBox.isValid { kamaeBox = leftBox; leftBox.reset() }
        }
        
        let kvgCanvasSize: Float = 109.0
        func toIosX(_ kvgX: Float) -> Float { return -boxWidth / 2.0 + (boxWidth * (kvgX / kvgCanvasSize)) }
        func toIosY(_ kvgY: Float) -> Float { return boxHeight / 2.0 - (boxHeight * (kvgY / kvgCanvasSize)) }
        
        if nyoBox.isValid && innerBox.isValid { return .shinnyo(splitX: toIosX(innerBox.minX - 1.0), bottomY: toIosY(innerBox.maxY + 1.0)) }
        if kamaeBox.isValid && innerBox.isValid { return .kamae(leftX: toIosX(innerBox.minX - 2.0), rightX: toIosX(innerBox.maxX + 2.0), topY: toIosY(innerBox.minY - 2.0), bottomY: toIosY(innerBox.maxY + 2.0)) }
        if leftBox.isValid && rightBox.isValid { return .henTsukuri(splitX: toIosX((leftBox.maxX + rightBox.minX) / 2.0)) }
        
        return .none
    }
    
    func getStrokeStarts(for char: Character, boxWidth: Float, boxHeight: Float) -> [SIMD2<Float>] {
        guard let unicodeScalar = char.unicodeScalars.first else { return [] }
        let hexString = String(format: "%05x", unicodeScalar.value)
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "KanjiVGData")
                     ?? Bundle.main.url(forResource: hexString, withExtension: "svg"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        
        let pattern = "d=\"[Mm]\\s*([0-9.-]+)[,\\s]+([0-9.-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        
        let kvgCanvasSize: Float = 109.0
        var points: [SIMD2<Float>] = []
        for match in matches {
            if let xRange = Range(match.range(at: 1), in: content), let yRange = Range(match.range(at: 2), in: content),
               let xVal = Float(content[xRange]), let yVal = Float(content[yRange]) {
                let iosX = -boxWidth / 2.0 + (boxWidth * (xVal / kvgCanvasSize))
                let iosY = boxHeight / 2.0 - (boxHeight * (yVal / kvgCanvasSize))
                points.append(SIMD2<Float>(iosX, iosY))
            }
        }
        return points
    }
    
    func getIntersections(for char: Character, boxWidth: Float, boxHeight: Float) -> [SIMD2<Float>] {
        guard let unicodeScalar = char.unicodeScalars.first else { return [] }
        let hexString = String(format: "%05x", unicodeScalar.value)
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "KanjiVGData")
                     ?? Bundle.main.url(forResource: hexString, withExtension: "svg"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let pathPattern = "<path[^>]*d=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pathPattern) else { return [] }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        var allStrokes: [[SIMD2<Float>]] = []
        var allAnchors: [[SIMD2<Float>]] = []
        let kvgCanvasSize: Float = 109.0

        for match in matches {
            if let dRange = Range(match.range(at: 1), in: content) {
                let d = String(content[dRange])
                let parsed = KanjiVGParser.parsePolylineAndAnchors(from: d)
                if parsed.polyline.count > 0 {
                    allStrokes.append(parsed.polyline)
                    allAnchors.append(parsed.anchors)
                }
            }
        }

        var rawPoints: [SIMD2<Float>] = []
        let touchTolerance: Float = 3.5

        if allStrokes.count >= 2 {
            for i in 0..<allStrokes.count {
                for j in (i+1)..<allStrokes.count {
                    let strokeA = allStrokes[i]
                    let strokeB = allStrokes[j]
                    for a in 0..<(strokeA.count - 1) {
                        for b in 0..<(strokeB.count - 1) {
                            if let intersect = GeometryMath.segmentsIntersect(p1: strokeA[a], p2: strokeA[a+1], p3: strokeB[b], p4: strokeB[b+1]) {
                                rawPoints.append(intersect)
                            }
                        }
                    }
                }
            }
        }

        for i in 0..<allStrokes.count {
            let stroke = allStrokes[i]
            if let first = stroke.first, touchesAnotherStroke(p: first, myIndex: i, strokes: allStrokes, tolerance: touchTolerance) { rawPoints.append(first) }
            if let last = stroke.last, touchesAnotherStroke(p: last, myIndex: i, strokes: allStrokes, tolerance: touchTolerance) { rawPoints.append(last) }
        }

        for anchors in allAnchors {
            if anchors.count >= 3 {
                for k in 1..<(anchors.count - 1) {
                    let p0 = anchors[k-1]
                    let p1 = anchors[k]
                    let p2 = anchors[k+1]
                    let v1 = SIMD2<Float>(p1.x - p0.x, p1.y - p0.y)
                    let v2 = SIMD2<Float>(p2.x - p1.x, p2.y - p1.y)
                    let len1 = sqrt(v1.x*v1.x + v1.y*v1.y)
                    let len2 = sqrt(v2.x*v2.x + v2.y*v2.y)
                    if len1 > 2.0 && len2 > 2.0 {
                        let cosTheta = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)
                        if cosTheta < 0.5 { rawPoints.append(p1) }
                    }
                }
            }
        }

        var finalPoints: [SIMD2<Float>] = []
        for pt in rawPoints {
            let iosX = -boxWidth / 2.0 + (boxWidth * (pt.x / kvgCanvasSize))
            let iosY = boxHeight / 2.0 - (boxHeight * (pt.y / kvgCanvasSize))
            let iosPt = SIMD2<Float>(iosX, iosY)
            if !finalPoints.contains(where: { GeometryMath.distance($0, iosPt) < 0.0015 }) {
                finalPoints.append(iosPt)
            }
        }
        return finalPoints
    }
    
    private func touchesAnotherStroke(p: SIMD2<Float>, myIndex: Int, strokes: [[SIMD2<Float>]], tolerance: Float) -> Bool {
        for j in 0..<strokes.count {
            if j == myIndex { continue }
            let otherStroke = strokes[j]
            for b in 0..<(otherStroke.count - 1) {
                if GeometryMath.pointToSegmentDistance(p: p, v: otherStroke[b], w: otherStroke[b+1]) < tolerance {
                    return true
                }
            }
        }
        return false
    }
    
    // ==========================================
    // 📦 XMLパーサー委譲処理
    // ==========================================
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "g" {
            let pos = attributeDict["kvg:position"] ?? ""
            positionStack.append(pos)
            if let validPos = positionStack.last(where: { majorPositions.contains($0) }) { currentPosition = validPos } else { currentPosition = "" }
        } else if elementName == "path" {
            if let d = attributeDict["d"] {
                let pts = KanjiVGParser.parsePolyline(from: d)
                for p in pts {
                    if currentPosition == "left" { leftBox.update(x: p.x, y: p.y) }
                    else if currentPosition == "right" { rightBox.update(x: p.x, y: p.y) }
                    else if currentPosition == "nyo" { nyoBox.update(x: p.x, y: p.y) }
                    else if currentPosition == "kamae" { kamaeBox.update(x: p.x, y: p.y) }
                    else { innerBox.update(x: p.x, y: p.y) }
                }
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "g" && !positionStack.isEmpty {
            positionStack.removeLast()
            currentPosition = positionStack.last(where: { majorPositions.contains($0) }) ?? ""
        }
    }
}
