import RealityKit
import UIKit
import CoreText

class ARGuideRenderer {
    static let referenceSize: Float = 0.0105
    static let targetText = "北海道函館市亀田中野町一一六番地二"
    
    // ===================================================
    // 🌟 楽屋（キャッシュ）の準備
    // ===================================================
    private static var textMeshCache: [Character: MeshResource] = [:]
    private static var sharedShitenMesh: MeshResource?
    private static var sharedKotenMesh: MeshResource?
    
    // 💡 新規追加：AR空間から引っこ抜いたEntityをしまっておく「見えないおもちゃ箱」
    private static var entityCache: [String: Entity] = [:]
    
    // ===================================================
    // 🌟 1. 起動用：お手本とベースの枠線だけを作る（超軽量）
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
            
            // お手本文字を配置
            let charEntity = ModelEntity(mesh: charMesh, materials: [textMaterial])
            charEntity.position = [-charBounds.x, currentY - charBounds.y, 0.001]
            otehonSide.addChild(charEntity)
            
            // ベースの枠と点線を両側に配置
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
    // 🌟 2. オンデマンド生成 ＆ 着脱式キャッシュの適用
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
            // nazoru は練習側のみ、その他は両側に表示
            let targetSides = (modeName == "nazoru") ? [renshuSide] : allSides
            
