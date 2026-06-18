import Foundation

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
              let content = try? String(contentsOf: url) else { return [] }
        
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
    
    // 🌟 新機能：「交点」を数学的に計算して抽出する最強のアルゴリズム
    func getIntersections(for char: Character, boxWidth: Float, boxHeight: Float) -> [SIMD2<Float>] {
        guard let unicodeScalar = char.unicodeScalars.first else { return [] }
        let hexString = String(format: "%05x", unicodeScalar.value)
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "kanjivg")
                     ?? Bundle.main.url(forResource: hexString, withExtension: "svg"),
              let content = try? String(contentsOf: url) else { return [] }

        // ファイルから全ての <path d="..."> を抽出
        let pathPattern = "<path[^>]*d=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pathPattern) else { return [] }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        var allStrokes: [[SIMD2<Float>]] = []
        let kvgCanvasSize: Float = 109.0

        for match in matches {
            if let dRange = Range(match.range(at: 1), in: content) {
                let d = String(content[dRange])
                let strokePoints = parsePolyline(from: d)
                if strokePoints.count > 1 { allStrokes.append(strokePoints) }
            }
        }

        var intersections: [SIMD2<Float>] = []

        // 画と画の総当たり交差判定（O(N^2)の線分交差チェック）
        if allStrokes.count >= 2 {
            for i in 0..<allStrokes.count {
                for j in (i+1)..<allStrokes.count {
                    let strokeA = allStrokes[i]
                    let strokeB = allStrokes[j]

                    for a in 0..<(strokeA.count - 1) {
                        for b in 0..<(strokeB.count - 1) {
                            if let intersect = segmentsIntersect(p1: strokeA[a], p2: strokeA[a+1], p3: strokeB[b], p4: strokeB[b+1]) {
                                // AR用の座標系に等倍マッピング
                                let iosX = -boxWidth / 2.0 + (boxWidth * (intersect.x / kvgCanvasSize))
                                let iosY = boxHeight / 2.0 - (boxHeight * (intersect.y / kvgCanvasSize))
                                let pt = SIMD2<Float>(iosX, iosY)

                                // 重複（近すぎる点）の排除
                                if !intersections.contains(where: { distance($0, pt) < 0.001 }) {
                                    intersections.append(pt)
                                }
                            }
                        }
                    }
                }
            }
        }
        return intersections
    }
    
    // ==========================================
    // 📦 XMLパーサー処理（へんとつくり用）
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
        let pts = parsePolyline(from: d)
        for p in pts {
            if position == "left" { leftBox.update(x: p.x, y: p.y) }
            else if position == "right" { rightBox.update(x: p.x, y: p.y) }
            else if position == "nyo" { nyoBox.update(x: p.x, y: p.y) }
            else if position == "kamae" { kamaeBox.update(x: p.x, y: p.y) }
            else { innerBox.update(x: p.x, y: p.y) }
        }
    }
    
    // ==========================================
    // 📐 交点計算のための幾何学ヘルパー
    // ==========================================
    
    // SVGパスを細かい直線の集まり（ポリライン）に変換する関数
    private func parsePolyline(from d: String) -> [SIMD2<Float>] {
        let pattern = "[a-zA-Z]|[-+]?[0-9]*\\.?[0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: d, range: NSRange(d.startIndex..., in: d))
        let tokens = matches.map { String(d[Range($0.range, in: d)!]) }

        var pts: [SIMD2<Float>] = []
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
                        startX = currentX; startY = currentY
                        if cmd == "m" { command = isRel ? "l" : "L" }
                    } else if cmd == "h" {
                        currentX = isRel ? startX + args[0] : args[0]
                        pts.append(SIMD2<Float>(currentX, startY)); startX = currentX
                    } else if cmd == "v" {
                        currentY = isRel ? startY + args[0] : args[0]
                        pts.append(SIMD2<Float>(startX, currentY)); startY = currentY
                    } else if cmd == "c" {
                        // ベジェ曲線を5分割してサンプリング
                        let c1 = SIMD2<Float>(isRel ? startX + args[0] : args[0], isRel ? startY + args[1] : args[1])
                        let c2 = SIMD2<Float>(isRel ? startX + args[2] : args[2], isRel ? startY + args[3] : args[3])
                        let end = SIMD2<Float>(isRel ? startX + args[4] : args[4], isRel ? startY + args[5] : args[5])
                        for i in 1...5 {
                            let t = Float(i) / 5.0; let mt = 1.0 - t
                            let x = (mt*mt*mt)*startX + 3.0*(mt*mt)*t*c1.x + 3.0*mt*(t*t)*c2.x + (t*t*t)*end.x
                            let y = (mt*mt*mt)*startY + 3.0*(mt*mt)*t*c1.y + 3.0*mt*(t*t)*c2.y + (t*t*t)*end.y
                            pts.append(SIMD2<Float>(x, y))
                        }
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
                        startX = end.x; startY = end.y
                    }
                    args.removeFirst(req)
                }
            }
        }
        return pts
    }
    
    // 2本の線分が交差しているかを判定する数学関数
    private func segmentsIntersect(p1: SIMD2<Float>, p2: SIMD2<Float>, p3: SIMD2<Float>, p4: SIMD2<Float>) -> SIMD2<Float>? {
        let d = (p2.x - p1.x) * (p4.y - p3.y) - (p2.y - p1.y) * (p4.x - p3.x)
        if abs(d) < 0.0001 { return nil } // 平行な場合は無視
        let u = ((p3.x - p1.x) * (p4.y - p3.y) - (p3.y - p1.y) * (p4.x - p3.x)) / d
        let v = ((p3.x - p1.x) * (p2.y - p1.y) - (p3.y - p1.y) * (p2.x - p1.x)) / d
        if u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0 {
            return SIMD2<Float>(p1.x + u * (p2.x - p1.x), p1.y + u * (p2.y - p1.y))
        }
        return nil
    }
    
    private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        return sqrt((a.x - b.x)*(a.x - b.x) + (a.y - b.y)*(a.y - b.y))
    }
}
