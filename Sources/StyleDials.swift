import SwiftUI

/// 畫錶盤需要的所有東西，打包成一個值。
///
/// 從 model 取一次就好，每個風格的 renderer 都只看這個——這樣設定頁的縮圖可以餵一個
/// 固定的範例進去，完全不訂閱 model，就不會在設定頁開著時十個錶盤每秒跟著倒數重畫。
struct DialContext {
    /// 已經走了多少（0…1）
    var progress: Double
    /// 「MM:SS」
    var clock: String
    var phase: Phase
    var alerting: Bool
    var alertFinished: Phase?
    var breath: Bool
    var roundInCycle: Int
    var rounds: Int
    var isCompact: Bool
    var hovering: Bool = false
    var running: Bool = false

    var tint: Color { Theme.accent(phase) }
    /// 剩多少（0…1）。沙漏、水位、月相都表達這個，跟倒數數字同一個方向。
    var remaining: Double { min(1, max(0, 1 - progress)) }
    /// 專注最長可設 120 分，時間會是「120:00」，不能用 prefix(2) 切
    var minutes: String { String(clock.split(separator: ":").first ?? "00") }
    var seconds: String { String(clock.split(separator: ":").last ?? "00") }
    /// 這一分鐘已經過了幾秒（倒數的秒數反過來），給秒針順時針走
    var elapsedInMinute: Int { (60 - (Int(seconds) ?? 0)) % 60 }
    /// 提醒中顯示「休息時間」／「該專注了」，平常顯示階段名稱
    var eyebrow: String { alerting ? alertEyebrow(for: alertFinished) : phase.title }

    @MainActor
    init(model: PomodoroModel, prefs: Prefs, isCompact: Bool, hovering: Bool = false) {
        progress = model.progress
        clock = model.clock
        phase = model.phase
        alerting = model.alerting
        alertFinished = model.alertFinished
        breath = model.breath
        roundInCycle = model.roundInCycle
        rounds = prefs.roundsPerLong
        running = model.running
        self.isCompact = isCompact
        self.hovering = hovering
    }

    init(progress: Double, clock: String, phase: Phase, alerting: Bool = false,
         alertFinished: Phase? = nil, breath: Bool = false,
         roundInCycle: Int = 1, rounds: Int = 4, isCompact: Bool, hovering: Bool = false,
         running: Bool = true) {
        self.progress = progress
        self.clock = clock
        self.phase = phase
        self.alerting = alerting
        self.alertFinished = alertFinished
        self.breath = breath
        self.roundInCycle = roundInCycle
        self.rounds = rounds
        self.isCompact = isCompact
        self.hovering = hovering
        self.running = running
    }

    /// 設定頁縮圖用的固定範例
    static func sample(isCompact: Bool = true) -> DialContext {
        DialContext(progress: 0.35, clock: "16:15", phase: .work, isCompact: isCompact)
    }
}

/// 一個 view 畫所有風格。十個 case 固定，一個 switch 最好讀，不需要 protocol。
///
/// 每個 renderer 都必須遵守 README「效能」那一節的規則：用 Shape／Path／Canvas 畫、
/// 不綁定 progress 的隱式動畫、只吃 1 Hz 的更新。任何動畫都要會停——
/// 這個視窗浮在全螢幕 App 上面，每次重畫都要重新合成。
struct StyledDial: View {
    let style: DialStyle
    let context: DialContext
    /// renderer 可用的面板尺寸
    let size: CGSize

    var body: some View {
        switch style {
        case .classic:   ClassicDial(c: context, size: size)
        case .pixel:     PixelDial(c: context, size: size)
        case .flip:      FlipDial(c: context, size: size)
        case .lcd:       LCDDial(c: context, size: size)
        case .hourglass: HourglassDial(c: context, size: size)
        case .moon:      MoonDial(c: context, size: size)
        case .water:     WaterDial(c: context, size: size)
        case .bauhaus:   BauhausDial(c: context, size: size)
        case .minimal:   MinimalDial(c: context, size: size)
        case .station:   StationDial(c: context, size: size)
        }
    }
}

/// 設定頁的縮圖：把該風格縮小模式的實際樣子等比縮進格子。
///
/// 用固定的範例 context，不訂閱 model——設定頁開著時，十個縮圖才不會每秒跟著倒數重畫。
/// 先以原尺寸排版再 scaleEffect，而不是直接用小尺寸畫：renderer 是照縮小模式調的，
/// 直接縮小尺寸會讓字級和間距跑掉，縮圖就不再是「實際的樣子」。
struct StyleThumbnail: View {
    let style: DialStyle
    let box: CGSize

