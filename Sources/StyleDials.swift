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

/// 參考實體沙漏：上下木板加兩根側柱，玻璃是兩顆圓鼓的泡在細頸相接。
/// 上面的沙面中間凹下去（沙從正中間漏走），下面的沙堆成圓錐——
/// 平平的一條色塊看起來像進度條，不像沙。
private struct HourglassDial: View {
    let c: DialContext
    let size: CGSize

    /// 木框。深色模式調亮一點，不然會沉進背景
    private static let wood = Theme.dyn(0x8C6D52, 0xA88B6E)

    var body: some View {
        let w = size.width, h = size.height
        let glassW = w * 0.58
        let glassH = h * (c.isCompact ? 0.66 : 0.70)
        let box = CGRect(x: (w - glassW) / 2, y: h * 0.05, width: glassW, height: glassH)

        ZStack {
            Canvas { ctx, _ in
                let plate = glassH * 0.04
                let plateW = glassW * 1.26
                let plateX = box.midX - plateW / 2
                // 玻璃和木板之間留一點縫，玻璃才像是被夾住的
                let body = box.insetBy(dx: glassW * 0.04, dy: plate + glassH * 0.012)
                let glass = Self.glassPath(in: body)
                let top = body.minY, neck = body.midY, bottom = body.maxY
                let half = neck - top

                // 側柱畫在玻璃後面
                let post = max(2, w * 0.022)
                for x in [plateX + plateW * 0.07, plateX + plateW * 0.93 - post] {
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: box.minY, width: post, height: glassH),
                                  cornerRadius: post / 2),
                             with: .color(Self.wood.opacity(0.75)))
                }

                ctx.fill(glass, with: .color(Theme.fill.opacity(0.35)))

