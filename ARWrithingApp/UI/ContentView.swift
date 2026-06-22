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
    @State private var selectedModes: Set<GuideMode> = [.nazoru]
    @State private var baseSize: Float = 0.0105
    @State private var isLeftHanded = false
    
    // 🌟 修正1: 設定パネルが表示されているかどうかを管理するフラグ（最初は開いておく）
    @State private var isPanelPresented = true
    
    @State private var currentZoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    let baseParallax = CGSize(width: 0, height: 0)
    
    var body: some View {
        ZStack {
            // ARViewの背景部分
            ARSceneManager(isLocked: $isLocked, selectedModes: selectedModes, baseSize: baseSize, isLeftHanded: isLeftHanded)
                .scaleEffect(currentZoom * gestureZoom)
                .offset(x: baseParallax.width + currentOffset.width + gestureOffset.width, y: baseParallax.height + currentOffset.height + gestureOffset.height)
                .gesture(DragGesture().updating($gestureOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in currentOffset.width += value.translation.width; currentOffset.height += value.translation.height })
                .edgesIgnoringSafeArea(.all)
                .gesture(MagnificationGesture().updating($gestureZoom) { value, state, _ in state = value }
                    .onEnded { value in currentZoom *= value; currentZoom = max(1.0, min(currentZoom, 5.0)) })
                
                // 🌟 修正2: AR画面のどこかをタップしたらメニューを自動で閉じる親切設計
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isPanelPresented = false
                    }
                }
            
            // 🌟 修正3: コントロールパネルとフローティングボタンのレイアウト
            VStack {
                Spacer()
                
                if isPanelPresented {
                    // --- 🎛️ 設定パネル（表示中のみ下からスッと出現） ---
                    VStack(spacing: 15) {
                        HStack {
                            Text("ガイド設定").font(.headline).foregroundColor(.primary)
                            Spacer()
                            // 閉じる用のバツボタン
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isPanelPresented = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        }
                        .padding(.horizontal)
                        
                        // 右利き/左利き切り替え
                        Picker("利き手設定", selection: $isLeftHanded) {
                            Text("左利き用").tag(true)
                            Text("右利き用").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // 📏 サイズ変更スライダー
                        HStack {
                            Text("小").font(.caption).foregroundColor(.secondary)
                            Slider(value: $baseSize, in: 0.005...0.015, step: 0.001)
                            Text("大").font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        // 🔘 ガイド選択ボタン
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
                    .background(Color(UIColor.systemBackground).opacity(0.92))
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -5)
                    .padding(.horizontal, 15)
                    .padding(.bottom, 15)
                    // 下からニュッと出てくるアニメーション効果
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                } else {
                    
                    // --- ⚙️ フローティングアクションボタン（パネルが閉じている時のみ右下に表示） ---
                    HStack {
                        Spacer() // 右側に寄せる
                        Button(action: {
                            // スプリングアニメーションで心地よく展開
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isPanelPresented = true
                            }
                        }) {
                            // FlutterのIcons.sliderの感覚でSF Symbolsのアイコンを指定
                            Image(systemName: "slider.horizontal.3")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)
                        }
                        .padding(.trailing, 25)
                        .padding(.bottom, 25)
                        // ふわっと現れるアニメーション効果
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }
}