    var body: some View {
        let panel = CGSize(width: style.compactSize.width - 2 * DialStyle.inset,
                           height: style.compactSize.height - 2 * DialStyle.inset)
        let scale = min(box.width / panel.width, box.height / panel.height)
        ZStack {
            style.silhouette
                .fill(style.surface)
                .overlay(style.silhouette.stroke(style.outline, lineWidth: 1))
            StyledDial(style: style, context: .sample(), size: panel)
                .clipShape(style.silhouette)
        }
        .frame(width: panel.width, height: panel.height)
        .scaleEffect(scale)
        .frame(width: panel.width * scale, height: panel.height * scale)
    }
}

/// 提醒時沿著輪廓的呼吸外框。原本的 PulseRing 只會畫圓，
/// 長方形的風格外面套一個圓圈會很怪，所以改成吃風格的輪廓。
///
/// `breath` 是外部傳入的純輸入（0…1），只內縮不放大——外層有 .clipped()。
struct PulseOutline: View {
    let shape: AnyShape
    let tint: Color
    let breath: Double

    var body: some View {
        shape
            .stroke(tint.opacity(0.18 + 0.38 * breath), lineWidth: 2 + 4 * breath)
            .scaleEffect(1 - 0.05 * breath)
    }
}

// MARK: - 經典刻度

/// 原本的錶盤，原封不動搬過來。也是其他風格的對照組。
private struct ClassicDial: View {
    let c: DialContext
    let size: CGSize

    var body: some View {
        if c.isCompact {
            ZStack {
                Dial(progress: c.progress, tint: c.tint, diameter: size.width - 18)
                VStack(spacing: 5) {
                    Text(c.clock)
                        .font(Theme.clock(30))
                        .foregroundStyle(Theme.ink)
                    if c.alerting {
                        Text(c.eyebrow)
                            .font(Theme.eyebrow)
                            .tracking(1.5)
                            .foregroundStyle(c.tint)
                    } else {
                        RoundDots(done: c.roundInCycle, total: c.rounds, tint: c.tint, dot: 4)
                    }
                }
                .offset(y: c.hovering ? -10 : 0)
            }
        } else {
            ZStack {
                Dial(progress: c.progress, tint: c.tint, diameter: size.width)
                VStack(spacing: 7) {
                    Text(c.eyebrow)
                        .font(Theme.eyebrow)
                        .tracking(2)
                        .foregroundStyle(c.tint)
                    Text(c.clock)
                        .font(Theme.clock(46))
                        .foregroundStyle(Theme.ink)
                    if c.alerting {
                        Text("點一下停止提醒")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.muted)
                    } else {
                        RoundDots(done: c.roundInCycle, total: c.rounds, tint: c.tint)
                    }
                }
            }
        }
    }
}

// MARK: - 共用小零件

/// 提醒中顯示「休息時間」／「該專注了」，平常顯示輪數圓點
private struct StatusLine: View {
    let c: DialContext
    var dot: CGFloat = 4
    var color: Color? = nil

    var body: some View {
        if c.alerting {
            Text(c.eyebrow)
                .font(Theme.eyebrow)
                .tracking(1.5)
                .foregroundStyle(color ?? c.tint)
        } else {
            RoundDots(done: c.roundInCycle, total: c.rounds, tint: color ?? c.tint, dot: dot)
        }
    }
}

/// 固定寬度的字格。系統字型有 .monospacedDigit()，但 Futura、Helvetica 這類字型
/// 不一定有等寬數字，倒數時整排字會左右跳。每個字放進固定寬的格子裡。
private struct CellText: View {
    let text: String
    let font: Font
    let cell: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(font)
                    .foregroundStyle(color)
                    .frame(width: ch == ":" ? cell * 0.42 : cell)
            }
        }
    }
}

private func circleRect(_ center: CGPoint, _ r: CGFloat) -> CGRect {
    CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
}

