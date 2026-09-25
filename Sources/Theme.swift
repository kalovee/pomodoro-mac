import SwiftUI
import AppKit

/// 設計 token：中性色偏一點暖，跟蕃茄紅同一個色溫家族；
/// 強調色只用在錶盤與主要按鈕，其餘一律灰階，讓層次不會被拉平。
enum Theme {

    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: nsDyn(light, dark))
    }

    /// 視窗底色要用 NSColor 設，而且必須跟 SwiftUI 那邊同一個色票，
    /// 否則標題列那一塊會透出系統預設灰，接縫會看得出來。
    static func nsDyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(isDark ? dark : light)
        }
    }

    static let groundNS = nsDyn(0xF3F1EF, 0x151413)

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                alpha: 1)
    }

    static let ground   = dyn(0xF3F1EF, 0x151413)
    static let surface  = dyn(0xFBFAF9, 0x1E1D1C)
    static let ink      = dyn(0x1A1918, 0xF2F0EE)
    static let muted    = dyn(0x7A7671, 0x8C8781)
    static let hairline = dyn(0xDDD9D5, 0x302E2C)
    static let fill     = dyn(0xE8E5E2, 0x272524)

    static func accent(_ phase: Phase) -> Color {
        switch phase {
        case .work:       return dyn(0xD4443A, 0xFF6A5C)
        case .shortBreak: return dyn(0x2E8F78, 0x46C4A6)
        case .longBreak:  return dyn(0x4B6BB0, 0x7FA2E8)
        }
    }

    // 字級：11 / 12.5 / 14 三階，加上錶盤的大數字
    static func clock(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded).monospacedDigit()
    }
    static let eyebrow = Font.system(size: 10.5, weight: .semibold)
    static let label   = Font.system(size: 12.5)
    static let caption = Font.system(size: 11)
}

/// 錶盤刻度。60 根一次畫成一條路徑。
///
/// 原本是 60 個 Capsule 各自帶兩層 frame 和 rotationEffect，等於每次重畫都要
/// 重建兩百多個 view modifier。浮在別的 App 全螢幕上面時，每次重畫都要重新合成，
/// 這是頓挫的主因之一。改成 Shape 之後整個錶盤只剩三層。
struct Ticks: Shape {
    let range: Range<Int>
    /// nil = 全畫，true = 只畫 5 的倍數（長刻度），false = 只畫其餘
    let majorsOnly: Bool?
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = diameter / 2

        for i in range {
            let major = i % 5 == 0
            if let want = majorsOnly, want != major { continue }

            let width: CGFloat = major ? 2 : 1.5
            let height: CGFloat = major ? diameter * 0.055 : diameter * 0.032
            let angle = Double(i) / 60 * 2 * .pi

            // 刻度從外緣往內長，中心落在外緣與內端的中點
            let mid = radius - height / 2
            let position = CGPoint(x: center.x + sin(angle) * mid,
                                   y: center.y - cos(angle) * mid)

            let tick = Path(roundedRect: CGRect(x: -width / 2, y: -height / 2,
                                                width: width, height: height),
                            cornerRadius: width / 2)
                .applying(CGAffineTransform(rotationAngle: angle))
                .applying(CGAffineTransform(translationX: position.x, y: position.y))
            path.addPath(tick)
        }
        return path
    }
}

/// 刻度錶盤：60 格對應鐘面，每 5 格一根長刻度；
/// 走過的刻度上色，末端一顆指針點標出目前位置。
struct Dial: View {
    let progress: Double
    let tint: Color
    var diameter: CGFloat
    var showsHand: Bool = true

    private var passed: Int {
        min(60, max(0, Int(progress * 60)))
    }

    var body: some View {
        ZStack {
            // 還沒走到的：長短刻度濃度不同，維持原本的層次
            Ticks(range: passed..<60, majorsOnly: true, diameter: diameter)
                .fill(Theme.hairline.opacity(0.9))
            Ticks(range: passed..<60, majorsOnly: false, diameter: diameter)
                .fill(Theme.hairline.opacity(0.55))
            // 走過的：一律滿濃度，所以長短可以合成同一條路徑
            Ticks(range: 0..<passed, majorsOnly: nil, diameter: diameter)
                .fill(tint)

            if showsHand {
                Circle()
                    .fill(tint)
                    .frame(width: diameter * 0.038, height: diameter * 0.038)
                    .frame(width: diameter, height: diameter, alignment: .top)
                    .offset(y: diameter * 0.028)
                    .rotationEffect(.degrees(progress * 360))
                    // 這裡刻意沒有隱式動畫。progress 每次更新都會重啟一段
                    // 0.25 秒的動畫，而更新永不停止——等於視窗以螢幕更新率
                    // 持續重繪，永遠不會安定下來。
                    .shadow(color: tint.opacity(0.5), radius: 3)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 提醒時圍在錶盤外的呼吸光環。
///
/// `breath` 刻意做成外部傳入的純輸入，而不是元件內部的動畫狀態——
/// 探針才能把兩個極端決定性地算成圖，檢查有沒有被視窗邊緣切到。
///
/// 只會內縮不會放大：`ContentView` 有 .clipped()，而縮小模式的內容
/// 剛好等於視窗尺寸，超過 1.0 的縮放會被切在邊緣，看起來像畫錯。
struct PulseRing: View {
    let tint: Color
    /// 0 = 最淡最細，1 = 最濃最粗
    let breath: Double
    let diameter: CGFloat

    var body: some View {
        Circle()
            .stroke(tint.opacity(0.18 + 0.38 * breath), lineWidth: 2 + 4 * breath)
            .frame(width: diameter, height: diameter)
            .scaleEffect(1 - 0.05 * breath)
    }
}

/// 一個循環裡的輪數，用實心／空心點表示——因為它本來就是一個有序的序列
struct RoundDots: View {
    let done: Int
    let total: Int
    let tint: Color
    var dot: CGFloat = 5

    var body: some View {
        HStack(spacing: dot * 0.9) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Circle()
                    .fill(i < done ? tint : Theme.hairline)
                    .frame(width: dot, height: dot)
            }
        }
    }
}

/// 兩種模式的視窗尺寸，集中在一個地方，讓畫面和視窗動畫用同一組數字
enum Metrics {
    static let full = CGSize(width: 320, height: 408)
    static let compact = CGSize(width: 168, height: 168)
    static let morph = 0.26
    /// 提醒脈動的半週期（秒）
    static let pulse = 0.85          // 縮放動畫長度
}
