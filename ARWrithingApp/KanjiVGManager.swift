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
        
        func toIosX(_ kvgX: Float) -> Float {
            let ratio = kvgX / kvgCanvasSize
            return -boxWidth / 2.0 + (boxWidth * ratio)
        }
        func toIosY(_ kvgY: Float) -> Float {
            let ratio = kvgY / kvgCanvasSize
            return boxHeight / 2.0 - (boxHeight * ratio)
        }
        
        if nyoBox.isValid && innerBox.isValid {
            return .shinnyo(splitX: toIosX(innerBox.minX - 1.0), bottomY: toIosY(innerBox.maxY + 1.0))
        }
        if kamaeBox.isValid && innerBox.isValid {
            return .kamae(leftX: toIosX(innerBox.minX - 2.0), rightX: toIosX(innerBox.maxX + 2.0),
                          topY: toIosY(innerBox.minY - 2.0), bottomY: toIosY(innerBox.maxY + 2.0))
        }
        if leftBox.isValid && rightBox.isValid {
            let midX = (leftBox.maxX + rightBox.minX) / 2.0
            return .henTsukuri(splitX: toIosX(midX))
        }
        
        return .none
    }
    
    // 🌟 新機能：漢字の一画ごとの「始点」座標を抽出する関数
    func getStrokeStarts(for char: Character, boxWidth: Float, boxHeight: Float) -> [SIMD2<Float>] {
        guard let unicodeScalar = char.unicodeScalars.first else { return [] }
        let hexString = String(format: "%05x", unicodeScalar.value)
        
        // ファイルのテキストを直接読み込む
        guard let url = Bundle.main.url(forResource: hexString, withExtension: "svg", subdirectory: "kanjivg")
                     ?? Bundle.main.url(forResource: hexString, withExtension: "svg"),
              let content = try? String(contentsOf: url) else { return [] }
        
        // 正規表現で <path d="M(x座標),(y座標)... の部分だけを高速に抽出
        let pattern = "d=\"[Mm]\\s*([0-9.-]+)[,\\s]+([0-9.-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        
        let kvgCanvasSize: Float = 109.0
        var points: [SIMD2<Float>] = []
        
        for match in matches {
            if let xRange = Range(match.range(at: 1), in: content),
               let yRange = Range(match.range(at: 2), in: content),
               let xVal = Float(content[xRange]),
               let yVal = Float(content[yRange]) {
                
                // ARの枠サイズに合わせて等倍マッピング
                let iosX = -boxWidth / 2.0 + (boxWidth * (xVal / kvgCanvasSize))
                let iosY = boxHeight / 2.0 - (boxHeight * (yVal / kvgCanvasSize))
                points.append(SIMD2<Float>(iosX, iosY))
            }
        }
        return points
    }
    
    // ==========================================
    // 📦 XMLパーサー処理
    // ==========================================
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "g" {
            let pos = attributeDict["kvg:position"] ?? ""
            positionStack.append(pos)
            if let validPos = positionStack.last(where: { majorPositions.contains($0) }) {
                currentPosition = validPos
            } else {
                currentPosition = ""
            }
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
        let pattern = "[a-zA-Z]|[-+]?[0-9]*\\.?[0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: d, range: NSRange(d.startIndex..., in: d))
        let tokens = matches.map { String(d[Range($0.range, in: d)!]) }
        
        var startX: Float = 0, startY: Float = 0
        var currentX: Float = 0, currentY: Float = 0
        var command = ""; var args: [Float] = []
        
        func updateBox(x: Float, y: Float) {
            if position == "left" { leftBox.update(x: x, y: y) }
            else if position == "right" { rightBox.update(x: x, y: y) }
            else if position == "nyo" { nyoBox.update(x: x, y: y) }
            else if position == "kamae" { kamaeBox.update(x: x, y: y) }
            else { innerBox.update(x: x, y: y) }
        }
        
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
                        updateBox(x: currentX, y: currentY)
                        startX = currentX; startY = currentY
                        if cmd == "m" { command = isRel ? "l" : "L" }
                    } else if cmd == "h" {
                        currentX = isRel ? startX + args[0] : args[0]
                        updateBox(x: currentX, y: startY); startX = currentX
                    } else if cmd == "v" {
                        currentY = isRel ? startY + args[0] : args[0]
                        updateBox(x: startX, y: currentY); startY = currentY
                    } else if cmd == "c" {
                        currentX = isRel ? startX + args[4] : args[4]
                        currentY = isRel ? startY + args[5] : args[5]
                        updateBox(x: currentX, y: currentY)
                        startX = currentX; startY = currentY
                    } else if cmd == "s" || cmd == "q" {
                        currentX = isRel ? startX + args[2] : args[2]
                        currentY = isRel ? startY + args[3] : args[3]
                        updateBox(x: currentX, y: currentY)
                        startX = currentX; startY = currentY
                    }
                    args.removeFirst(req)
                }
            }
        }
    }
}
