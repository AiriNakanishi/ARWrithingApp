import RealityKit
import UIKit
import CoreText

class ARGuideRenderer {
    static let referenceSize: Float = 0.0105
    
    private static var textMeshCache: [Character: MeshResource] = [:]
    private static var entityCache: [String: Entity] = [:]
    private static var isGenerating: Set<String> = []
    
    static func clearCache() {
        textMeshCache.removeAll()
        entityCache.removeAll()
        isGenerating.removeAll()
    }
    
    // 💡 あいりさん考案の美文字アルゴリズム（ノイズ除去・極端アスペクト比対応版）
        static func getGaikeiShape(char: Character, uiFont: UIFont) -> GuideShape {
            let metrics = ARShapeBuilder.getShapeClassificationMetrics(char: char, uiFont: uiFont)
            
            // ゼロ除算防止
            let w = metrics.width > 0 ? metrics.width : 1.0
            let h = metrics.height > 0 ? metrics.height : 1.0
            let topW = metrics.topWidth
            let botW = metrics.bottomWidth
            let cornerRatio = metrics.cornerRatio
            
            let aspectRatio = w / h
            
            // 1. 【ひし形判定】四隅のインク密度が極端に低い
            if cornerRatio < 0.12 {
                return .rhombus
            }
            
            // 2. 【極端な長方形判定】アスペクト比で即決（「一」などが三角形に吸い込まれるのを防ぐ）
            if aspectRatio > 2.0 {
                return .wide_rect  // 横幅が高さの2倍以上なら文句なしで横長
            } else if aspectRatio < 0.5 {
                return .tall_rect  // 高さが横幅の2倍以上なら文句なしで縦長
            }
            
            // 3. 【ノイズ・細すぎ除外フィルター】
            // 条件A: 上の幅と下の幅に、文字全体の10%以上の明確な差があるか？（微小な誤差のノイズキャンセリング）
            let hasSignificantDifference = abs(topW - botW) > (w * 0.1)
            // 条件B: 上の幅か下の幅のどちらかが、文字全体の20%以上の太さを持っているか？（「中」の縦棒など細すぎ判定の除外）
            let isNotJustLines = topW > (w * 0.2) || botW > (w * 0.2)
            
            // 誤差がなく、かつ単なる線ではない場合のみ、すぼまり具合（三角・台形）を判定する
            if hasSignificantDifference && isNotJustLines {
                
                // 4. 【三角・台形判定】
                if botW > topW * 1.5 {
                    if topW < w * 0.45 {
                        return .triangle     // 下が広く、上が尖っていれば三角
                    } else {
                        return .trapezoid    // 下が広く、上もそこそこ広ければ台形
                    }
                } else if topW > botW * 1.5 {
                    return .inv_triangle     // 上が広ければ逆三角
                }
            }
            
            // 5. 【緩い長方形判定】極端ではないが、少し縦長・横長なもの
            if aspectRatio > 1.1 {
                return .wide_rect
            } else if aspectRatio < 0.9 {
                return .tall_rect
            }
            
            // 6. 【正方形】これまでの条件をすべてすり抜けた、バランスの良い四角い文字
            return .square
        }
    
