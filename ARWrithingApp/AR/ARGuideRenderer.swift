import RealityKit
import UIKit
import CoreText

class ARGuideRenderer {
    static let referenceSize: Float = 0.0105
    static let targetText = "北海道函館市亀田中野町一一六番地二"
    
    private static var textMeshCache: [Character: MeshResource] = [:]
    private static var entityCache: [String: Entity] = [:]
    private static var isGenerating: Set<String> = []
    
    // ===================================================
    // 🌟 1. 起動用（変更なし）
    // ===================================================
    static func createBaseEntity() -> Entity {
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
        
        var currentY: Float = 0.0
        
        for char in targetText {
            let charMesh: MeshResource
            if let cached = textMeshCache[char] { charMesh = cached } else {
                charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
                textMeshCache[char] = charMesh
            }
            
            let charBounds = charEntityVisualBounds(mesh: charMesh)
            let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
            charEntity.position = [-charBounds.x, currentY - charBounds.y, 0.001]
            otehonSide.addChild(charEntity)
            
            for side in [otehonSide, renshuSide] {
                let frameEntity = createRectangularFrame(width: fixedBoxSize, height: fixedBoxSize, thickness: lineThickness, color: UIColor.gray.withAlphaComponent(baseAlpha))
                frameEntity.position = [0, currentY, 0]
                side.addChild(frameEntity)
                
                let crosshairColor = UIColor.gray.withAlphaComponent(baseAlpha)
                let vDashedLine = createDashedLineEntity(from: SIMD3<Float>(0, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(0, currentY - fixedBoxSize / 2, 0), thickness: lineThickness * 0.8, color: crosshairColor, dashLength: dashLen, gapLength: dashLen)
                let hDashedLine = createDashedLineEntity(from: SIMD3<Float>(-fixedBoxSize / 2, currentY, 0), to: SIMD3<Float>(fixedBoxSize / 2, currentY, 0), thickness: lineThickness * 0.8, color: crosshairColor, dashLength: dashLen, gapLength: dashLen)
                side.addChild(vDashedLine); side.addChild(hDashedLine)
            }
            currentY -= fixedLineSpacing
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
    // 🌟 2. オンデマンド生成（変更なし）
    // ===================================================
    static func updateScene(root: Entity, modes: Set<GuideMode>, size: Float, isLeftHanded: Bool) {
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
                                    let newGroup = generateModeGroup(modeName: modeName)
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
        reportPerformance(root: root, duration: duration)
    }
    
    // ===================================================
    // 🌟 3. 専用ジェネレーター（💡 ここが「メッシュ結合」の心臓部です！）
    // ===================================================
    private static func generateModeGroup(modeName: String) -> Entity {
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
        
        let gaikeiShapes: [GuideShape] = [.triangle, .square, .square, .square, .square, .inv_triangle, .trapezoid, .square, .tall_rect, .square, .inv_triangle, .wide_rect, .wide_rect, .triangle, .square, .trapezoid, .wide_rect]
        
        var currentY: Float = 0.0
        
        for (index, char) in targetText.enumerated() {
            
            // 💡 なぞる（nazoru）は文字そのものなので特別扱い（元々1文字1パーツ）
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
                // 💡 ここからが「1文字分のメッシュ結合」の処理
                var builder = MeshBuilder() // 設計図を作る専用スタッフ
                let t = lineThickness * 1.5 // 線の太さ
                
                switch modeName {
                case "gaikei":
                    let shape = gaikeiShapes[index % gaikeiShapes.count]
                    var shapeW = fixedBoxSize, shapeH = fixedBoxSize
                    if shape == .wide_rect { shapeH = fixedBoxSize * 0.45 } else if shape == .tall_rect { shapeW = fixedBoxSize * 0.6 }
                    
                    // 設計図に4本の線を書き込む
                    builder.addLine(from: [-shapeW/2, shapeH/2], to: [shapeW/2, shapeH/2], thickness: t) // 上
                    builder.addLine(from: [-shapeW/2, -shapeH/2], to: [shapeW/2, -shapeH/2], thickness: t) // 下
                    builder.addLine(from: [-shapeW/2, -shapeH/2], to: [-shapeW/2, shapeH/2], thickness: t) // 左
                    builder.addLine(from: [shapeW/2, -shapeH/2], to: [shapeW/2, shapeH/2], thickness: t) // 右
                    
                case "daikei":
                    let metrics = getCharacterMetrics(char: char, font: ctFont)
                    if metrics.topWidth > 0 && metrics.bottomWidth > 0 && metrics.height > 0 {
                        let tw = metrics.topWidth
                        let bw = metrics.bottomWidth
                        let h = metrics.height
                        builder.addLine(from: [-tw/2, h/2], to: [tw/2, h/2], thickness: t) // 上
                        builder.addLine(from: [-bw/2, -h/2], to: [bw/2, -h/2], thickness: t) // 下
                        builder.addLine(from: [-bw/2, -h/2], to: [-tw/2, h/2], thickness: t) // 左
                        builder.addLine(from: [bw/2, -h/2], to: [tw/2, h/2], thickness: t) // 右
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
                
                // 💡 設計図が書き終わったら、一気に「1つのMesh」として実体化させる！
                if let mergedMesh = builder.generate() {
                    let charMat = (modeName == "shiten") ? shitenMat : (modeName == "koten") ? kotenMat : guideMat
                    let charEntity = ModelEntity(mesh: mergedMesh, materials: [charMat])
                    charEntity.position = [0, currentY, 0.0002] // 1文字分のパーツとして配置
                    group.addChild(charEntity)
                }
            }
            
            currentY -= fixedLineSpacing
        }
        return group
    }
    
    // (これ以下の reportPerformance、getCPUUsage、charEntityVisualBounds はそのまま維持)
    private static func reportPerformance(root: Entity, duration: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let memoryUsed = kerr == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0.0
        
        let cpuUsage = getCPUUsage()
        
        func countEntities(_ entity: Entity) -> Int {
            return 1 + entity.children.reduce(0) { $0 + countEntities($1) }
        }
        let entityCount = countEntities(root)
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 [AR Monitor] システム負荷状況")
        print("  🔸 CPU 使用率           : \(String(format: "%.1f", cpuUsage)) %")
        print("  🔸 メモリ使用量 (RAM)   : \(String(format: "%.2f", memoryUsed)) MB / 3072.00 MB")
        print("  🔸 AR空間のオブジェクト数: \(entityCount) 個")
        print("  🔸 処理時間 (メインスレッド): \(String(format: "%.4f", duration)) ms")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    private static func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                guard infoResult == KERN_SUCCESS else { continue }
                let isIdle = threadInfo.flags & TH_FLAGS_IDLE != 0
                if !isIdle {
                    totalUsageOfCPU += (Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }
        return totalUsageOfCPU
    }
    
    private static func charEntityVisualBounds(mesh: MeshResource) -> SIMD2<Float> {
        let dummyEntity = ModelEntity(mesh: mesh)
        let bounds = dummyEntity.visualBounds(relativeTo: nil)
        return SIMD2<Float>(bounds.center.x, bounds.center.y)
    }
    
    // ===================================================
    // 🌟 4. 新規追加：設計図を作るための専用スタッフ（MeshBuilder）
    // ===================================================
    private struct MeshBuilder {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // 四角形（ポリゴン）の情報を追加する
        mutating func addQuad(p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>) {
            let startIdx = UInt32(positions.count)
            positions.append(contentsOf: [p0, p1, p2, p3])
            // 2つの三角形を組み合わせて四角形を作る
            indices.append(contentsOf: [startIdx, startIdx+2, startIdx+1, startIdx, startIdx+3, startIdx+2])
        }
        
        // 線の情報を四角形として追加する
        mutating func addLine(from: SIMD2<Float>, to: SIMD2<Float>, thickness: Float) {
            let dir = to - from
            let length = simd_length(dir)
            guard length > 0 else { return }
            let normDir = dir / length
            // 線に対して垂直なベクトルを計算
            let perp = SIMD2<Float>(-normDir.y, normDir.x) * (thickness / 2.0)
            
            let p0 = SIMD3<Float>(from.x - perp.x, from.y - perp.y, 0)
            let p1 = SIMD3<Float>(from.x + perp.x, from.y + perp.y, 0)
            let p2 = SIMD3<Float>(to.x + perp.x, to.y + perp.y, 0)
            let p3 = SIMD3<Float>(to.x - perp.x, to.y - perp.y, 0)
            
            addQuad(p0: p0, p1: p1, p2: p2, p3: p3)
        }
        
        // 点（ドット）の情報を正方形として追加する
        mutating func addDot(center: SIMD2<Float>, radius: Float) {
            let p0 = SIMD3<Float>(center.x + radius, center.y - radius, 0)
            let p1 = SIMD3<Float>(center.x - radius, center.y - radius, 0)
            let p2 = SIMD3<Float>(center.x - radius, center.y + radius, 0)
            let p3 = SIMD3<Float>(center.x + radius, center.y + radius, 0)
            addQuad(p0: p0, p1: p1, p2: p2, p3: p3)
        }
        
        // 設計図から本物のMeshResourceを一撃で生成する
        func generate() -> MeshResource? {
            guard !positions.isEmpty else { return nil }
            var desc = MeshDescriptor(name: "mergedMesh")
            desc.positions = MeshBuffers.Positions(positions)
            desc.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [desc])
        }
    }
}
