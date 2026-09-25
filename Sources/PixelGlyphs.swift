import SwiftUI

/// 像素數字與七段顯示的字形表。
///
/// 系統沒有像素字型，附字型檔又有授權問題，所以兩種都直接在程式裡畫。
/// 字形都在終端機印出來確認過每個字認得出來。
enum PixelGlyphs {
    /// 3×5 點陣，1＝亮。冒號是 1×5。
    static let digits: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"],
        "7": ["111", "001", "010", "010", "010"],
        "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"],
        ":": ["0", "1", "0", "1", "0"],
    ]

    /// 像素番茄（專注）與咖啡杯（休息），7×6。
    /// 2＝深色（葉子、杯把），1＝最深色。
    static let tomato: [String] = [
        "0022200",
        "0112110",
        "1111111",
        "1111111",
        "1111111",
        "0111110",
    ]
    static let cup: [String] = [
        "0200200",
        "0000000",
        "1111100",
        "1111122",
        "1111102",
        "0111000",
    ]

    /// 一串文字的點陣寬度（以像素為單位）：每個字 3 寬、冒號 1 寬、字間 1 格
    static func width(of text: String) -> Int {
        let widths = text.map { $0 == ":" ? 1 : 3 }
        return widths.reduce(0, +) + max(0, widths.count - 1)
    }

    /// 在 Canvas 裡畫一串像素數字，左上角為 origin、每個像素邊長 px
    static func draw(_ text: String, in ctx: GraphicsContext, at origin: CGPoint,
                     px: CGFloat, color: Color) {
        var path = Path()
        var x = origin.x
        for ch in text {
            guard let rows = digits[ch] else { continue }
            let w = rows[0].count
            for (r, row) in rows.enumerated() {
                for (col, bit) in row.enumerated() where bit == "1" {
                    path.addRect(CGRect(x: x + CGFloat(col) * px, y: origin.y + CGFloat(r) * px,
                                        width: px, height: px))
                }
            }
            x += CGFloat(w + 1) * px
        }
        ctx.fill(path, with: .color(color))
    }

    static func drawIcon(_ rows: [String], in ctx: GraphicsContext, at origin: CGPoint,
                         px: CGFloat, dark: Color, mid: Color) {
        var darkPath = Path(), midPath = Path()
        for (r, row) in rows.enumerated() {
            for (col, bit) in row.enumerated() {
                let rect = CGRect(x: origin.x + CGFloat(col) * px, y: origin.y + CGFloat(r) * px,
                                  width: px, height: px)
                if bit == "1" { darkPath.addRect(rect) }
                if bit == "2" { midPath.addRect(rect) }
            }
        }
        ctx.fill(darkPath, with: .color(dark))
        ctx.fill(midPath, with: .color(mid))
    }

    // MARK: 七段顯示

    /// 標準七段對應：a 上、b 右上、c 右下、d 下、e 左下、f 左上、g 中
    static let segments: [Character: Set<Character>] = [
        "0": ["a", "b", "c", "d", "e", "f"],
        "1": ["b", "c"],
        "2": ["a", "b", "g", "e", "d"],
        "3": ["a", "b", "g", "c", "d"],
        "4": ["f", "g", "b", "c"],
        "5": ["a", "f", "g", "c", "d"],
        "6": ["a", "f", "g", "e", "d", "c"],
        "7": ["a", "b", "c"],
        "8": ["a", "b", "c", "d", "e", "f", "g"],
        "9": ["a", "b", "c", "d", "f", "g"],
    ]

    /// 一個七段數字的七條段，回傳 (段名, 路徑)。段的兩端削尖，是 LCD 的樣子。
    static func segmentPaths(in rect: CGRect, thickness t: CGFloat) -> [(Character, Path)] {
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        let ym = rect.midY
        let g: CGFloat = t * 0.18   // 段與段之間的細縫

        func horizontal(_ y: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x0 + g, y: y))
            p.addLine(to: CGPoint(x: x0 + g + t / 2, y: y - t / 2))
            p.addLine(to: CGPoint(x: x1 - g - t / 2, y: y - t / 2))
            p.addLine(to: CGPoint(x: x1 - g, y: y))
            p.addLine(to: CGPoint(x: x1 - g - t / 2, y: y + t / 2))
            p.addLine(to: CGPoint(x: x0 + g + t / 2, y: y + t / 2))
            p.closeSubpath()
            return p
        }
        func vertical(_ x: CGFloat, _ top: CGFloat, _ bottom: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x, y: top + g))
            p.addLine(to: CGPoint(x: x + t / 2, y: top + g + t / 2))
            p.addLine(to: CGPoint(x: x + t / 2, y: bottom - g - t / 2))
            p.addLine(to: CGPoint(x: x, y: bottom - g))
            p.addLine(to: CGPoint(x: x - t / 2, y: bottom - g - t / 2))
            p.addLine(to: CGPoint(x: x - t / 2, y: top + g + t / 2))
            p.closeSubpath()
            return p
        }

        let left = x0 + t / 2, right = x1 - t / 2
        let top = y0 + t / 2, bottom = y1 - t / 2
        return [
            ("a", horizontal(top)),
            ("b", vertical(right, top, ym)),
            ("c", vertical(right, ym, bottom)),
            ("d", horizontal(bottom)),
            ("e", vertical(left, ym, bottom)),
            ("f", vertical(left, top, ym)),
            ("g", horizontal(ym)),
        ]
    }
}
