//
//  ContentView.swift
//  ARWrithingApp
//

import SwiftUI
import RealityKit
import ARKit
import Vision

struct ContentView: View {
    var body: some View {
        ARViewContainer()
            .edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        
        arView.session.delegate = context.coordinator
        
        // ==========================================
        // 🎨 ゴムのように伸び縮みする「1m×1mの基準シート」を作る
        // ==========================================
        // ベースとして1m x 1m の平面を作る（後で認識したサイズにScaleで掛け算して変形させます）
        let mesh = MeshResource.generatePlane(width: 1.0, depth: 1.0)
        
        // 赤色で、少し透けて見える（アルファ値0.5）素材にする（デバッグに最適！）
        let material = SimpleMaterial(color: UIColor.red.withAlphaComponent(0.5), isMetallic: false)
        
        let frameEntity = ModelEntity(mesh: mesh, materials: [material])
        frameEntity.isEnabled = false
        
        let anchor = AnchorEntity(world: [0, 0, 0])
        anchor.addChild(frameEntity)
        arView.scene.addAnchor(anchor)
        
        context.coordinator.arView = arView
        context.coordinator.markerEntity = frameEntity
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, ARSessionDelegate {
            weak var arView: ARView?
            var markerEntity: ModelEntity?
            var isProcessing = false
            
            // 🌟 追加：現在の「位置」「サイズ」「角度」を記憶しておく変数
            var currentPosition: SIMD3<Float>?
            var currentScale: SIMD3<Float>?
            var currentAngle: Float?
            
            func session(_ session: ARSession, didUpdate frame: ARFrame) {
                guard !isProcessing else { return }
                isProcessing = true
                
                let pixelBuffer = frame.capturedImage
                
                let request = VNDetectRectanglesRequest { [weak self] request, error in
                    defer { self?.isProcessing = false }
                    
                    guard let results = request.results as? [VNRectangleObservation], let rectangle = results.first else {
                        DispatchQueue.main.async { self?.markerEntity?.isEnabled = false }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        guard let arView = self?.arView else { return }
                        let viewportSize = arView.bounds.size
                        
                        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
                        func convertToScreen(_ visionPoint: CGPoint) -> CGPoint {
                            let flippedY = CGPoint(x: visionPoint.x, y: 1.0 - visionPoint.y)
                            let normalized = flippedY.applying(transform)
                            return CGPoint(x: normalized.x * viewportSize.width, y: normalized.y * viewportSize.height)
                        }
                        
                        let tl = convertToScreen(rectangle.topLeft)
                        let tr = convertToScreen(rectangle.topRight)
                        let bl = convertToScreen(rectangle.bottomLeft)
                        let centerPoint = convertToScreen(CGPoint(x: rectangle.boundingBox.midX, y: rectangle.boundingBox.midY))
                        
                        guard let centerResult = arView.raycast(from: centerPoint, allowing: .estimatedPlane, alignment: .horizontal).first,
                              let tlResult = arView.raycast(from: tl, allowing: .estimatedPlane, alignment: .horizontal).first,
                              let trResult = arView.raycast(from: tr, allowing: .estimatedPlane, alignment: .horizontal).first,
                              let blResult = arView.raycast(from: bl, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
                        
                        let physicalWidth = distance(tlResult.worldTransform.columns.3, trResult.worldTransform.columns.3)
                        let physicalHeight = distance(tlResult.worldTransform.columns.3, blResult.worldTransform.columns.3)
                        
                        print(String(format: "🔍 修正後サイズ: 横 %.1f cm / 縦 %.1f cm", physicalWidth * 100, physicalHeight * 100))
                        
                        let dx3D = trResult.worldTransform.columns.3.x - tlResult.worldTransform.columns.3.x
                        let dz3D = trResult.worldTransform.columns.3.z - tlResult.worldTransform.columns.3.z
                        let targetAngle = atan2(dz3D, dx3D)
                        
                        // 🌟 今回計算した「理想の目標地点」
                        let targetPosition = SIMD3<Float>(
                            centerResult.worldTransform.columns.3.x,
                            centerResult.worldTransform.columns.3.y + 0.001,
                            centerResult.worldTransform.columns.3.z
                        )
                        let targetScale = SIMD3<Float>(physicalWidth, 1.0, physicalHeight)
                        
                        // 🌟 修正ポイント：急に動かさず、少しずつ目標値に近づける（スムージング）
                        if let currPos = self?.currentPosition, let currScale = self?.currentScale, let currAngle = self?.currentAngle {
                            
                            // 15%だけ目標に近づける（数値を小さくするほど、チカチカが減ってヌルッと動く）
                            let smooth: Float = 0.15
                            
                            self?.currentPosition = currPos + (targetPosition - currPos) * smooth
                            self?.currentScale = currScale + (targetScale - currScale) * smooth
                            
                            // 角度の補間（逆回転してしまうのを防ぐ処理）
                            var angleDiff = targetAngle - currAngle
                            while angleDiff > .pi { angleDiff -= 2 * .pi }
                            while angleDiff < -.pi { angleDiff += 2 * .pi }
                            self?.currentAngle = currAngle + angleDiff * smooth
                            
                        } else {
                            // 最初に見つけた時だけは、ワープさせる
                            self?.currentPosition = targetPosition
                            self?.currentScale = targetScale
                            self?.currentAngle = targetAngle
                        }
                        
                        // スムーズに計算された値をARオブジェクトに適用する
                        self?.markerEntity?.position = self!.currentPosition!
                        self?.markerEntity?.scale = self!.currentScale!
                        self?.markerEntity?.orientation = simd_quatf(angle: -(self!.currentAngle!), axis: SIMD3<Float>(0, 1, 0))
                        
                        self?.markerEntity?.isEnabled = true
                    }
                }
                
                request.minimumConfidence = 0.8
                request.maximumObservations = 1
                request.minimumSize = 0.3
                
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
                DispatchQueue.global(qos: .userInteractive).async {
                    try? handler.perform([request])
                }
            }
        }
}

// 3D空間の2点間の距離を計算するヘルパー関数
func distance(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
    let dx = a.x - b.x
    let dy = a.y - b.y
    let dz = a.z - b.z
    return sqrt(dx*dx + dy*dy + dz*dz)
}

#Preview {
    ContentView()
}
