import SwiftUI

/// 錶盤風格。
///
/// 只換錶盤本身；按鈕、任務欄、設定頁維持原本的主題。縮小模式的**形狀**跟著風格走——
/// 像素是方的、翻頁鐘和 LCD 是寬的、沙漏是高的——因為把一個方形像素螢幕硬塞進圓形裡很彆扭。
enum DialStyle: String, CaseIterable, Identifiable {
    case classic, pixel, flip, lcd, hourglass, moon, water, bauhaus, minimal, station

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic:   return "經典刻度"
        case .pixel:     return "像素"
        case .flip:      return "翻頁鐘"
        case .lcd:       return "LCD 電子錶"
        case .hourglass: return "沙漏"
        case .moon:      return "月相"
        case .water:     return "水位"
        case .bauhaus:   return "包浩斯"
        case .minimal:   return "極簡環"
        case .station:   return "車站鐘"
        }
    }

    var note: String {
        switch self {
        case .classic:   return "60 格刻度，走過的上色"
        case .pixel:     return "8-bit 掌機的四階綠"
        case .flip:      return "分鐘變的時候翻一頁"
        case .lcd:       return "七段數字，沒亮的段淡淡留著"
        case .hourglass: return "上面的沙就是剩下的時間"
        case .moon:      return "由滿月慢慢缺成新月"
        case .water:     return "兩道波浪，淹到的數字反白"
        case .bauhaus:   return "紅黃藍的幾何構成"
        case .minimal:   return "一道圓環，末端一顆圓鈕"
        case .station:   return "黑色粗刻度配紅色秒針"
        }
    }

    // MARK: 版面

    /// 縮小模式的視窗尺寸
    var compactSize: CGSize {
        switch self {
        case .pixel:     return CGSize(width: 160, height: 160)
        case .flip:      return CGSize(width: 232, height: 112)
        case .lcd:       return CGSize(width: 212, height: 112)
        case .hourglass: return CGSize(width: 132, height: 184)
        case .bauhaus:   return CGSize(width: 164, height: 164)
        default:         return CGSize(width: 168, height: 168)
        }
    }

    /// 完整模式裡錶盤面板的尺寸，放在大約 284×222 的區域裡
    var fullSize: CGSize {
        switch self {
        case .pixel:     return CGSize(width: 196, height: 196)
        case .flip:      return CGSize(width: 268, height: 130)
        case .lcd:       return CGSize(width: 252, height: 132)
        case .hourglass: return CGSize(width: 146, height: 200)
        case .bauhaus:   return CGSize(width: 192, height: 192)
        default:         return CGSize(width: 196, height: 196)
        }
    }

    var isRound: Bool {
        switch self {
        case .classic, .moon, .water, .minimal, .station: return true
        default: return false
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .pixel:     return 6       // 像素螢幕不該太圓
        case .flip:      return 18
        case .lcd:       return 22
        case .hourglass: return 26
        case .bauhaus:   return 4       // 包浩斯是直角的
        default:         return 0
        }
    }

    /// 輪廓。填色、提醒色、描邊、脈動外框都用它，取代原本寫死的 Circle()。
    var silhouette: AnyShape {
        isRound
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 懸停時要不要把錶面壓暗、按鈕疊在正中間。
    /// 寬的（翻頁鐘、LCD）、高的（沙漏）、指針式的（車站鐘），和數字壓在下半部的
    /// （月相、包浩斯）底下都沒有空位放按鈕。
    ///
    /// 車站鐘刻意不叫「瑞士鐵路鐘」、也不做紅色圓盤秒針：那是瑞士聯邦鐵路（SBB）受保護的設計，
    /// Apple 在 iOS 用了類似的樣子後付過授權費，而這個 repo 是公開的。
    var dimsOnHover: Bool {
        switch self {
        case .flip, .lcd, .hourglass, .station, .moon, .bauhaus: return true
        default: return false
        }
    }

    /// 縮小模式輪廓和視窗邊緣的距離。
    /// 系統陰影畫在視窗外面不受影響；留這一圈是讓輪廓的抗鋸齒邊不會被視窗邊界切平。
    static let inset: CGFloat = 6

    // MARK: 配色

    /// 有自己配色身分的風格。休息時不改色，改用小標記區分——
    /// 車站鐘的紅秒針、LCD 的灰綠液晶就是它們的身分。
    var keepsPalette: Bool {
        switch self {
        case .pixel, .flip, .lcd, .bauhaus, .station: return true
        default: return false
        }
    }

    /// 輪廓的底色
    var surface: Color {
        switch self {
        case .pixel:   return Color(hex: 0x9BBC0F)
        case .flip:    return Color(hex: 0x1D1D1F)
        case .lcd:     return Color(hex: 0xC4CFA1)
        case .moon:    return Color(hex: 0x10152A)
        case .bauhaus: return Color(hex: 0xF1EADB)
        // 深色模式下一整片白錶面太刺眼，壓成暖灰，刻度和指針的對比還夠
        case .station: return Theme.dyn(0xFBFBF8, 0xD9D6D0)
        default:       return Theme.surface
        }
    }

    var outline: Color {
        switch self {
        case .pixel:   return Color(hex: 0x0F380F)
        case .flip:    return Color(hex: 0x000000).opacity(0.6)
        case .lcd:     return Color(hex: 0x8A9468)
        case .moon:    return Color(hex: 0x000000).opacity(0.5)
        case .bauhaus: return Color(hex: 0x1A1A1A)
        case .station: return Color(hex: 0x1A1A1A).opacity(0.18)
        default:       return Theme.hairline
        }
    }

    /// 完整模式要不要畫出面板底。經典刻度和極簡環本來就是浮在視窗底色上的線條，
    /// 其餘的都有「一塊螢幕／錶面／玻璃」這個實體，沒有面板會散掉。
    var showsPanelInFull: Bool {
        switch self {
        case .classic, .minimal: return false
        default: return true
        }
    }
}

extension Color {
    /// 風格的固定配色用。一般介面顏色請用 Theme 的 token。
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