                let sand = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [c.tint.opacity(0.72), c.tint]),
                    startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))

                // 上泡越靠頸部越窄，剩一點點沙也還有高度；下泡底部寬，一開始堆得慢。
                // 用次方近似體積，比線性的高度更像真的沙。
                let topFill = pow(c.remaining, 0.6)
                let pileFill = 1 - pow(1 - c.progress, 0.6)
                let flowing = c.running && c.remaining > 0.001 && c.remaining < 0.999

                var peakY = bottom
                ctx.drawLayer { layer in
                    layer.clip(to: glass)

                    // 上面的沙＝剩下的時間，沙面中間凹下去
                    if c.remaining > 0.001 {
                        let level = neck - half * 0.82 * topFill
                        let dip = flowing ? min(half * 0.10, (neck - level) * 0.5) : 0
                        var p = Path()
                        p.move(to: CGPoint(x: body.minX, y: level))
                        p.addQuadCurve(to: CGPoint(x: body.maxX, y: level),
                                       control: CGPoint(x: body.midX, y: level + 2 * dip))
                        p.addLine(to: CGPoint(x: body.maxX, y: neck))
                        p.addLine(to: CGPoint(x: body.minX, y: neck))
                        p.closeSubpath()
                        layer.fill(p, with: sand)
                    }

                    // 下面的沙＝已經過去的時間，堆成圓錐
                    if c.progress > 0.001 {
                        let base = bottom - half * 0.82 * pileFill
                        let cone = min(half * 0.22, (bottom - base) + half * 0.08)
                        peakY = max(neck + 2, base - cone / 2)
                        let shoulder = base + cone / 2
                        var p = Path()
                        p.move(to: CGPoint(x: body.minX, y: bottom))
                        p.addLine(to: CGPoint(x: body.minX, y: shoulder))
                        p.addCurve(to: CGPoint(x: body.midX, y: peakY),
                                   control1: CGPoint(x: body.minX + body.width * 0.28, y: shoulder),
                                   control2: CGPoint(x: body.midX - body.width * 0.14, y: peakY))
                        p.addCurve(to: CGPoint(x: body.maxX, y: shoulder),
                                   control1: CGPoint(x: body.midX + body.width * 0.14, y: peakY),
                                   control2: CGPoint(x: body.maxX - body.width * 0.28, y: shoulder))
                        p.addLine(to: CGPoint(x: body.maxX, y: bottom))
                        p.closeSubpath()
                        layer.fill(p, with: sand)
                    }

                    // 頸部落下的細沙線，只在計時中出現；靜止不動（不做粒子）
                    if flowing {
                        layer.fill(Path(CGRect(x: body.midX - 0.6, y: neck,
                                               width: 1.2, height: max(0, peakY - neck))),
                                   with: .color(c.tint))
                    }
                }

                // 玻璃反光：兩顆泡左上各一道細白弧
                for (y0, y1) in [(top + half * 0.16, top + half * 0.60),
                                 (neck + half * 0.40, bottom - half * 0.16)] {
                    var hl = Path()
                    hl.move(to: CGPoint(x: body.minX + body.width * 0.17, y: y0))
                    hl.addQuadCurve(to: CGPoint(x: body.minX + body.width * 0.17, y: y1),
                                    control: CGPoint(x: body.minX + body.width * 0.05, y: (y0 + y1) / 2))
                    ctx.stroke(hl, with: .color(.white.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
                ctx.stroke(glass, with: .color(Theme.ink.opacity(0.28)), lineWidth: 1.2)

                // 上下木板
                for y in [box.minY, box.maxY - plate] {
                    ctx.fill(Path(roundedRect: CGRect(x: plateX, y: y, width: plateW, height: plate),
                                  cornerRadius: plate / 2),
                             with: .color(Self.wood))
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
            .position(x: w / 2, y: box.maxY + (h - box.maxY) / 2)
        }
        .frame(width: w, height: h)
    }

    /// 兩顆圓鼓的玻璃泡：口比肚子窄一點，肚子鼓出去再收進細頸。
    /// 先算右半邊，左半邊左右鏡像。
    static func glassPath(in r: CGRect) -> Path {
        let half = r.width / 2
        let q = r.midY - r.minY
        let lip = 0.76                // 泡口寬度（相對於最寬處）
        let neck = 0.10               // 頸部寬度
        func pt(_ sx: Double, _ y: CGFloat) -> CGPoint { CGPoint(x: r.midX + half * sx, y: y) }

        var p = Path()
        p.move(to: pt(-lip, r.minY))
        p.addLine(to: pt(lip, r.minY))
        for s in [1.0, -1.0] {
            // s = 1：右邊由上往下；s = -1：左邊由下往上
            let y0 = s > 0 ? r.minY : r.maxY
            let y1 = s > 0 ? r.maxY : r.minY
            let d = s > 0 ? q : -q       // 往頸部的方向
            p.addCurve(to: pt(s, y0 + d * 0.40),
                       control1: pt(s * (lip + (1 - lip) * 0.7), y0),
                       control2: pt(s, y0 + d * 0.12))
            p.addCurve(to: pt(s * neck, r.midY),
                       control1: pt(s, y0 + d * 0.78),
                       control2: pt(s * neck, r.midY - d * 0.22))
            p.addCurve(to: pt(s, y1 - d * 0.40),
                       control1: pt(s * neck, r.midY + d * 0.22),
                       control2: pt(s, y1 - d * 0.78))
            p.addCurve(to: pt(s * lip, y1),
                       control1: pt(s, y1 - d * 0.12),
                       control2: pt(s * (lip + (1 - lip) * 0.7), y1))
            if s > 0 { p.addLine(to: pt(-lip, r.maxY)) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 月相

/// 參考機械錶的月相盤：深藍星空、帶暖色的月面，暗面留一點地球反照，
/// 月海（深色斑塊）讓它看起來是月亮而不是一顆白圓。亮面＝剩下的時間，由滿月缺成新月。
private struct MoonDial: View {
    let c: DialContext
    let size: CGSize

    /// 星星位置（相對座標），刻意避開月亮。第三個值是半徑，大於 1 的畫成十字星芒。
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.20, 0.22, 1.3), (0.78, 0.18, 0.9), (0.85, 0.42, 1.1), (0.14, 0.50, 0.8),
        (0.30, 0.10, 0.7), (0.24, 0.72, 0.9), (0.80, 0.68, 0.7), (0.53, 0.07, 0.8),
        (0.68, 0.30, 0.6), (0.10, 0.34, 0.6),
    ]
    /// 月海：中心（相對月心，以半徑為單位）和半徑
    private static let maria: [(CGFloat, CGFloat, CGFloat)] = [
        (-0.28, -0.22, 0.24), (0.14, -0.30, 0.17), (0.28, 0.06, 0.21),
        (-0.08, 0.20, 0.15), (0.04, 0.48, 0.10), (-0.40, 0.36, 0.08),
    ]

    private static let starColor = Color(hex: 0xF3E6C2)
    private static let moonLight = Color(hex: 0xFBF6E6)
    private static let moonEdge = Color(hex: 0xE4D8B8)
    private static let moonDark = Color(hex: 0x252C4D)

    var body: some View {
        let w = size.width, h = size.height
        // 月亮和光暈放上半部、數字放下半部，兩者不能疊到
        let r = w * 0.22
        let center = CGPoint(x: w / 2, y: h * 0.36)

        ZStack {
            Canvas { ctx, _ in
                // 天頂稍亮。半透明疊在底色上，提醒時的底色閃光才透得過來
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.07), .clear]),
                                               center: CGPoint(x: w / 2, y: h * 0.2),
                                               startRadius: 0, endRadius: w * 0.7))

                for (x, y, s) in Self.stars {
                    let p = CGPoint(x: w * x, y: h * y)
                    ctx.fill(Path(ellipseIn: circleRect(p, s)), with: .color(Self.starColor.opacity(0.7)))
                    if s > 1 {
                        var cross = Path()
                        cross.move(to: CGPoint(x: p.x - s * 3, y: p.y))
                        cross.addLine(to: CGPoint(x: p.x + s * 3, y: p.y))
                        cross.move(to: CGPoint(x: p.x, y: p.y - s * 3))
                        cross.addLine(to: CGPoint(x: p.x, y: p.y + s * 3))
                        ctx.stroke(cross, with: .color(Self.starColor.opacity(0.35)), lineWidth: 0.6)
                    }
                }

                // 光暈跟著亮面大小變淡
                ctx.fill(Path(ellipseIn: circleRect(center, r * 1.7)),
                         with: .radialGradient(Gradient(colors: [Self.moonLight.opacity(0.03 + 0.13 * c.remaining),
                                                                 .clear]),
                                               center: center, startRadius: r * 0.9, endRadius: r * 1.7))

                // 暗面：地球反照，看得出整顆月亮的輪廓
                let disk = Path(ellipseIn: circleRect(center, r))
                ctx.fill(disk, with: .color(Self.moonDark))

                let lit = Self.litPath(center: center, r: r, fraction: c.remaining)
                ctx.fill(lit, with: .radialGradient(Gradient(colors: [Self.moonLight, Self.moonEdge]),
                                                    center: CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.3),
                                                    startRadius: 0, endRadius: r * 1.4))
                // 月光只帶一點階段色，太多會變成粉紅色的月亮
                ctx.fill(lit, with: .color(c.tint.opacity(0.10)))

                // 月海：亮面上是淡灰斑，暗面上是更暗的斑，一次畫完
                ctx.drawLayer { layer in
                    layer.clip(to: disk)
                    var m = Path()
                    for (dx, dy, rr) in Self.maria {
                        m.addEllipse(in: circleRect(CGPoint(x: center.x + dx * r, y: center.y + dy * r), rr * r))
                    }
                    layer.fill(m, with: .color(.black.opacity(0.09)))
                }
                ctx.stroke(disk, with: .color(.white.opacity(0.08)), lineWidth: 1)
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

/// 一道正弦波的水面，底下填滿。
///
/// 波的相位由秒數決定：每秒跟著倒數挪一點，暫停時就停住。
/// 不做連續的波浪動畫——這個視窗浮在全螢幕 App 上，一直重畫的代價太高。
private struct WaveShape: Shape {
    /// 水位（0…1，從底部算起）
    let level: Double
    let amplitude: CGFloat
    /// 波長，相對於寬度
    let wavelength: CGFloat
    let phase: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard level > 0.002 else { return p }
        let y0 = rect.maxY - rect.height * CGFloat(level)
        let steps = 48
        for i in 0...steps {
            let x = rect.width * CGFloat(i) / CGFloat(steps)
            let angle = 2 * Double.pi * Double(x / (wavelength * rect.width)) + phase
            let y = y0 + amplitude * CGFloat(sin(angle))
            let pt = CGPoint(x: rect.minX + x, y: y)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 參考液體進度球：前後兩道錯開的波疊出水的深度，淹到的數字反白。
/// 水位＝剩下的時間。
private struct WaterDial: View {
    let c: DialContext
    let size: CGSize

    /// 靜止的氣泡（相對座標、半徑），只畫在水面以下的
    private static let bubbles: [(CGFloat, CGFloat, CGFloat)] = [
        (0.30, 0.82, 2.2), (0.36, 0.72, 1.4), (0.68, 0.86, 1.8), (0.74, 0.62, 1.2), (0.58, 0.93, 1.3),
    ]

    var body: some View {
        let w = size.width, h = size.height
        // 水快滿或快乾時把波壓平，不然波峰會頂出圓外或在底部露出一條縫
        let damp = CGFloat(min(1, c.remaining * 8, (1 - c.remaining) * 8))
        let amp = (c.isCompact ? 3.5 : 4.5) * damp
        let phase = Double(c.elapsedInMinute) * 0.9
        let front = WaveShape(level: c.remaining, amplitude: amp, wavelength: 0.95, phase: phase)
        let back = WaveShape(level: c.remaining, amplitude: amp * 0.8, wavelength: 0.8, phase: -phase * 0.7 + 2)

        ZStack {
            Canvas { ctx, _ in
                // 左側刻度線，像量杯
                for f in [0.25, 0.5, 0.75] {
                    ctx.fill(Path(CGRect(x: w * 0.13, y: h * f - 0.5, width: w * 0.08, height: 1)),
                             with: .color(Theme.muted.opacity(0.45)))
                }
            }
            back.fill(c.tint.opacity(0.28))
            front.fill(LinearGradient(colors: [c.tint.opacity(0.72), c.tint.opacity(0.95)],
                                      startPoint: .top, endPoint: .bottom))
            Canvas { ctx, _ in
                let surface = h * (1 - c.remaining) + amp + 4
                var p = Path()
                for (x, y, r) in Self.bubbles where h * y - r > surface {
                    p.addEllipse(in: circleRect(CGPoint(x: w * x, y: h * y), r))
                }
                ctx.stroke(p, with: .color(.white.opacity(0.45)), lineWidth: 0.8)
            }

            // 同一組字畫兩次：水上是墨色，水下的部分用波形遮罩換成白色
            readout(ink: Theme.ink, accent: c.tint)
                .frame(width: w, height: h)
            readout(ink: .white, accent: .white.opacity(0.9))
                .frame(width: w, height: h)
                .mask { front }
        }
        .frame(width: w, height: h)
    }

    private func readout(ink: Color, accent: Color) -> some View {
        VStack(spacing: c.isCompact ? 5 : 7) {
            if !c.isCompact {
                Text(c.eyebrow).font(Theme.eyebrow).tracking(2).foregroundStyle(accent)
            }
            Text(c.clock)
                .font(Theme.clock(c.isCompact ? 30 : 42))
                .foregroundStyle(ink)
            StatusLine(c: c, dot: c.isCompact ? 4 : 5, color: accent)
        }
        // offset 要在 frame／mask 之前：字往上挪，遮罩的水面不跟著挪
        .offset(y: c.hovering ? -10 : 0)
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

/// 12 個小點，放在環的內側當作時刻的暗示，一條路徑畫完
private struct HourDots: Shape {
    let radius: CGFloat
    let dot: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            p.addEllipse(in: circleRect(CGPoint(x: rect.midX + radius * CGFloat(sin(a)),
                                                y: rect.midY - radius * CGFloat(cos(a))), dot / 2))
        }
        return p
    }
}

/// 參考 Apple Watch 的活動圓環：同色系的淡底軌、圓頭的粗弧，
/// 弧的末端一顆帶陰影的圓鈕標出「現在在這裡」。數字只留分鐘大字，秒數縮小退後。
private struct MinimalDial: View {
    let c: DialContext
    let size: CGSize

    var body: some View {
        let d = c.isCompact ? size.width - 24 : size.width - 10
        let line: CGFloat = c.isCompact ? 5 : 6
        // 弧的末端：從正上方順時針，剩下多少就走到哪
        let a = 2 * Double.pi * c.remaining
        let knob = CGPoint(x: d / 2 * CGFloat(sin(a)), y: -d / 2 * CGFloat(cos(a)))

        ZStack {
            Circle().stroke(c.tint.opacity(0.13), lineWidth: line).frame(width: d, height: d)
            HourDots(radius: d / 2 - line - (c.isCompact ? 5 : 7), dot: c.isCompact ? 1.6 : 2)
                .fill(Theme.muted.opacity(0.35))
                .frame(width: d, height: d)
            // 剩下多少：從正上方順時針，隨時間往回縮
            Circle()
                .trim(from: 0, to: c.remaining)
                .stroke(c.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: d, height: d)
            if c.remaining > 0.002 {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: line * 0.55, height: line * 0.55)
                    .frame(width: line * 1.5, height: line * 1.5)
                    .background(Circle().fill(c.tint))
                    .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
                    .offset(x: knob.x, y: knob.y)
            }

            VStack(spacing: c.isCompact ? 2 : 6) {
                if !c.isCompact {
                    Text(c.eyebrow).font(Theme.eyebrow).tracking(2).foregroundStyle(c.tint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(c.minutes)
                        .font(.system(size: c.isCompact ? 38 : 58, weight: .thin, design: .rounded)
                            .monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    Text(":" + c.seconds)
                        .font(.system(size: c.isCompact ? 15 : 20, weight: .regular, design: .rounded)
                            .monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                if !c.isCompact {
                    StatusLine(c: c)
                } else if c.alerting {
                    Text(c.eyebrow).font(Theme.eyebrow).tracking(1.5).foregroundStyle(c.tint)
                }
            }
            .frame(maxWidth: d - 2 * line - 20)
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
