import Foundation
import simd

struct KanjiVGParser {
    static func parsePolyline(from d: String) -> [SIMD2<Float>] {
        return parsePolylineAndAnchors(from: d).polyline
    }
    
    static func parsePolylineAndAnchors(from d: String) -> (polyline: [SIMD2<Float>], anchors: [SIMD2<Float>]) {
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
}