/// 從正上方順時針的扇形，fraction 0…1
private func pie(center: CGPoint, radius: CGFloat, fraction: Double) -> Path {
    var p = Path()
    guard fraction > 0 else { return p }
    p.move(to: center)
    let steps = max(2, Int(96 * fraction))
    for i in 0...steps {
        let a = -Double.pi / 2 + 2 * .pi * fraction * Double(i) / Double(steps)
        p.addLine(to: CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
    }
    p.closeSubpath()
    return p
}

// MARK: - 像素 8-bit

/// 掌機的四階綠。全部畫在一個 Canvas 裡——一個像素一個 view 的話會是幾百個 view。
private struct PixelDial: View {
    let c: DialContext
    let size: CGSize

    private static let darkest = Color(hex: 0x0F380F)
    private static let dark = Color(hex: 0x306230)
    private static let light = Color(hex: 0x8BAC0F)

    /// 16×16 格子的外圈剛好 60 格，對應 60 格刻度。從正上方順時針排。
    private static let ring: [(Int, Int)] = {
        var cells: [(Int, Int)] = []
        for x in 8...15 { cells.append((x, 0)) }
        for y in 1...15 { cells.append((15, y)) }
        for x in stride(from: 14, through: 0, by: -1) { cells.append((x, 15)) }
        for y in stride(from: 14, through: 1, by: -1) { cells.append((0, y)) }
        for x in 0...7 { cells.append((x, 0)) }
        return cells
    }()

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let w = sz.width, h = sz.height
                let margin = w * 0.07
                let cell = (w - 2 * margin) / 16
                let block = cell * 0.74

                // 外圈：剩下的亮、走過的暗
                let elapsed = Int((c.progress * 60).rounded())
                var lit = Path(), dim = Path()
                for (i, (gx, gy)) in Self.ring.enumerated() {
                    let r = CGRect(x: margin + CGFloat(gx) * cell + (cell - block) / 2,
                                   y: margin + CGFloat(gy) * cell + (cell - block) / 2,
                                   width: block, height: block)
                    if i < elapsed { dim.addRect(r) } else { lit.addRect(r) }
                }
                ctx.fill(dim, with: .color(Self.light))
                ctx.fill(lit, with: .color(Self.darkest))

                // 數字：放得進內框的最大「整數」像素，像素才不會糊
                let inner = w - 2 * margin - 3 * cell
                let cols = PixelGlyphs.width(of: c.clock)
                let px = max(1, floor(min(inner / CGFloat(cols), cell * 1.35)))
                let textW = CGFloat(cols) * px
                let lift: CGFloat = c.hovering ? -cell * 1.2 : 0
                let ty = floor(h * 0.40 - 2.5 * px + lift)
                PixelGlyphs.draw(c.clock, in: ctx,
                                 at: CGPoint(x: floor((w - textW) / 2), y: ty),
                                 px: px, color: Self.darkest)

                // 階段小圖：專注是番茄、休息是咖啡杯（固定配色的風格不改色，用圖示區分）
                let ipx = max(1, floor(cell * 0.55))
                PixelGlyphs.drawIcon(c.phase.isBreak ? PixelGlyphs.cup : PixelGlyphs.tomato,
                                     in: ctx,
                                     at: CGPoint(x: floor((w - 7 * ipx) / 2),
                                                 y: floor(ty + 5 * px + px * 1.4)),
                                     px: ipx, dark: Self.darkest, mid: Self.dark)
            }
            if c.alerting {
                Text(c.eyebrow)
                    .font(.system(size: max(9, size.width * 0.07), weight: .heavy))
                    .foregroundStyle(Self.darkest)
                    .offset(y: size.height * 0.29)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - 翻頁鐘

/// 翻頁：舊的一頁往下翻走、新的一頁從上面翻下來
private struct FlipRotation: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0),
                              anchor: .center, perspective: 0.45)
            .opacity(abs(angle) >= 89 ? 0 : 1)
    }
}

private extension AnyTransition {
    static var flipDown: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipRotation(angle: 90), identity: FlipRotation(angle: 0)),
            removal: .modifier(active: FlipRotation(angle: -90), identity: FlipRotation(angle: 0)))
    }
}

private struct FlipCard: View {
    let text: String
    let width: CGFloat
    let height: CGFloat
    /// 只有分鐘那張會翻
    let flips: Bool

    private static let card = Color(hex: 0x2C2C2E)
    private static let cardTop = Color(hex: 0x38383A)
    private static let ink = Color(hex: 0xF2F2F2)

    var body: some View {
        ZStack {
            face(text)
                // 分鐘變的時候換 id 觸發翻頁；秒數用固定 id，就地換字不翻
                .id(flips ? text : "static")
                .transition(flips ? .flipDown : .identity)
        }
        .frame(width: width, height: height)
        // 這個動畫綁在「一分鐘才變一次」的值上，翻完就停。
        // 跟當初那個綁在每秒都變的 progress、永遠停不下來的隱式動畫是兩回事。
        .animation(flips ? .easeInOut(duration: 0.35) : nil, value: text)
    }