            for side in allSides {
                let sideName = side.name // "OtehonSide" または "RenshuSide"
                let cacheKey = "\(sideName)_\(modeName)" // 例："RenshuSide_daikei"
                
                // このSideに今表示すべきか？
                let shouldBeVisible = isActive && targetSides.contains(side)
                
                if shouldBeVisible {
                    // 💡 表示する時：ステージに居なければ、楽屋から出すか新しく作る
                    if side.findEntity(named: modeName) == nil {
                        if let cachedGroup = entityCache[cacheKey] {
                            // 楽屋（キャッシュ）に居たのでステージに出す
                            side.addChild(cachedGroup)
                        } else {
                            // 楽屋にも居ないので、新しく作って楽屋リストにも登録しつつステージへ
                            let newGroup = generateModeGroup(modeName: modeName)
                            entityCache[cacheKey] = newGroup
                            side.addChild(newGroup)
                        }
                    }
                } else {
                    // 💡 非表示にする時：ステージに居たら、物理的に引っこ抜いて楽屋へ
                    if let existingGroup = side.findEntity(named: modeName) {
                        existingGroup.removeFromParent() // isEnabledではなく、ツリーから完全に外す
                    }
                }
            }
        }
        
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        reportPerformance(root: root, duration: duration)
    }
    
    // ===================================================
    // 🌟 3. 専用ジェネレーター：必要なものだけをパッと作る
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
        
        if sharedShitenMesh == nil { sharedShitenMesh = MeshResource.generateSphere(radius: dotRadius * 0.75) }
        if sharedKotenMesh == nil { sharedKotenMesh = MeshResource.generateSphere(radius: dotRadius) }
        
        var traceMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.2)); traceMaterial.blending = .transparent(opacity: 1.0)
        var shitenMat = UnlitMaterial(color: UIColor.red.withAlphaComponent(baseAlpha)); shitenMat.blending = .transparent(opacity: 1.0)
        var kotenMat = UnlitMaterial(color: UIColor.magenta.withAlphaComponent(baseAlpha)); kotenMat.blending = .transparent(opacity: 1.0)
        
        let gaikeiShapes: [GuideShape] = [.triangle, .square, .square, .square, .square, .inv_triangle, .trapezoid, .square, .tall_rect, .square, .inv_triangle, .wide_rect, .wide_rect, .triangle, .square, .trapezoid, .wide_rect]
        
        var currentY: Float = 0.0
        
        for (index, char) in targetText.enumerated() {
            switch modeName {
            case "nazoru":
                let charMesh: MeshResource
                if let cached = textMeshCache[char] { charMesh = cached } else {
                    charMesh = MeshResource.generateText(String(char), extrusionDepth: 0.0, font: uiFont)
                    textMeshCache[char] = charMesh
                }
                let bounds = charEntityVisualBounds(mesh: charMesh)
                let traceEntity = ModelEntity(mesh: charMesh, materials: [traceMaterial])
                traceEntity.position = [-bounds.x, currentY - bounds.y, 0.001]
                group.addChild(traceEntity)
                
            case "gaikei":
                let shape = gaikeiShapes[index % gaikeiShapes.count]
                var shapeW = fixedBoxSize, shapeH = fixedBoxSize
                if shape == .wide_rect { shapeH = fixedBoxSize * 0.45 } else if shape == .tall_rect { shapeW = fixedBoxSize * 0.6 }
                let frame = createGuideFrame(shape: shape, width: shapeW, height: shapeH, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))
                frame.position = [0, currentY, 0]
                group.addChild(frame)
                
            case "daikei":
                let metrics = getCharacterMetrics(char: char, font: ctFont)
                // 🌟 修正ポイント：幅や高さが0以下の時にエンジンがクラッシュするのを防ぐ安全装置
                if metrics.topWidth > 0 && metrics.bottomWidth > 0 && metrics.height > 0 {
                    let frame = createDynamicTrapezoid(topWidth: metrics.topWidth, bottomWidth: metrics.bottomWidth, height: metrics.height, thickness: lineThickness * 1.5, color: UIColor.blue.withAlphaComponent(baseAlpha))
                    frame.position = [0, currentY, 0]
                    group.addChild(frame)
                }
                
            case "henTsukuri":
                let guideType = KanjiVGManager.shared.getGuide(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                let subGroup = Entity()
                let color = UIColor.blue.withAlphaComponent(baseAlpha)
                let thick = lineThickness * 1.5
                if case let .henTsukuri(splitX) = guideType { subGroup.addChild(createLineEntity(from: SIMD3<Float>(splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(splitX, currentY - fixedBoxSize / 2, 0), thickness: thick, color: color)) }
                else if case let .center(centerX) = guideType { subGroup.addChild(createLineEntity(from: SIMD3<Float>(centerX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(centerX, currentY - fixedBoxSize / 2, 0), thickness: thick, color: color)) }
                else if case let .shinnyo(splitX, bottomY) = guideType { subGroup.addChild(createLineEntity(from: SIMD3<Float>(splitX, currentY + fixedBoxSize / 2, 0), to: SIMD3<Float>(splitX, currentY + bottomY, 0), thickness: thick, color: color)); subGroup.addChild(createLineEntity(from: SIMD3<Float>(splitX, currentY + bottomY, 0), to: SIMD3<Float>(fixedBoxSize / 2, currentY + bottomY, 0), thickness: thick, color: color)) }
                else if case let .kamae(leftX, rightX, topY, bottomY) = guideType { subGroup.addChild(createLineEntity(from: SIMD3<Float>(leftX, currentY + topY, 0), to: SIMD3<Float>(leftX, currentY + bottomY, 0), thickness: thick, color: color)); subGroup.addChild(createLineEntity(from: SIMD3<Float>(rightX, currentY + topY, 0), to: SIMD3<Float>(rightX, currentY + bottomY, 0), thickness: thick, color: color)); subGroup.addChild(createLineEntity(from: SIMD3<Float>(leftX, currentY + bottomY, 0), to: SIMD3<Float>(rightX, currentY + bottomY, 0), thickness: thick, color: color)) }
                group.addChild(subGroup)
                
            case "shiten":
                let strokeStarts = KanjiVGManager.shared.getStrokeStarts(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                for point in strokeStarts {
                    let dot = ModelEntity(mesh: sharedShitenMesh!, materials: [shitenMat])
                    dot.position = [point.x, currentY + point.y, 0.0002]
                    group.addChild(dot)
                }
                
            case "koten":
                let intersections = KanjiVGManager.shared.getIntersections(for: char, boxWidth: fixedBoxSize, boxHeight: fixedBoxSize)
                for point in intersections {
                    let dot = ModelEntity(mesh: sharedKotenMesh!, materials: [kotenMat])
                    dot.position = [point.x, currentY + point.y, 0.0002]
                    group.addChild(dot)
                }
                
            default: break
            }
            currentY -= fixedLineSpacing
        }
        return group
    }
    
    // (これ以下の reportPerformance、getCPUUsage、charEntityVisualBounds 等の既存の関数は変更なしのため省略せずそのまま維持してください)
    
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
}
