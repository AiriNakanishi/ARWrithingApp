import SwiftUI

enum GuideMode: String, CaseIterable, Identifiable {
    case nazoru = "なぞる"
    case gaikei = "外形"
    case daikei = "外接台形"
    case henTsukuri = "部首の境目"
    case shiten = "始点"
    case koten = "交点"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    @State private var isLocked = false
    @State private var selectedModes: Set<GuideMode> = [.nazoru]
    @State private var baseSize: Float = 0.0105
    @State private var isLeftHanded = false
    
    // 💡 初期状態：ガイド設定パネルは閉じておく
    @State private var isPanelPresented = false
    
    @State private var currentZoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    // 大学の住所をデフォルト設定
    @State private var targetText = "上寺市緑町丘道一丁目"
    // 💡 初期状態：アプリ起動時にすぐ文字設定ポップアップを出すため true にする
    @State private var isEditingText = true
    // ポップアップを開いた時に、現在の文字が最初から入力欄に入っているようにする
    @State private var textInputBuffer = "上寺市緑町丘道一丁目"
    
    let baseParallax = CGSize(width: 0, height: 0)
    
    var body: some View {
        ZStack {
            // ==========================================
            // 🌟 1. 一番奥：ARカメラと3D空間のレイヤー
            // ==========================================
            ARSceneManager(isLocked: $isLocked, selectedModes: selectedModes, baseSize: baseSize, isLeftHanded: isLeftHanded, targetText: targetText)
                .scaleEffect(currentZoom * gestureZoom)
                .offset(x: baseParallax.width + currentOffset.width + gestureOffset.width, y: baseParallax.height + currentOffset.height + gestureOffset.height)
                .gesture(DragGesture().updating($gestureOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in currentOffset.width += value.translation.width; currentOffset.height += value.translation.height })
                .edgesIgnoringSafeArea(.all)
                .gesture(MagnificationGesture().updating($gestureZoom) { value, state, _ in state = value }
                    .onEnded { value in currentZoom *= value; currentZoom = max(1.0, min(currentZoom, 5.0)) })
                .onTapGesture {
                    // パネルが開いている時に背景タップで閉じる
                    if isPanelPresented && !isEditingText {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isPanelPresented = false
                        }
                    }
                }
            
            // ==========================================
            // 🌟 2. 中間：操作ボタンのレイヤー（入力中以外に表示）
            // ==========================================
            if !isEditingText {
                VStack {
                    Spacer() // 下に押し下げる
                    
                    if isPanelPresented {
                        // --- 🎛️ ガイド設定パネル ---
                        VStack(spacing: 15) {
                            HStack {
                                Text("ガイド設定").font(.headline).foregroundColor(.primary)
                                Spacer()
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
                            
                            Picker("利き手設定", selection: $isLeftHanded) {
                                Text("左利き用").tag(true)
                                Text("右利き用").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            
                            HStack {
                                Text("小").font(.caption).foregroundColor(.secondary)
                                Slider(value: $baseSize, in: 0.005...0.015, step: 0.001)
                                Text("大").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            
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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        
                    } else {
                        // --- ⚙️ フローティングアクションボタン群（右下に縦並び） ---
                        HStack {
                            Spacer()
                            
                            VStack(spacing: 16) {
                                // ① 文字変更ボタン（上段）
                                Button(action: {
                                    textInputBuffer = targetText
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isEditingText = true
                                    }
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(width: 56, height: 56)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)
                                }
                                
                                // ② ガイド設定展開ボタン（下段）
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        isPanelPresented = true
                                    }
                                }) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(width: 56, height: 56)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)
                                }
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 25)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
            
            // ==========================================
            // 🌟 3. 一番手前：文字入力ポップアップと暗いベール
            // ==========================================
            if isEditingText {
                // 背景を暗くするベール
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                
                // 中央の入力カード
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("テキスト設定")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("表示する文字を入力してください")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("文字を入力...", text: $textInputBuffer)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .padding(.horizontal, 4)
                    
                    Button(action: {
                        let trimmed = textInputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            targetText = trimmed
                        } else {
                            textInputBuffer = targetText // 空欄なら元の文字に戻す
                        }
                        
                        // キーボードを閉じてポップアップを消す
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isEditingText = false
                        }
                    }) {
                        Text("決定")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(24)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(24)
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 32)
                // フワッと少し拡大しながら現れるアニメーション
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }
}