    private func face(_ t: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.12, style: .continuous)
        return ZStack {
            shape.fill(Self.card)
            VStack(spacing: 0) {
                Self.cardTop.frame(height: height / 2)
                Color.clear
            }
            Text(t)
                .font(.system(size: height * 0.72, weight: .bold).monospacedDigit())
                .foregroundStyle(Self.ink)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(.horizontal, width * 0.06)
            // 中間的轉軸縫
            Color.black.opacity(0.75).frame(height: max(1.5, height * 0.018))
            HStack {
                Capsule().fill(Color.black.opacity(0.6)).frame(width: width * 0.035, height: height * 0.16)
                Spacer()
                Capsule().fill(Color.black.opacity(0.6)).frame(width: width * 0.035, height: height * 0.16)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
    }
}

private struct FlipDial: View {
    let c: DialContext
    let size: CGSize

    private static let ink = Color(hex: 0xF2F2F2)

    var body: some View {
        let w = size.width, h = size.height
        let pad = w * 0.06
        let gap = w * 0.07
        let cardW = (w - 2 * pad - gap) / 2
        let cardH = h * 0.56
        let cardsTop = c.isCompact ? h * 0.10 : h * 0.20
        let trackY = cardsTop + cardH + h * (c.isCompact ? 0.10 : 0.09)
        let trackW = w - 2 * pad

        ZStack {
            if !c.isCompact {
                Text(c.eyebrow)
                    .font(Theme.eyebrow).tracking(2)
                    .foregroundStyle(Self.ink.opacity(0.75))
                    .position(x: w / 2, y: h * 0.10)
            }

            FlipCard(text: c.minutes, width: cardW, height: cardH, flips: true)
                .position(x: pad + cardW / 2, y: cardsTop + cardH / 2)
            FlipCard(text: c.seconds, width: cardW, height: cardH, flips: false)
                .position(x: w - pad - cardW / 2, y: cardsTop + cardH / 2)
            VStack(spacing: cardH * 0.22) {
                Circle().fill(Self.ink.opacity(0.55)).frame(width: 4, height: 4)
                Circle().fill(Self.ink.opacity(0.55)).frame(width: 4, height: 4)
            }
            .position(x: w / 2, y: cardsTop + cardH / 2)

            // 下方細線：剩下多少
            ZStack(alignment: .leading) {
                Capsule().fill(Self.ink.opacity(0.14))
                Capsule().fill(Self.ink.opacity(0.6)).frame(width: trackW * c.remaining)
            }
            .frame(width: trackW, height: 3)
            .position(x: w / 2, y: trackY)

            Group {
                if c.alerting {
                    Text(c.eyebrow).foregroundStyle(Self.ink)
                } else if c.phase.isBreak {
                    // 固定配色的風格不改色，休息改用小標記
                    Text("BREAK").foregroundStyle(Self.ink.opacity(0.6))
                } else if !c.isCompact {
                    RoundDots(done: c.roundInCycle, total: c.rounds, tint: Self.ink.opacity(0.8), dot: 4)
                }
            }
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(1.5)
            .position(x: w / 2, y: min(h - 7, trackY + (c.isCompact ? 11 : 12)))
        }
        .frame(width: w, height: h)
    }
}

// MARK: - LCD 電子錶

/// 七段數字自己畫。沒亮的段淡淡留著——那是 LCD 的靈魂。
private struct LCDDial: View {
    let c: DialContext
    let size: CGSize

    private static let ink = Color(hex: 0x1A1F16)
    private static let screen = Color(hex: 0xB9C596)

    var body: some View {
        let w = size.width, h = size.height
        let inset: CGFloat = c.isCompact ? 8 : 12
        let scr = CGRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset)

