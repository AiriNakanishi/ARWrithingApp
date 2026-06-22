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
    @State private var selectedMode: GuideMode = .koten
    
    @State private var currentZoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    let baseParallax = CGSize(width: 0, height: 0)
    
    var body: some View {
        ZStack {
            // ARの画面は別ファイル（ARSceneManager）に切り出しました！
            ARSceneManager(isLocked: $isLocked, selectedMode: selectedMode)
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
                VStack(spacing: 15) {
                    Picker("ガイドモード", selection: $selectedMode) {
                        ForEach(GuideMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal).background(Color(UIColor.systemBackground).opacity(0.7)).cornerRadius(8)
                    
                    Button(action: { isLocked.toggle() }) {
                        Text(isLocked ? "解除" : "固定")
                            .font(.title2).fontWeight(.semibold).foregroundColor(.white)
                            .padding().frame(width: 120, height: 35)
                            .background(isLocked ? Color.red.opacity(0.4) : Color.blue.opacity(0.4) )
                            .cornerRadius(15).shadow(radius: 5)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
    }
}
