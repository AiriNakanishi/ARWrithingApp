import SwiftUI

enum GuideMode: String, CaseIterable, Identifiable {
    case nazoru = "なぞる"
    case gaikei = "外形"
    case daikei = "台形"
    case henTsukuri = "へんとつくり"
    case shiten = "始点"
    case koten = "交点"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    @State private var isLocked = false
    // 🌟 修正1: どれか1つではなく「Set」を使って複数選択可能にしました
    @State private var selectedModes: Set<GuideMode> = [.koten]
    
    // 🌟 修正2: 文字サイズを動的に変更するための変数（初期値は今までと同じ 0.0105）
    @State private var baseSize: Float = 0.0105
    
    @State private var currentZoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    let baseParallax = CGSize(width: 0, height: 0)
    
    var body: some View {
        ZStack {
            // 🌟 サイズと複数選択モードをAR側に渡します
            ARSceneManager(isLocked: $isLocked, selectedModes: selectedModes, baseSize: baseSize)
                .scaleEffect(currentZoom * gestureZoom)
                .offset(x: baseParallax.width + currentOffset.width + gestureOffset.width, y: baseParallax.height + currentOffset.height + gestureOffset.height)
                .gesture(DragGesture().updating($gestureOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in currentOffset.width += value.translation.width; currentOffset.height += value.translation.height })
                .edgesIgnoringSafeArea(.all)
                .gesture(MagnificationGesture().updating($gestureZoom) { value, state, _ in state = value }
                    .onEnded { value in currentZoom *= value; currentZoom = max(1.0, min(currentZoom, 5.0)) })
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: gestureOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: gestureZoom)
                .animation(.easeOut(duration: 0.2), value: currentZoom)
            
            VStack {
                Spacer()
                
                // 🎛️ UIコントロールパネル
                VStack(spacing: 15) {
                    // 📏 サイズ変更スライダー
                    HStack {
                        Text("小").font(.caption).foregroundColor(.secondary)
                        Slider(value: $baseSize, in: 0.005...0.015, step: 0.001)
                        Text("大").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // 🔘 重ね合わせ可能なガイド選択ボタン
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(GuideMode.allCases) { mode in
                                Button(action: {
                                    if selectedModes.contains(mode) {
                                        selectedModes.remove(mode)
                                    } else {
                                        selectedModes.insert(mode)
                                    }
                                }) {
                                    Text(mode.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(selectedModes.contains(mode) ? Color.blue : Color.gray.opacity(0.3))
                                        .foregroundColor(selectedModes.contains(mode) ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Button(action: { isLocked.toggle() }) {
                        Text(isLocked ? "解除" : "固定")
                            .font(.headline).fontWeight(.bold).foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isLocked ? Color.red.opacity(0.6) : Color.blue.opacity(0.6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 15)
                .background(Color(UIColor.systemBackground).opacity(0.85))
                .cornerRadius(20)
                .padding(.horizontal, 15)
                .padding(.bottom, 20)
            }
        }
    }
}