        Canvas { ctx, _ in
            ctx.fill(Path(roundedRect: scr, cornerRadius: 8), with: .color(Self.screen))
            ctx.stroke(Path(roundedRect: scr, cornerRadius: 8), with: .color(Self.ink.opacity(0.2)), lineWidth: 1)

            // 印在液晶上的小字：目前這一段亮、其他的淡淡留著
            let legendFont = Font.system(size: c.isCompact ? 8.5 : 10, weight: .semibold)
            let legends: [(String, Bool)] = [("專注", c.phase == .work),
                                             ("短休", c.phase == .shortBreak),
                                             ("長休", c.phase == .longBreak)]
            for (i, (label, on)) in legends.enumerated() {
                ctx.draw(Text(label).font(legendFont).foregroundColor(Self.ink.opacity(on ? 0.9 : 0.13)),
                         at: CGPoint(x: scr.minX + 16 + CGFloat(i) * (c.isCompact ? 26 : 32),
                                     y: scr.minY + (c.isCompact ? 9 : 12)))
            }
            if c.alerting {
                ctx.draw(Text(c.eyebrow).font(legendFont).foregroundColor(Self.ink),
                         at: CGPoint(x: scr.maxX - (c.isCompact ? 26 : 32), y: scr.minY + (c.isCompact ? 9 : 12)))
            }

            // 七段數字
            let dh = scr.height * (c.isCompact ? 0.48 : 0.50)
            let dw = dh * 0.52
            let t = dw * 0.19
            let gap = dw * 0.24
            let colonW = dw * 0.36
            let chars = Array(c.clock)
            let total = chars.reduce(CGFloat(0)) { $0 + ($1 == ":" ? colonW : dw) } + gap * CGFloat(chars.count - 1)
            var x = scr.midX - total / 2
            let top = scr.minY + (c.isCompact ? 18 : 24)
            // 微微右斜，電子錶的數字是斜的
            let shear = CGAffineTransform(translationX: 0, y: -(top + dh))
                .concatenating(CGAffineTransform(a: 1, b: 0, c: -0.1, d: 1, tx: 0, ty: 0))
                .concatenating(CGAffineTransform(translationX: 0, y: top + dh))
            var ghost = Path(), lit = Path()
            // 冒號：跑動時一秒亮一秒暗；暫停時常亮
            let colonOn = !c.running || (Int(c.seconds) ?? 0) % 2 == 0
            for ch in chars {
                if ch == ":" {
                    let s = t * 0.9
                    for fy in [0.32, 0.68] {
                        let r = CGRect(x: x + (colonW - s) / 2, y: top + dh * fy - s / 2, width: s, height: s)
                        if colonOn { lit.addRect(r) } else { ghost.addRect(r) }
                    }
                    x += colonW + gap
                    continue
                }
                let on = PixelGlyphs.segments[ch] ?? []
                for (name, seg) in PixelGlyphs.segmentPaths(in: CGRect(x: x, y: top, width: dw, height: dh), thickness: t) {
                    if on.contains(name) { lit.addPath(seg) } else { ghost.addPath(seg) }
                }
                x += dw + gap
            }
            ctx.fill(ghost.applying(shear), with: .color(Self.ink.opacity(0.07)))
            ctx.fill(lit.applying(shear), with: .color(Self.ink))

            // 底下 20 格的分段條：剩下多少
            let n = 20
            let barW = scr.width * 0.78
            let cellW = barW / CGFloat(n)
            let barY = scr.maxY - (c.isCompact ? 10 : 13)
            let litCount = c.remaining > 0 ? Int(ceil(c.remaining * Double(n))) : 0
            var on = Path(), off = Path()
            for i in 0..<n {
                let r = CGRect(x: scr.midX - barW / 2 + CGFloat(i) * cellW + 1, y: barY - 2,
                               width: cellW - 2, height: 4)
                if i < litCount { on.addRect(r) } else { off.addRect(r) }
            }
            ctx.fill(off, with: .color(Self.ink.opacity(0.08)))
            ctx.fill(on, with: .color(Self.ink.opacity(0.85)))
        }
        .frame(width: w, height: h)
    }
}

// MARK: - 沙漏

private struct HourglassDial: View {
    let c: DialContext
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let glassW = w * 0.64
        let glassH = h * (c.isCompact ? 0.64 : 0.68)
        let glass = CGRect(x: (w - glassW) / 2, y: h * 0.06, width: glassW, height: glassH)

