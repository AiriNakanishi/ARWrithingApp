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
    
    func getGuide(for char: Character, boxWidth: Float, boxHeight: Float) -> GuideType {
        guard let unicodeScalar = char.unicodeScalars.first else { return .none }
        let hexString = String(format: "%05x", unicodeScalar.value)
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "kanjivg")
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
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "kanjivg")
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
    
    // 🌟 完全修復版：「クロス交差」「T字接点」「L字角」のみを抽出する最強アルゴリズム
    func getIntersections(for char: Character, boxWidth: Float, boxHeight: Float) -> [SIMD2<Float>] {
        guard let unicodeScalar = char.unicodeScalars.first else { return [] }
        let hexString = String(format: "%05x", unicodeScalar.value)
        
        // 🚨 前回消してしまっていた「?? Bundle.main...」を復活！（これでファイルが確実に読まれます）
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "kanjivg")
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
                let parsed = parsePolylineAndAnchors(from: d)
                if parsed.polyline.count > 1 {
                    allStrokes.append(parsed.polyline)
                    allAnchors.append(parsed.anchors)
                }
            }
        }

        var rawPoints: [SIMD2<Float>] = []
        let touchTolerance: Float = 3.5 // 接触を判定する許容距離

        // ① クロス交差点の抽出（×の交わり）
        if allStrokes.count >= 2 {
            for i in 0..<allStrokes.count {
                for j in (i+1)..<allStrokes.count {
                    let strokeA = allStrokes[i]
                    let strokeB = allStrokes[j]
                    for a in 0..<(strokeA.count - 1) {
                        for b in 0..<(strokeB.count - 1) {
                            if let intersect = segmentsIntersect(p1: strokeA[a], p2: strokeA[a+1], p3: strokeB[b], p4: strokeB[b+1]) {
                                rawPoints.append(intersect)
                            }
                        }
                    }
                }
            }
        }

        // ② T字・結合部の抽出（線の端点が別の線に接触している場合のみ追加）
        for i in 0..<allStrokes.count {
            let stroke = allStrokes[i]
            if let first = stroke.first, touchesAnotherStroke(p: first, myIndex: i, strokes: allStrokes, tolerance: touchTolerance) {
                rawPoints.append(first)
            }
            if let last = stroke.last, touchesAnotherStroke(p: last, myIndex: i, strokes: allStrokes, tolerance: touchTolerance) {
                rawPoints.append(last)
            }
        }

        // ③ L字の角（コーナー）の抽出
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
                        // 約60度以上の鋭角な折れ曲がりのみ角として扱う
                        if cosTheta < 0.5 {
                            rawPoints.append(p1)
                        }
                    }
                }
            }
        }

        // ④ AR座標への変換と、強力な二重打ち防止（1.5ミリ以内の近い点を統合）
        var finalPoints: [SIMD2<Float>] = []
        for pt in rawPoints {
            let iosX = -boxWidth / 2.0 + (boxWidth * (pt.x / kvgCanvasSize))
            let iosY = boxHeight / 2.0 - (boxHeight * (pt.y / kvgCanvasSize))
            let iosPt = SIMD2<Float>(iosX, iosY)

            if !finalPoints.contains(where: { distance($0, iosPt) < 0.0015 }) {
                finalPoints.append(iosPt)
            }
        }
        
        return finalPoints
    }
    
    // 指定した点が別の線に接触しているか判定する関数
    private func touchesAnotherStroke(p: SIMD2<Float>, myIndex: Int, strokes: [[SIMD2<Float>]], tolerance: Float) -> Bool {
        for j in 0..<strokes.count {
            if j == myIndex { continue }
            let otherStroke = strokes[j]
            for b in 0..<(otherStroke.count - 1) {
                if pointToSegmentDistance(p: p, v: otherStroke[b], w: otherStroke[b+1]) < tolerance {
                    return true
                }
            }
        }
        return false
    }
    
    // ==========================================
    // 📦 XMLパーサー処理
    // ==========================================
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "g" {
            let pos = attributeDict["kvg:position"] ?? ""
            positionStack.append(pos)
            if let validPos = positionStack.last(where: { majorPositions.contains($0) }) { currentPosition = validPos } else { currentPosition = "" }
        } else if elementName == "path" {
            if let d = attributeDict["d"] { extractCoordinates(from: d, position: currentPosition) }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "g" && !positionStack.isEmpty {
            positionStack.removeLast()
            currentPosition = positionStack.last(where: { majorPositions.contains($0) }) ?? ""
        }
    }
    
    private func extractCoordinates(from d: String, position: String) {
        let parsed = parsePolylineAndAnchors(from: d)
        for p in parsed.polyline {
            if position == "left" { leftBox.update(x: p.x, y: p.y) }
            else if position == "right" { rightBox.update(x: p.x, y: p.y) }
            else if position == "nyo" { nyoBox.update(x: p.x, y: p.y) }
            else if position == "kamae" { kamaeBox.update(x: p.x, y: p.y) }
            else { innerBox.update(x: p.x, y: p.y) }
        }
    }
    
    // ==========================================
    // 📐 線分・交点計算アルゴリズム
    // ==========================================
    private func parsePolylineAndAnchors(from d: String) -> (polyline: [SIMD2<Float>], anchors: [SIMD2<Float>]) {
        let pattern = "[a-zA-Z]|[-+]?[0-9]*\\.?[0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return ([], []) }
        let matches = regex.matches(in: d, range: NSRange(d.startIndex..., in: d))
        let tokens = matches.map { String(d[Range($0.range, in: d)!]) }

        var pts: [SIMD2<Float>] = []
        var anchors: [SIMD2<Float>] = []
        var startX: Float = 0, startY: Float = 0
        var currentX: Float = 0, currentY: Float = 0
        var command = ""; var args: [Float] = []

        for token in tokens {
            if let firstChar = token.first, firstChar.isLetter {
                command = String(firstChar); args.removeAll()
            } else if let val = Float(token) {
                args.append(val)
                if command.isEmpty { continue }

                let cmd = command.lowercased()
                var req = 2
                if cmd == "c" { req = 6 } else if cmd == "s" || cmd == "q" { req = 4 } else if cmd == "h" || cmd == "v" { req = 1 } else if cmd == "z" { req = 0 }

                while args.count >= req && req > 0 {
                    let isRel = command.first!.isLowercase
                    if cmd == "m" || cmd == "l" {
                        currentX = isRel ? startX + args[0] : args[0]
                        currentY = isRel ? startY + args[1] : args[1]
                        pts.append(SIMD2<Float>(currentX, currentY))
                        anchors.append(SIMD2<Float>(currentX, currentY))
                        startX = currentX; startY = currentY
                        if cmd == "m" { command = isRel ? "l" : "L" }
                    } else if cmd == "h" {
                        currentX = isRel ? startX + args[0] : args[0]
                        pts.append(SIMD2<Float>(currentX, startY))
                        anchors.append(SIMD2<Float>(currentX, startY))
                        startX = currentX
                    } else if cmd == "v" {
                        currentY = isRel ? startY + args[0] : args[0]
                        pts.append(SIMD2<Float>(startX, currentY))
                        anchors.append(SIMD2<Float>(startX, currentY))
                        startY = currentY
                    } else if cmd == "c" {
                        let c1 = SIMD2<Float>(isRel ? startX + args[0] : args[0], isRel ? startY + args[1] : args[1])
                        let c2 = SIMD2<Float>(isRel ? startX + args[2] : args[2], isRel ? startY + args[3] : args[3])
                        let end = SIMD2<Float>(isRel ? startX + args[4] : args[4], isRel ? startY + args[5] : args[5])
                        for i in 1...5 {
                            let t = Float(i) / 5.0; let mt = 1.0 - t
                            let x = (mt*mt*mt)*startX + 3.0*(mt*mt)*t*c1.x + 3.0*mt*(t*t)*c2.x + (t*t*t)*end.x
                            let y = (mt*mt*mt)*startY + 3.0*(mt*mt)*t*c1.y + 3.0*mt*(t*t)*c2.y + (t*t*t)*end.y
                            pts.append(SIMD2<Float>(x, y))
                        }
                        anchors.append(SIMD2<Float>(end.x, end.y))
                        startX = end.x; startY = end.y
                    } else if cmd == "s" || cmd == "q" {
                        let c1 = SIMD2<Float>(isRel ? startX + args[0] : args[0], isRel ? startY + args[1] : args[1])
                        let end = SIMD2<Float>(isRel ? startX + args[2] : args[2], isRel ? startY + args[3] : args[3])
                        for i in 1...5 {
                            let t = Float(i) / 5.0; let mt = 1.0 - t
                            let x = mt*mt*startX + 2.0*mt*t*c1.x + t*t*end.x
                            let y = mt*mt*startY + 2.0*mt*t*c1.y + t*t*end.y
                            pts.append(SIMD2<Float>(x, y))
                        }
                        anchors.append(SIMD2<Float>(end.x, end.y))
                        startX = end.x; startY = end.y
                    }
                    args.removeFirst(req)
                }
            }
        }
        return (pts, anchors)
    }
    
    private func segmentsIntersect(p1: SIMD2<Float>, p2: SIMD2<Float>, p3: SIMD2<Float>, p4: SIMD2<Float>) -> SIMD2<Float>? {
        let d = (p2.x - p1.x) * (p4.y - p3.y) - (p2.y - p1.y) * (p4.x - p3.x)
        if abs(d) < 0.0001 { return nil }
        let u = ((p3.x - p1.x) * (p4.y - p3.y) - (p3.y - p1.y) * (p4.x - p3.x)) / d
        let v = ((p3.x - p1.x) * (p2.y - p1.y) - (p3.y - p1.y) * (p2.x - p1.x)) / d
        
        if u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0 {
            return SIMD2<Float>(p1.x + u * (p2.x - p1.x), p1.y + u * (p2.y - p1.y))
        }
        return nil
    }

    private func distanceSquared(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        return (a.x - b.x)*(a.x - b.x) + (a.y - b.y)*(a.y - b.y)
    }

    private func pointToSegmentDistance(p: SIMD2<Float>, v: SIMD2<Float>, w: SIMD2<Float>) -> Float {
        let l2 = distanceSquared(v, w)
        if l2 == 0 { return distance(p, v) }
        var t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2
        t = max(0, min(1, t))
        let projection = SIMD2<Float>(v.x + t * (w.x - v.x), v.y + t * (w.y - v.y))
        return distance(p, projection)
    }
    
    private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        return sqrt((a.x - b.x)*(a.x - b.x) + (a.y - b.y)*(a.y - b.y))
    }
}