    // ===================================================
    // 🌟 1. 起動用
    // ===================================================
    static func createBaseEntity(text: String) -> Entity {
        let textContainer = Entity()
        
        let otehonSide = Entity(); otehonSide.name = "OtehonSide"
        let renshuSide = Entity(); renshuSide.name = "RenshuSide"
        textContainer.addChild(otehonSide)
        textContainer.addChild(renshuSide)
        
        let fixedBoxSize: Float = referenceSize
        let fixedLineSpacing: Float = referenceSize
        let lineThickness: Float = referenceSize * 0.047
        let dashLen: Float = referenceSize * 0.076
        let baseAlpha: CGFloat = 0.15
        
        let fontSize = CGFloat(referenceSize * 0.95)
        let uiFont = UIFont(name: "HiraMinProN-W3", size: fontSize) ?? UIFont(name: "HiraMinProN-W6", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .regular)
        var textMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.8)); textMaterial.blending = .transparent(opacity: 1.0)
        var baseGuideMat = UnlitMaterial(color: UIColor.gray.withAlphaComponent(baseAlpha)); baseGuideMat.blending = .transparent(opacity: 1.0)
        
        var currentY: Float = 0.0
        var baseBuilder = MeshBuilder()
        
        for char in text {
            let charMesh: MeshResource
            if let cached = textMeshCache[char] { charMesh = cached } else {
                charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
                textMeshCache[char] = charMesh
            }
            let charBounds = charEntityVisualBounds(mesh: charMesh)
            let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
            charEntity.position = [-charBounds.x, currentY - charBounds.y, 0.001]
            otehonSide.addChild(charEntity)
            
            baseBuilder.addLine(from: [-fixedBoxSize/2, currentY + fixedBoxSize/2], to: [fixedBoxSize/2, currentY + fixedBoxSize/2], thickness: lineThickness)
            baseBuilder.addLine(from: [-fixedBoxSize/2, currentY - fixedBoxSize/2], to: [fixedBoxSize/2, currentY - fixedBoxSize/2], thickness: lineThickness)
            baseBuilder.addLine(from: [-fixedBoxSize/2, currentY - fixedBoxSize/2], to: [-fixedBoxSize/2, currentY + fixedBoxSize/2], thickness: lineThickness)
            baseBuilder.addLine(from: [fixedBoxSize/2, currentY - fixedBoxSize/2], to: [fixedBoxSize/2, currentY + fixedBoxSize/2], thickness: lineThickness)
            
            baseBuilder.addDashedLine(from: [0, currentY + fixedBoxSize/2], to: [0, currentY - fixedBoxSize/2], thickness: lineThickness * 0.8, dashLength: dashLen, gapLength: dashLen)
            baseBuilder.addDashedLine(from: [-fixedBoxSize/2, currentY], to: [fixedBoxSize/2, currentY], thickness: lineThickness * 0.8, dashLength: dashLen, gapLength: dashLen)
            
            currentY -= fixedLineSpacing
        }
        
        if let baseMergedMesh = baseBuilder.generate() {
            let otehonBase = ModelEntity(mesh: baseMergedMesh, materials: [baseGuideMat])
            otehonSide.addChild(otehonBase)
            
            let renshuBase = ModelEntity(mesh: baseMergedMesh, materials: [baseGuideMat])
            renshuSide.addChild(renshuBase)
        }
        
        let totalBounds = textContainer.visualBounds(relativeTo: nil)
        textContainer.position = -totalBounds.center
        let flatWrapper = Entity()
        flatWrapper.addChild(textContainer)
        flatWrapper.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        flatWrapper.name = "GuideWrapper"
        return flatWrapper
    }
    
    // ===================================================
    // 🌟 2. オンデマンド生成
    // ===================================================
    static func updateScene(root: Entity, modes: Set<GuideMode>, size: Float, isLeftHanded: Bool, text: String) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let wrapper = root.findEntity(named: "GuideWrapper"),
              let otehonSide = wrapper.findEntity(named: "OtehonSide"),
              let renshuSide = wrapper.findEntity(named: "RenshuSide") else { return }
        
        wrapper.scale = SIMD3<Float>(repeating: size / referenceSize)
        
        let baseOffset = referenceSize * 1.4
        otehonSide.position.x = isLeftHanded ? baseOffset : -baseOffset
        renshuSide.position.x = isLeftHanded ? -baseOffset : baseOffset
        
        let activeNames = Set(modes.map { String(describing: $0) })
        let toggleableNames = ["nazoru", "gaikei", "daikei", "henTsukuri", "shiten", "koten"]
        let allSides = [otehonSide, renshuSide]
        
        for modeName in toggleableNames {
            let isActive = activeNames.contains(modeName)
            let targetSides = (modeName == "nazoru") ? [renshuSide] : allSides
            
            for side in allSides {
                let sideName = side.name
                let cacheKey = "\(sideName)_\(modeName)"
                let shouldBeVisible = isActive && targetSides.contains(side)
                
                if shouldBeVisible {
                    if side.findEntity(named: modeName) == nil {
                        if let cachedGroup = entityCache[cacheKey] {
                            side.addChild(cachedGroup)
                        } else {
                            if !isGenerating.contains(cacheKey) {
                                isGenerating.insert(cacheKey)
                                DispatchQueue.main.async {
                                    let newGroup = generateModeGroup(modeName: modeName, text: text)
                                    self.entityCache[cacheKey] = newGroup
                                    self.isGenerating.remove(cacheKey)
                                    if side.findEntity(named: modeName) == nil {
                                        side.addChild(newGroup)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    if let existingGroup = side.findEntity(named: modeName) {
                        existingGroup.removeFromParent()
                    }
                }
            }
        }
        
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        // 💡 分離した ARPerformanceMonitor から呼び出すように修正
        ARPerformanceMonitor.reportPerformance(root: root, duration: duration)
    }
    
    // ===================================================
    // 🌟 3. 専用ジェネレーター
    // ===================================================
    private static func generateModeGroup(modeName: String, text: String) -> Entity {
        let group = Entity()
        group.name = modeName
        
        let fixedBoxSize = referenceSize
        let fixedLineSpacing = referenceSize
        let lineThickness = referenceSize * 0.047
        let dotRadius = referenceSize * 0.076
        let baseAlpha: CGFloat = 0.15
        
        let fontSize = CGFloat(referenceSize * 0.95)
        let uiFont = UIFont(name: "HiraMinProN-W3", size: fontSize) ?? .systemFont(ofSize: fontSize)
        
        let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, 100, nil)
    
        
        var traceMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.2)); traceMaterial.blending = .transparent(opacity: 1.0)
        var shitenMat = UnlitMaterial(color: UIColor.red.withAlphaComponent(baseAlpha)); shitenMat.blending = .transparent(opacity: 1.0)
        var kotenMat = UnlitMaterial(color: UIColor.magenta.withAlphaComponent(baseAlpha)); kotenMat.blending = .transparent(opacity: 1.0)
        var guideMat = UnlitMaterial(color: UIColor.blue.withAlphaComponent(baseAlpha)); guideMat.blending = .transparent(opacity: 1.0)
        
        var currentY: Float = 0.0
        
        for char in text {
            if modeName == "nazoru" {
                let charMesh: MeshResource
                if let cached = textMeshCache[char] { charMesh = cached } else {
                    charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
                    textMeshCache[char] = charMesh
                }
                let bounds = charEntityVisualBounds(mesh: charMesh)
                let traceEntity = ModelEntity(mesh: charMesh, materials: [traceMaterial])
                traceEntity.position = [-bounds.x, currentY - bounds.y, 0.001]
                group.addChild(traceEntity)
                
            } else {
                var builder = MeshBuilder()
                let t = lineThickness * 1.5
                let w = fixedBoxSize
                let h = fixedBoxSize
                
                switch modeName {
                case "gaikei":
                                    let shape = getGaikeiShape(char: char, uiFont: uiFont)
                                    
                                    let metrics = ARShapeBuilder.getShapeClassificationMetrics(char: char, uiFont: uiFont)
                                    let aspect = (metrics.height > 0 && metrics.width > 0) ? (metrics.width / metrics.height) : 1.0
                                    
                                    // 文字のアスペクト比に合わせたオーダーメイドの枠サイズ（長方形・その他の図形用）
                                    var rw = w
                                    var rh = h
                                    if aspect > 1.0 {
                                        rh = w / aspect
                                    } else {
                                        rw = h * aspect
                                    }
                                    
                                    switch shape {
                                    case .square:
                                        // 💡 正方形はアスペクト比を無視し、固定サイズの真四角（w, h）で描画する
                                        builder.addLine(from: [-w/2, h/2], to: [w/2, h/2], thickness: t)
                                        builder.addLine(from: [-w/2, -h/2], to: [w/2, -h/2], thickness: t)
                                        builder.addLine(from: [-w/2, -h/2], to: [-w/2, h/2], thickness: t)
                                        builder.addLine(from: [w/2, -h/2], to: [w/2, h/2], thickness: t)
                                        
                                    case .wide_rect, .tall_rect:
                                        // 💡 長方形は文字のアスペクト比に合わせたサイズ（rw, rh）で描画する
                                        builder.addLine(from: [-rw/2, rh/2], to: [rw/2, rh/2], thickness: t)
                                        builder.addLine(from: [-rw/2, -rh/2], to: [rw/2, -rh/2], thickness: t)
                                        builder.addLine(from: [-rw/2, -rh/2], to: [-rw/2, rh/2], thickness: t)
                                        builder.addLine(from: [rw/2, -rh/2], to: [rw/2, rh/2], thickness: t)
                                        
                                    case .triangle:
                                        builder.addLine(from: [-rw/2, -rh/2], to: [rw/2, -rh/2], thickness: t)
                                        builder.addLine(from: [-rw/2, -rh/2], to: [0, rh/2], thickness: t)
                                        builder.addLine(from: [rw/2, -rh/2], to: [0, rh/2], thickness: t)
                                        
                                    case .inv_triangle:
                                        builder.addLine(from: [-rw/2, rh/2], to: [rw/2, rh/2], thickness: t)
                                        builder.addLine(from: [-rw/2, rh/2], to: [0, -rh/2], thickness: t)
                                        builder.addLine(from: [rw/2, rh/2], to: [0, -rh/2], thickness: t)
                                        
                                    case .trapezoid:
                                        let topW = rw * 0.5
                                        builder.addLine(from: [-topW/2, rh/2], to: [topW/2, rh/2], thickness: t)
                                        builder.addLine(from: [-rw/2, -rh/2], to: [rw/2, -rh/2], thickness: t)
                                        builder.addLine(from: [-rw/2, -rh/2], to: [-topW/2, rh/2], thickness: t)
                                        builder.addLine(from: [rw/2, -rh/2], to: [topW/2, rh/2], thickness: t)
                                        
                                    case .rhombus:
                                        builder.addLine(from: [0.0, rh/2], to: [rw/2, 0.0], thickness: t)
                                        builder.addLine(from: [rw/2, 0.0], to: [0.0, -rh/2], thickness: t)
                                        builder.addLine(from: [0.0, -rh/2], to: [-rw/2, 0.0], thickness: t)
                                        builder.addLine(from: [-rw/2, 0.0], to: [0.0, rh/2], thickness: t)
                                    }
//                    switch shape {
//                    case .square:
//                        builder.addLine(from: [-w/2, h/2], to: [w/2, h/2], thickness: t)
//                        builder.addLine(from: [-w/2, -h/2], to: [w/2, -h/2], thickness: t)
//                        builder.addLine(from: [-w/2, -h/2], to: [-w/2, h/2], thickness: t)
//                        builder.addLine(from: [w/2, -h/2], to: [w/2, h/2], thickness: t)
//                        
//                    case .wide_rect:
//                        let rh = h * 0.45
//                        builder.addLine(from: [-w/2, rh/2], to: [w/2, rh/2], thickness: t)
//                        builder.addLine(from: [-w/2, -rh/2], to: [w/2, -rh/2], thickness: t)
//                        builder.addLine(from: [-w/2, -rh/2], to: [-w/2, rh/2], thickness: t)
//                        builder.addLine(from: [w/2, -rh/2], to: [w/2, rh/2], thickness: t)
//                        
//                    case .tall_rect:
//                        let rw = w * 0.6
//                        builder.addLine(from: [-rw/2, h/2], to: [rw/2, h/2], thickness: t)
//                        builder.addLine(from: [-rw/2, -h/2], to: [rw/2, -h/2], thickness: t)
//                        builder.addLine(from: [-rw/2, -h/2], to: [-rw/2, h/2], thickness: t)
//                        builder.addLine(from: [rw/2, -h/2], to: [rw/2, h/2], thickness: t)
//                        
//                    case .triangle:
//                        builder.addLine(from: [-w/2, -h/2], to: [w/2, -h/2], thickness: t)
//                        builder.addLine(from: [-w/2, -h/2], to: [0, h/2], thickness: t)
//                        builder.addLine(from: [w/2, -h/2], to: [0, h/2], thickness: t)
//                        
//                    case .inv_triangle:
//                        builder.addLine(from: [-w/2, h/2], to: [w/2, h/2], thickness: t)
//                        builder.addLine(from: [-w/2, h/2], to: [0, -h/2], thickness: t)
//                        builder.addLine(from: [w/2, h/2], to: [0, -h/2], thickness: t)
//                        
//                    case .trapezoid:
//                        let topW = w * 0.5
//                        builder.addLine(from: [-topW/2, h/2], to: [topW/2, h/2], thickness: t)
//                        builder.addLine(from: [-w/2, -h/2], to: [w/2, -h/2], thickness: t)
//                        builder.addLine(from: [-w/2, -h/2], to: [-topW/2, h/2], thickness: t)
//                        builder.addLine(from: [w/2, -h/2], to: [topW/2, h/2], thickness: t)
//                        
//                    case .rhombus:
//                        builder.addLine(from: [0.0, h/2], to: [w/2, 0.0], thickness: t)
//                        builder.addLine(from: [w/2, 0.0], to: [0.0, -h/2], thickness: t)
//                        builder.addLine(from: [0.0, -h/2], to: [-w/2, 0.0], thickness: t)
//                        builder.addLine(from: [-w/2, 0.0], to: [0.0, h/2], thickness: t)
//                    }
                    
                case "daikei":
                    let metrics = ARShapeBuilder.getTrapezoidMetrics(char: char, font: ctFont)
                    if metrics.topWidth > 0 && metrics.bottomWidth > 0 && metrics.height > 0 {
                        let tw = metrics.topWidth
                        let bw = metrics.bottomWidth
                        let ch = metrics.height
                        builder.addLine(from: [-tw/2, ch/2], to: [tw/2, ch/2], thickness: t)
                        builder.addLine(from: [-bw/2, -ch/2], to: [bw/2, -ch/2], thickness: t)
                        builder.addLine(from: [-bw/2, -ch/2], to: [-tw/2, ch/2], thickness: t)
                        builder.addLine(from: [bw/2, -ch/2], to: [tw/2, ch/2], thickness: t)
                    }
                    
                case "henTsukuri":
                    let guideType = KanjiVGManager.shared.getGuide(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    if case let .henTsukuri(splitX) = guideType {
                        builder.addLine(from: [splitX, fixedBoxSize / 2], to: [splitX, -fixedBoxSize / 2], thickness: t)
                    } else if case let .center(centerX) = guideType {
                        builder.addLine(from: [centerX, fixedBoxSize / 2], to: [centerX, -fixedBoxSize / 2], thickness: t)
                    } else if case let .shinnyo(splitX, bottomY) = guideType {
                        builder.addLine(from: [splitX, fixedBoxSize / 2], to: [splitX, bottomY], thickness: t)
                        builder.addLine(from: [splitX, bottomY], to: [fixedBoxSize / 2, bottomY], thickness: t)
                    } else if case let .kamae(leftX, rightX, topY, bottomY) = guideType {
                        builder.addLine(from: [leftX, topY], to: [leftX, bottomY], thickness: t)
                        builder.addLine(from: [rightX, topY], to: [rightX, bottomY], thickness: t)
                        builder.addLine(from: [leftX, bottomY], to: [rightX, bottomY], thickness: t)
                    }
                    
                case "shiten":
                    let strokeStarts = KanjiVGManager.shared.getStrokeStarts(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    for point in strokeStarts {
                        builder.addDot(center: [point.x, point.y], radius: dotRadius * 0.75)
                    }
                    
                case "koten":
                    let intersections = KanjiVGManager.shared.getIntersections(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                    for point in intersections {
                        builder.addDot(center: [point.x, point.y], radius: dotRadius)
                    }
                    
                default: break
                }
                
                if let mergedMesh = builder.generate() {
                    let charMat = (modeName == "shiten") ? shitenMat : (modeName == "koten") ? kotenMat : guideMat
                    let charEntity = ModelEntity(mesh: mergedMesh, materials: [charMat])
                    charEntity.position = [0, currentY, 0.0002]
                    group.addChild(charEntity)
                }
            }
            
            currentY -= fixedLineSpacing
        }
        return group
    }
    
    private static func charEntityVisualBounds(mesh: MeshResource) -> SIMD2<Float> {
        let dummyEntity = ModelEntity(mesh: mesh)
        let bounds = dummyEntity.visualBounds(relativeTo: nil)
        return SIMD2<Float>(bounds.center.x, bounds.center.y)
    }
}