        ZStack {
            Canvas { ctx, _ in
                let cap = glassH * 0.045
                let body = glass.insetBy(dx: 0, dy: cap)
                let path = Self.glassPath(in: body)
                ctx.fill(path, with: .color(Theme.fill.opacity(0.45)))

                // 沙只存在玻璃裡面
                ctx.drawLayer { layer in
                    layer.clip(to: path)
                    let top = body.minY, neck = body.midY, bottom = body.maxY
                    // 上面的沙＝剩下的時間
                    let topLevel = neck - (neck - top) * 0.86 * c.remaining
                    if c.remaining > 0.001 {
                        layer.fill(Path(CGRect(x: body.minX, y: topLevel,
                                               width: body.width, height: neck - topLevel)),
                                   with: .color(c.tint))
                    }
                    // 下面堆起來的沙＝已經過去的時間，頂端微微隆起
                    let botLevel = bottom - (bottom - neck) * 0.86 * c.progress
                    if c.progress > 0.001 {
                        var mound = Path()
                        mound.move(to: CGPoint(x: body.minX, y: bottom))
                        mound.addLine(to: CGPoint(x: body.minX, y: botLevel + 3))
                        mound.addQuadCurve(to: CGPoint(x: body.maxX, y: botLevel + 3),
                                           control: CGPoint(x: body.midX, y: botLevel - 4))
                        mound.addLine(to: CGPoint(x: body.maxX, y: bottom))
                        mound.closeSubpath()
                        layer.fill(mound, with: .color(c.tint))
                    }
                    // 頸部的細沙線，靜止不動（不做粒子）
                    if c.running && c.remaining > 0.001 && c.remaining < 0.999 {
                        layer.fill(Path(CGRect(x: body.midX - 0.6, y: neck,
                                               width: 1.2, height: max(0, botLevel - neck))),
                                   with: .color(c.tint))
                    }
                }
                ctx.stroke(path, with: .color(Theme.ink.opacity(0.35)), lineWidth: 1.5)

                // 上下木蓋
                for y in [glass.minY, glass.maxY - cap] {
                    ctx.fill(Path(roundedRect: CGRect(x: glass.minX - glassW * 0.08, y: y,
                                                      width: glassW * 1.16, height: cap),
                                  cornerRadius: cap / 2),
                             with: .color(Theme.muted.opacity(0.6)))
                }
            }

            VStack(spacing: 3) {
                Text(c.clock)
                    .font(Theme.clock(c.isCompact ? 22 : 26))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                StatusLine(c: c, dot: 3.5)
            }
            .position(x: w / 2, y: glass.maxY + (h - glass.maxY) / 2)
        }
        .frame(width: w, height: h)
    }

    /// 兩個玻璃泡在頸部相接
    static func glassPath(in r: CGRect) -> Path {
        let neck = r.width * 0.07
        let ym = r.midY
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX + neck, y: ym),
                   control1: CGPoint(x: r.maxX, y: r.minY + (ym - r.minY) * 0.55),
                   control2: CGPoint(x: r.midX + neck, y: ym - (ym - r.minY) * 0.25))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                   control1: CGPoint(x: r.midX + neck, y: ym + (r.maxY - ym) * 0.25),
                   control2: CGPoint(x: r.maxX, y: r.maxY - (r.maxY - ym) * 0.55))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX - neck, y: ym),
                   control1: CGPoint(x: r.minX, y: r.maxY - (r.maxY - ym) * 0.55),
                   control2: CGPoint(x: r.midX - neck, y: ym + (r.maxY - ym) * 0.25))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY),
                   control1: CGPoint(x: r.midX - neck, y: ym - (ym - r.minY) * 0.25),
                   control2: CGPoint(x: r.minX, y: r.minY + (ym - r.minY) * 0.55))
        p.closeSubpath()
        return p
    }
}

// MARK: - 月相

/// 由滿月慢慢缺成新月：亮面＝剩下的時間。
private struct MoonDial: View {
    let c: DialContext
    let size: CGSize

