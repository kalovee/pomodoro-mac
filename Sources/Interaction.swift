import SwiftUI

// MARK: - 按鈕回饋
//
// 這裡的動畫都只在「操作的那一刻」跑：按下、放開、滑鼠移進移出、完成一段。
// 跑完就停，不會像當初綁在 progress 上的隱式動畫那樣讓視窗一直重畫（見 README「效能」）。

/// 按下縮一點、放開彈回，讓按鈕有「被按到」的手感
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 取代 @State 用的（原因見 ContentView.swift 的 ViewState）
final class HoverState: ObservableObject {
    @Published var on = false
}

/// 滑鼠移上去微微放大、提亮，告訴使用者「這個可以按」
private struct HoverLift: ViewModifier {
    let amount: CGFloat
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        content
            .scaleEffect(hover.on ? amount : 1)
            .brightness(hover.on ? 0.04 : 0)
            .animation(.easeOut(duration: 0.15), value: hover.on)
            .onHover { hover.on = $0 }
    }
}

extension View {
    func hoverLift(_ amount: CGFloat = 1.06) -> some View {
        modifier(HoverLift(amount: amount))
    }
}

// MARK: - 完成動畫

struct BurstValue {
    var scale: CGFloat = 0.6
    var opacity: Double = 0
}

/// 完成一段時，從錶盤往外擴散的一圈環和 12 顆小點，約 1.2 秒跑完就停。
///
/// 用 keyframeAnimator 綁在 `trigger`（model 的 completionCount）上：只有數字變的那一刻會跑一次，
/// 平常透明度是 0、不動、不重畫。
struct CompletionBurst: View {
    let trigger: Int
    let tint: Color
    let diameter: CGFloat

    var body: some View {
        Color.clear
            .frame(width: diameter, height: diameter)
            .keyframeAnimator(initialValue: BurstValue(), trigger: trigger) { _, v in
                ZStack {
                    Circle()
                        .stroke(tint.opacity(v.opacity), lineWidth: 3)
                        .scaleEffect(v.scale)
                    ForEach(0..<12, id: \.self) { i in
                        Circle()
                            .fill(tint.opacity(v.opacity))
                            .frame(width: 5, height: 5)
                            .offset(y: -diameter / 2 * v.scale)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                }
                .frame(width: diameter, height: diameter)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.55, duration: 0.01)
                    SpringKeyframe(1.0, duration: 1.1, spring: .bouncy)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.9, duration: 0.08)
                    LinearKeyframe(0.9, duration: 0.35)
                    LinearKeyframe(0, duration: 0.75)
                }
            }
            .allowsHitTesting(false)
    }
}