    /// 星星位置（相對座標），刻意避開月亮
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.20, 0.22, 1.1), (0.78, 0.18, 0.9), (0.85, 0.42, 1.2), (0.14, 0.50, 0.8),
        (0.30, 0.10, 0.7), (0.24, 0.72, 0.9), (0.80, 0.68, 0.7), (0.53, 0.07, 0.8),
    ]

    var body: some View {
        let w = size.width, h = size.height
        // 月亮和光暈放上半部、數字放下半部，兩者不能疊到
        let r = w * 0.22
        let center = CGPoint(x: w / 2, y: h * 0.36)

        ZStack {
            Canvas { ctx, _ in
                for (x, y, s) in Self.stars {
                    ctx.fill(Path(ellipseIn: circleRect(CGPoint(x: w * x, y: h * y), s)),
                             with: .color(.white.opacity(0.55)))
                }
                ctx.fill(Path(ellipseIn: circleRect(center, r * 1.22)), with: .color(.white.opacity(0.05)))
                ctx.fill(Path(ellipseIn: circleRect(center, r)), with: .color(Color(hex: 0x2A3150)))
                let lit = Self.litPath(center: center, r: r, fraction: c.remaining)
                ctx.fill(lit, with: .color(Color(hex: 0xF4F1E8)))
                // 月光只帶一點階段色，太多會變成粉紅色的月亮
                ctx.fill(lit, with: .color(c.tint.opacity(0.12)))
            }
            VStack(spacing: 4) {
                Text(c.clock)
                    .font(Theme.clock(c.isCompact ? 24 : 30))
                    .foregroundStyle(.white.opacity(0.92))
                StatusLine(c: c, dot: 3.5)
            }
            .position(x: w / 2, y: h * 0.79)
        }
        .frame(width: w, height: h)
    }

    /// 亮面：左邊的月緣半圓 ＋ 明暗交界的半橢圓。
    /// 虧月亮面在左；fraction 1 是滿月、0.5 是下弦月、0 是新月。
    static func litPath(center: CGPoint, r: CGFloat, fraction f: Double) -> Path {
        var p = Path()
        guard f > 0.002 else { return p }
        let k = 2 * f - 1
        let n = 48
        p.move(to: CGPoint(x: center.x, y: center.y - r))
        // 月緣：上 → 左 → 下
        for i in 1...n {
            let a = -Double.pi / 2 - Double.pi * Double(i) / Double(n)
            p.addLine(to: CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a)))
        }
        // 明暗交界：下 → 上，中間在 x = center + k·r
        for i in 1...n {
            let a = Double.pi / 2 - Double.pi * Double(i) / Double(n)
            p.addLine(to: CGPoint(x: center.x + k * r * cos(a), y: center.y + r * sin(a)))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 水位

/// 水位＝剩下的時間。水面是一段固定的淺弧，不做波浪。
private struct WaterDial: View {
    let c: DialContext
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let level = h * (1 - c.remaining)

        ZStack {
            Canvas { ctx, _ in
                // 左側刻度線，像量杯
                for f in [0.25, 0.5, 0.75] {
                    ctx.fill(Path(CGRect(x: w * 0.13, y: h * f - 0.5, width: w * 0.08, height: 1)),
                             with: .color(Theme.muted.opacity(0.45)))
                }
                guard c.remaining > 0.002 else { return }
                var surface = Path()
                surface.move(to: CGPoint(x: 0, y: level))
                surface.addQuadCurve(to: CGPoint(x: w, y: level), control: CGPoint(x: w / 2, y: level + 5))
                var water = surface
                water.addLine(to: CGPoint(x: w, y: h))
                water.addLine(to: CGPoint(x: 0, y: h))
                water.closeSubpath()
                ctx.fill(water, with: .color(c.tint.opacity(0.26)))
                ctx.stroke(surface, with: .color(c.tint.opacity(0.65)), lineWidth: 1.5)
            }
            VStack(spacing: c.isCompact ? 5 : 7) {
                if !c.isCompact {
                    Text(c.eyebrow).font(Theme.eyebrow).tracking(2).foregroundStyle(c.tint)
                }
                Text(c.clock)
                    .font(Theme.clock(c.isCompact ? 30 : 42))
                    .foregroundStyle(Theme.ink)
                StatusLine(c: c, dot: c.isCompact ? 4 : 5)
            }
            .offset(y: c.hovering ? -10 : 0)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - 包浩斯

/// 紅圓裡的扇形＝剩下的時間；藍方、黃條、黑線是構成。
private struct BauhausDial: View {
    let c: DialContext
    let size: CGSize

    private static let red = Color(hex: 0xD0342C)
    private static let yellow = Color(hex: 0xF2B51C)
    private static let blue = Color(hex: 0x1F4E9C)
    private static let ink = Color(hex: 0x1A1A1A)

    var body: some View {
        let w = size.width, h = size.height

        ZStack {
            Canvas { ctx, _ in
                let cc = CGPoint(x: w * 0.36, y: h * 0.36)
                let r = w * 0.24
                ctx.fill(pie(center: cc, radius: r, fraction: c.remaining), with: .color(Self.red))
                ctx.stroke(Path(ellipseIn: circleRect(cc, r)), with: .color(Self.ink),
                           lineWidth: max(1.2, w * 0.01))
                ctx.fill(Path(CGRect(x: w * 0.66, y: h * 0.12, width: w * 0.20, height: w * 0.20)),
                         with: .color(Self.blue))
                ctx.fill(Path(CGRect(x: w * 0.66, y: h * 0.40, width: w * 0.24, height: h * 0.07)),
                         with: .color(Self.yellow))
                ctx.fill(Path(CGRect(x: w * 0.10, y: h * 0.66, width: w * 0.80, height: max(2, h * 0.022))),
                         with: .color(Self.ink))
            }
            HStack(spacing: w * 0.03) {
                CellText(text: c.clock, font: .custom("Futura-Bold", size: w * 0.16),
                         cell: w * 0.10, color: Self.ink)
                // 固定配色的風格不改色，休息時多一顆藍點
                if c.phase.isBreak {
                    Circle().fill(Self.blue).frame(width: w * 0.05, height: w * 0.05)
                }
            }
            .frame(width: w * 0.80, alignment: .leading)
            .position(x: w / 2, y: h * 0.79)

            // 靠右、塞在黃條和黑線之間的空位。放左邊會壓到紅圓。
            if c.alerting {
                Text(c.eyebrow)
                    .font(.custom("Futura-Bold", size: max(9, w * 0.065)))
                    .foregroundStyle(Self.red)
                    .frame(width: w * 0.80, alignment: .trailing)
                    .position(x: w / 2, y: h * 0.57)
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - 極簡環

private struct MinimalDial: View {
    let c: DialContext
    let size: CGSize

    var body: some View {
        let d = c.isCompact ? size.width - 22 : size.width - 6
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 1.5).frame(width: d, height: d)
            // 剩下多少：從正上方順時針，隨時間往回縮
            Circle()
                .trim(from: 0, to: c.remaining)
                .stroke(c.tint, style: StrokeStyle(lineWidth: c.isCompact ? 3 : 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: d, height: d)
            VStack(spacing: c.isCompact ? 4 : 8) {
                if !c.isCompact {
                    Text(c.eyebrow).font(Theme.eyebrow).tracking(2).foregroundStyle(c.tint)
                }
                Text(c.clock)
                    .font(.system(size: c.isCompact ? 32 : 50, weight: .light, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(Theme.ink)
                if !c.isCompact {
                    StatusLine(c: c)
                } else if c.alerting {
                    Text(c.eyebrow).font(Theme.eyebrow).tracking(1.5).foregroundStyle(c.tint)
                }
            }
            .offset(y: c.hovering ? -8 : 0)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - 車站鐘

/// 60 根長方形刻度，12 根粗的
private struct StationTicks: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<60 {
            let major = i % 5 == 0
            let len = major ? radius * 0.22 : radius * 0.07
            let wid = major ? radius * 0.07 : radius * 0.022
            let a = Double(i) / 60 * 2 * .pi
            let mid = radius - len / 2
            p.addPath(Path(CGRect(x: -wid / 2, y: -len / 2, width: wid, height: len))
                .applying(CGAffineTransform(rotationAngle: a))
                .applying(CGAffineTransform(translationX: c.x + sin(a) * mid, y: c.y - cos(a) * mid)))
        }
        return p
    }
}

/// 指針。角度直接烤進路徑、不用 rotationEffect：Shape 的路徑不可插值，
/// 切換階段那 0.28 秒的動畫才不會讓指針轉一大圈。
private struct StationHand: Shape {
    let angle: Double
    let length: CGFloat
    let width: CGFloat
    let tail: CGFloat
    /// 秒針尾端的配重圓；0 表示沒有
    var weight: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var p = Path(CGRect(x: -width / 2, y: -length, width: width, height: length + tail))
        if weight > 0 {
            p.addEllipse(in: CGRect(x: -weight / 2, y: tail - weight / 2, width: weight, height: weight))
        }
        return p
            .applying(CGAffineTransform(rotationAngle: angle * .pi / 180))
            .applying(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    }
}

/// 白錶面、黑刻度、紅秒針。
/// 刻意不叫「瑞士鐵路鐘」、秒針也不做尖端紅色圓盤——那是 SBB 受保護的設計。
private struct StationDial: View {
    let c: DialContext
    let size: CGSize

    private static let ink = Color(hex: 0x141414)
    private static let red = Color(hex: 0xD62718)

    var body: some View {
        let r = size.width / 2 - (c.isCompact ? 5 : 3)
        ZStack {
            StationTicks(radius: r).fill(Self.ink)

            Group {
                if c.alerting {
                    Text(c.eyebrow).foregroundStyle(Self.red)
                } else if c.phase.isBreak {
                    // 固定配色的風格不改色，休息改用小字
                    Text("休息").foregroundStyle(Self.ink.opacity(0.7))
                }
            }
            .font(.custom("Helvetica-Bold", size: max(9, r * 0.13)))
            // 放在數字下面。提醒時時間是整分、兩根指針都指向正上方，放上面一定被蓋住。
            .offset(y: r * 0.61)

            CellText(text: c.clock, font: .custom("Helvetica-Bold", size: r * 0.19),
                     cell: r * 0.125, color: Self.ink)
                .offset(y: r * 0.40)

            // 分針：一整圈是這一段的長度
            StationHand(angle: c.progress * 360, length: r * 0.74, width: r * 0.065, tail: r * 0.14)
                .fill(Self.ink)
            // 秒針：每秒跳一格
            StationHand(angle: Double(c.elapsedInMinute) * 6, length: r * 0.86,
                        width: max(1.2, r * 0.022), tail: r * 0.26, weight: r * 0.09)
                .fill(Self.red)
            Circle().fill(Self.ink).frame(width: r * 0.06, height: r * 0.06)
        }
        .frame(width: size.width, height: size.height)
    }
}
