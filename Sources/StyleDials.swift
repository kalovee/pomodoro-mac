import SwiftUI
import AppKit

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
    /// 錶盤上方的小字（階段名稱、模式名稱或提醒文字），由 model 決定
    var eyebrow: String
    /// 碼錶往上數：秒針要順著秒數走，而不是倒過來
    var countsUp: Bool = false
    /// 只有番茄鐘有輪數，另外兩個模式不顯示輪數圓點
    var showsRounds: Bool = true
    /// 每開始新的一段 +1，沙漏靠它翻面
    var segmentID: Int = 0
    /// 任務名稱：黑膠唱片把它當歌名印在標籤上
    var task: String = ""
    var mode: TimerMode = .pomodoro
    /// 黑膠用會轉的 Core Animation 圖層（完整模式、沒開減少動態效果）；否則用靜態圖
    var usesLiveRecord: Bool = false
    /// 黑膠此刻要不要轉：上面那個條件再加上正在計時
    var spins: Bool = false

    var tint: Color { Theme.accent(phase) }
    /// 剩多少（0…1）。沙漏、水位、月相都表達這個，跟倒數數字同一個方向。
    var remaining: Double { min(1, max(0, 1 - progress)) }
    /// 專注最長可設 120 分，時間會是「120:00」，不能用 prefix(2) 切
    var minutes: String { String(clock.split(separator: ":").first ?? "00") }
    var seconds: String { String(clock.split(separator: ":").last ?? "00") }
    /// 這一分鐘已經過了幾秒（倒數的秒數反過來），給秒針順時針走
    var elapsedInMinute: Int {
        let s = Int(seconds) ?? 0
        return countsUp ? s : (60 - s) % 60
    }

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
        eyebrow = model.eyebrow
        countsUp = model.mode == .stopwatch
        showsRounds = model.mode == .pomodoro
        segmentID = model.segmentID
        task = model.task
        mode = model.mode
        // 縮小模式不轉：讀書時眼角有東西一直轉會分心。系統開了減少動態效果也不轉
        usesLiveRecord = !isCompact && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        spins = usesLiveRecord && model.running
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
        eyebrow = alerting ? alertEyebrow(for: alertFinished) : phase.title
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
        case .candle:    CandleDial(c: context, size: size)
        case .vinyl:     VinylDial(c: context, size: size)
        case .nixie:     NixieDial(c: context, size: size)
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

/// 刻度內側的淡色扇形＝還沒走到的時間。
///
/// 參考 Time Timer 那片會隨時間消失的紅色圓盤：刻度要數才讀得出來，
/// 一片面積一眼就知道還剩多少。顏色壓得很淡，數字壓在上面還是清楚。
private struct TimerWash: View {
    let progress: Double
    let tint: Color
    let diameter: CGFloat

    var body: some View {
        Canvas { ctx, sz in
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = diameter / 2 * 0.86
            ctx.fill(sector(center: center, radius: r, from: progress), with: .color(tint.opacity(0.09)))
            ctx.stroke(Path(ellipseIn: circleRect(center, r)),
                       with: .color(Theme.hairline.opacity(0.8)), lineWidth: 0.75)
            // 扇形的起邊：從圓心拉到目前位置的一條細線，像 Time Timer 圓盤的邊緣
            if progress > 0.001 && progress < 0.999 {
                let a = -Double.pi / 2 + 2 * .pi * progress
                var edge = Path()
                edge.move(to: center)
                edge.addLine(to: CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a))))
                ctx.stroke(edge, with: .color(tint.opacity(0.35)), lineWidth: 1)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 60 格刻度加上 Time Timer 式的剩餘扇形。也是其他風格的對照組。
private struct ClassicDial: View {
    let c: DialContext
    let size: CGSize

    var body: some View {
        if c.isCompact {
            ZStack {
                TimerWash(progress: c.progress, tint: c.tint, diameter: size.width - 18)
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
                        StatusLine(c: c, dot: 4)
                    }
                }
                .offset(y: c.hovering ? -10 : 0)
            }
        } else {
            ZStack {
                TimerWash(progress: c.progress, tint: c.tint, diameter: size.width)
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
                        StatusLine(c: c, dot: 5)
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
        } else if c.showsRounds {
            RoundDots(done: c.roundInCycle, total: c.rounds, tint: color ?? c.tint, dot: dot)
        } else {
            // 沒有輪數的模式改顯示模式名稱，位置和高度跟圓點差不多
            Text(c.eyebrow)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle((color ?? c.tint).opacity(0.8))
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
    /// 冒號的格寬（相對於數字格）。粗字體的冒號比較胖，要給寬一點
    var colonRatio: CGFloat = 0.42

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(font)
                    .foregroundStyle(color)
                    .frame(width: ch == ":" ? cell * colonRatio : cell)
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
        p.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a))))
    }
    p.closeSubpath()
    return p
}

/// 從 from 走到整圈的扇形（從正上方順時針量），也就是「還沒走到」的那一塊
private func sector(center: CGPoint, radius: CGFloat, from start: Double) -> Path {
    var p = Path()
    let fraction = 1 - min(1, max(0, start))
    guard fraction > 0.001 else { return p }
    p.move(to: center)
    let steps = max(2, Int(96 * fraction))
    for i in 0...steps {
        let a = -Double.pi / 2 + 2 * .pi * (start + fraction * Double(i) / Double(steps))
        p.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a))))
    }
    p.closeSubpath()
    return p
}

// MARK: - 像素 8-bit

/// 掌機的四階綠。全部畫在一個 Canvas 裡——一個像素一個 view 的話會是幾百個 view。
///
/// 參考早期掌機的液晶：整片螢幕有淡淡的點陣格線，數字下面一條 RPG 式的 HP 條，
/// 階段圖示站在 HP 條左邊。外圈 60 格保留，跟經典刻度同一套讀法。
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

                // 液晶的點陣格線：半格一條，淡到只看得出質感
                var grid = Path()
                let pitch = cell / 2
                var gx = margin
                while gx <= w - margin + 0.1 {
                    grid.addRect(CGRect(x: gx, y: margin, width: 0.5, height: h - 2 * margin))
                    gx += pitch
                }
                var gy = margin
                while gy <= h - margin + 0.1 {
                    grid.addRect(CGRect(x: margin, y: gy, width: w - 2 * margin, height: 0.5))
                    gy += pitch
                }
                ctx.fill(grid, with: .color(Self.darkest.opacity(0.06)))

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

                // 數字下面一排：階段圖示＋HP 條。
                // 專注是番茄、休息是咖啡杯（固定配色的風格不改色，用圖示區分）
                let ipx = max(1, floor(cell * 0.5))
                let rowY = floor(ty + 5 * px + px * 1.4)
                let barW = floor(inner * 0.52)
                let barH = 6 * ipx
                let rowW = 7 * ipx + 2 * ipx + barW
                let rowX = floor((w - rowW) / 2)
                PixelGlyphs.drawIcon(c.phase.isBreak ? PixelGlyphs.cup : PixelGlyphs.tomato,
                                     in: ctx, at: CGPoint(x: rowX, y: rowY),
                                     px: ipx, dark: Self.darkest, mid: Self.dark)

                // HP 條：外框、底、10 格，剩多少亮多少
                let bar = CGRect(x: rowX + 9 * ipx, y: rowY, width: barW, height: barH)
                ctx.fill(Path(bar), with: .color(Self.darkest))
                ctx.fill(Path(bar.insetBy(dx: ipx, dy: ipx)), with: .color(Self.light))
                let slots = 10
                let hpLit = c.remaining > 0 ? Int(ceil(c.remaining * Double(slots))) : 0
                let slotW = (barW - 3 * ipx) / CGFloat(slots)
                var hp = Path()
                for i in 0..<hpLit {
                    hp.addRect(CGRect(x: floor(bar.minX + 2 * ipx + CGFloat(i) * slotW), y: bar.minY + 2 * ipx,
                                      width: max(1, floor(slotW) - ipx), height: barH - 4 * ipx))
                }
                ctx.fill(hp, with: .color(Self.dark))
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
    /// 卡片右下角的小字，像實體翻頁鐘印在卡片上的「分」「秒」
    var label: String? = nil

    /// 上半比下半亮一點，像光從上面打下來；各自再帶一點漸層
    private static let topHi = Color(hex: 0x3C3C3F)
    private static let topLo = Color(hex: 0x323235)
    private static let botHi = Color(hex: 0x2A2A2D)
    private static let botLo = Color(hex: 0x222225)
    private static let ink = Color(hex: 0xF2F2F2)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.12, style: .continuous)
        ZStack {
            // 卡片底下的厚度：往下錯開一點的深色卡，比 .shadow 便宜而且不會糊
            shape.fill(Color.black.opacity(0.55))
                .offset(y: height * 0.035)
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
        let hinge = max(1.5, height * 0.02)
        return ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [Self.topHi, Self.topLo], startPoint: .top, endPoint: .bottom)
                    .frame(height: height / 2)
                LinearGradient(colors: [Self.botHi, Self.botLo], startPoint: .top, endPoint: .bottom)
            }
            Text(t)
                .font(.system(size: height * 0.72, weight: .bold).monospacedDigit())
                .foregroundStyle(Self.ink)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(.horizontal, width * 0.06)
            // 中間的轉軸縫：一條黑線，下緣一道細亮邊，才看得出是兩片
            VStack(spacing: 0) {
                Color.black.opacity(0.8).frame(height: hinge)
                Color.white.opacity(0.08).frame(height: 0.75)
            }
            if let label {
                Text(label)
                    .font(.system(size: max(7, height * 0.11), weight: .semibold))
                    .foregroundStyle(Self.ink.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, width * 0.08)
                    .padding(.bottom, height * 0.07)
            }
            HStack {
                Capsule().fill(Color.black.opacity(0.6)).frame(width: width * 0.035, height: height * 0.16)
                Spacer()
                Capsule().fill(Color.black.opacity(0.6)).frame(width: width * 0.035, height: height * 0.16)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 0.75))
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

            FlipCard(text: c.minutes, width: cardW, height: cardH, flips: true, label: "分")
                .position(x: pad + cardW / 2, y: cardsTop + cardH / 2)
            FlipCard(text: c.seconds, width: cardW, height: cardH, flips: false, label: "秒")
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
///
/// 參考經典數位錶（刻意不用任何品牌字樣）：錶殼兩側各兩顆按鍵、液晶上緣印著模式標籤、
/// 右上角一組小七段顯示輪數、底下的分段條兩端加括號，像電池格。
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
            // 錶殼兩側的按鍵
            var keys = Path()
            for fy in [0.32, 0.68] {
                for x in [CGFloat(0.5), w - 4] {
                    keys.addRoundedRect(in: CGRect(x: x, y: h * fy - 6, width: 3.5, height: 12),
                                        cornerSize: CGSize(width: 1.5, height: 1.5))
                }
            }
            ctx.fill(keys, with: .color(Self.ink.opacity(0.22)))

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
            } else {
                // 右上角的小七段：完成輪數／一輪幾個，沒亮的段一樣淡淡留著
                let sh: CGFloat = c.isCompact ? 8 : 10
                let sw = sh * 0.55
                let st = max(1, sw * 0.2)
                let sgap = sw * 0.35
                let slash = sw * 0.8
                let left = String(c.roundInCycle), right = String(c.rounds)
                let count = left.count + right.count
                let smallW = CGFloat(count) * sw + CGFloat(count - 1) * sgap + slash + sgap
                var sx = scr.maxX - 9 - smallW
                let sy = scr.minY + (c.isCompact ? 9 : 12) - sh / 2
                var sLit = Path(), sGhost = Path()
                func small(_ text: String) {
                    for ch in text {
                        let on = PixelGlyphs.segments[ch] ?? []
                        for (name, seg) in PixelGlyphs.segmentPaths(in: CGRect(x: sx, y: sy, width: sw, height: sh),
                                                                    thickness: st) {
                            if on.contains(name) { sLit.addPath(seg) } else { sGhost.addPath(seg) }
                        }
                        sx += sw + sgap
                    }
                }
                small(left)
                var cut = Path()
                cut.move(to: CGPoint(x: sx + slash, y: sy))
                cut.addLine(to: CGPoint(x: sx, y: sy + sh))
                sLit.addPath(cut.strokedPath(StrokeStyle(lineWidth: st)))
                sx += slash + sgap
                small(right)
                ctx.fill(sGhost, with: .color(Self.ink.opacity(0.07)))
                ctx.fill(sLit, with: .color(Self.ink.opacity(0.85)))
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

            // 分段條兩端的括號
            var brackets = Path()
            for side in [-1.0, 1.0] {
                let bx = scr.midX + CGFloat(side) * (barW / 2 + 3)
                brackets.addRect(CGRect(x: bx - 0.6, y: barY - 4, width: 1.2, height: 8))
                let tipX = side < 0 ? bx : bx - 2.5
                brackets.addRect(CGRect(x: tipX, y: barY - 4, width: 2.5, height: 1.2))
                brackets.addRect(CGRect(x: tipX, y: barY + 2.8, width: 2.5, height: 1.2))
            }
            ctx.fill(brackets, with: .color(Self.ink.opacity(0.6)))
        }
        .frame(width: w, height: h)
    }
}

// MARK: - 沙漏

/// 沙漏翻面：新的一段開始時，滿沙的沙漏從倒放轉正
private struct SpinFlip: ViewModifier {
    let angle: Double
    let anchor: UnitPoint
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle), anchor: anchor)
    }
}

/// 寫實沙漏：車床木框、有厚度的玻璃、帶顆粒的真沙。
///
/// 沙用固定的沙色，不跟階段變色——紅色的沙看起來像液體。階段交給底下的輪數圓點。
/// 所有顆粒、反光的位置都是固定的，每秒只跟著剩餘時間重畫一次，沒有粒子動畫。
private struct HourglassDial: View {
    let c: DialContext
    let size: CGSize

    private static let woodLight = Theme.dyn(0xA67C58, 0xB8906B)
    private static let woodDark = Theme.dyn(0x6B4930, 0x7D5A3E)
    private static let sandLight = Color(hex: 0xEBD09C)
    private static let sandDeep = Color(hex: 0xC99A5B)
    private static let sandShade = Color(hex: 0x8F6638)

    /// 沙粒：單位座標與大小，用固定種子的亂數產生一次
    private static let grains: [(CGFloat, CGFloat, CGFloat, Bool)] = {
        var seed: UInt64 = 0x5EED
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        return (0..<220).map { _ in (next(), next(), 0.5 + next() * 0.6, next() > 0.45) }
    }()

    var body: some View {
        let w = size.width, h = size.height
        let glassW = w * 0.58
        let glassH = h * (c.isCompact ? 0.66 : 0.70)
        let box = CGRect(x: (w - glassW) / 2, y: h * 0.05, width: glassW, height: glassH)

        ZStack {
            Canvas { ctx, _ in draw(in: &ctx, box: box, w: w) }
                // 每開始新的一段換一個 id：新的沙漏（上面滿沙）從倒放轉正，就像把沙漏翻過來
                .id(c.segmentID)
                .transition(.asymmetric(
                    insertion: .modifier(active: SpinFlip(angle: -180, anchor: UnitPoint(x: 0.5, y: box.midY / h)),
                                         identity: SpinFlip(angle: 0, anchor: UnitPoint(x: 0.5, y: box.midY / h))),
                    removal: .identity))

            VStack(spacing: c.isCompact ? 1 : 3) {
                Text(c.clock)
                    .font(Theme.clock(c.isCompact ? 22 : 26))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                StatusLine(c: c, dot: 3.5)
            }
            // 縮小模式提醒時，閃動的外框畫在輪廓裡面；文字要離底邊遠一點，不然「休息時間」會壓在外框上
            .position(x: w / 2, y: box.maxY + (h - box.maxY) / 2 + (c.isCompact ? -3 : 2))
        }
        .frame(width: w, height: h)
        // 動畫只綁在 segmentID：一段開始時轉一次，轉完就停
        .animation(.easeInOut(duration: 0.75), value: c.segmentID)
    }

    private func draw(in ctx: inout GraphicsContext, box: CGRect, w: CGFloat) {
        let glassW = box.width, glassH = box.height
        let plate = glassH * 0.045
        let plateW = glassW * 1.26
        let plateX = box.midX - plateW / 2
        let body = box.insetBy(dx: glassW * 0.05, dy: plate + glassH * 0.014)
        let glass = Self.glassPath(in: body)
        let top = body.minY, neck = body.midY, bottom = body.maxY
        let half = neck - top

        // 桌面上的影子
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 2.5))
            l.fill(Path(ellipseIn: CGRect(x: plateX - 2, y: box.maxY - plate * 0.2,
                                          width: plateW + 4, height: plate * 1.4)),
                   with: .color(.black.opacity(0.18)))
        }

        // 車床木柱：橫向亮暗漸層表現圓柱，上下各一顆珠狀凸環
        let post = max(2.4, w * 0.026)
        for cx in [plateX + plateW * 0.085, plateX + plateW * 0.915] {
            let turned = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Self.woodDark, Self.woodLight, Self.woodDark]),
                startPoint: CGPoint(x: cx - post, y: 0), endPoint: CGPoint(x: cx + post, y: 0))
            ctx.fill(Path(CGRect(x: cx - post / 2, y: box.minY, width: post, height: glassH)), with: turned)
            for by in [box.minY + plate * 1.6, box.maxY - plate * 1.6] {
                ctx.fill(Path(ellipseIn: CGRect(x: cx - post * 0.95, y: by - post * 0.55,
                                                width: post * 1.9, height: post * 1.1)), with: turned)
            }
        }

        // 玻璃本身：淡淡的底色，左亮右暗
        ctx.fill(glass, with: .color(Theme.fill.opacity(0.28)))
        ctx.fill(glass, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.30), .white.opacity(0.04), .black.opacity(0.05)]),
            startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0)))

        let sand = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Self.sandLight, Self.sandDeep]),
            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))

        // 上泡越靠頸部越窄，下泡底部寬：用次方近似體積，比線性高度更像真的沙
        let topFill = pow(c.remaining, 0.6)
        let pileFill = 1 - pow(1 - c.progress, 0.6)
        let flowing = c.running && c.remaining > 0.001 && c.remaining < 0.999

        var topSand = Path()
        var pile = Path()
        var peakY = bottom

        if c.remaining > 0.001 {
            // 上面的沙＝剩下的時間。漏的時候沙面是往頸部凹下去的漏斗
            let level = neck - half * 0.84 * topFill
            let dip = flowing ? min(half * 0.16, (neck - level) * 0.7) : 0
            topSand.move(to: CGPoint(x: body.minX, y: level))
            topSand.addQuadCurve(to: CGPoint(x: body.midX, y: level + dip),
                                 control: CGPoint(x: body.midX - body.width * 0.22, y: level))
            topSand.addQuadCurve(to: CGPoint(x: body.maxX, y: level),
                                 control: CGPoint(x: body.midX + body.width * 0.22, y: level))
            topSand.addLine(to: CGPoint(x: body.maxX, y: neck + 1))
            topSand.addLine(to: CGPoint(x: body.minX, y: neck + 1))
            topSand.closeSubpath()
        }

        if c.progress > 0.001 {
            // 下面的沙＝已經過去的時間，堆成接近安息角的圓錐，頂端略圓
            let base = bottom - half * 0.84 * pileFill
            let cone = min(half * 0.30, (bottom - base) + half * 0.10)
            peakY = max(neck + 3, base - cone * 0.6)
            let shoulder = base + cone * 0.4
            pile.move(to: CGPoint(x: body.minX, y: bottom))
            pile.addLine(to: CGPoint(x: body.minX, y: shoulder))
            pile.addQuadCurve(to: CGPoint(x: body.midX - 2.5, y: peakY + 1.2),
                              control: CGPoint(x: body.midX - body.width * 0.24, y: peakY + cone * 0.38))
            pile.addQuadCurve(to: CGPoint(x: body.midX + 2.5, y: peakY + 1.2),
                              control: CGPoint(x: body.midX, y: peakY - 0.8))
            pile.addQuadCurve(to: CGPoint(x: body.maxX, y: shoulder),
                              control: CGPoint(x: body.midX + body.width * 0.24, y: peakY + cone * 0.38))
            pile.addLine(to: CGPoint(x: body.maxX, y: bottom))
            pile.closeSubpath()
        }

        ctx.drawLayer { layer in
            layer.clip(to: glass)
            for p in [topSand, pile] where !p.isEmpty {
                layer.fill(p, with: sand)
                // 沙堆左邊受光、右邊背光
                layer.fill(p, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.10)]),
                    startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0)))
                // 顆粒：深淺兩種細點，只畫在沙裡
                layer.drawLayer { g in
                    g.clip(to: p)
                    var dark = Path(), light = Path()
                    for (gx, gy, r, isDark) in Self.grains {
                        let pt = CGRect(x: body.minX + gx * body.width, y: top + gy * body.height,
                                        width: r, height: r)
                        if isDark { dark.addEllipse(in: pt) } else { light.addEllipse(in: pt) }
                    }
                    g.fill(dark, with: .color(Self.sandShade.opacity(0.45)))
                    g.fill(light, with: .color(.white.opacity(0.45)))
                }
            }
            // 上層沙面的受光邊
            if !topSand.isEmpty {
                layer.stroke(topSand, with: .color(.white.opacity(0.25)), lineWidth: 0.6)
            }

            // 沙流：一條細線加幾顆沿線的沙粒，落點濺起幾顆
            if flowing {
                layer.fill(Path(CGRect(x: body.midX - 0.55, y: neck, width: 1.1, height: max(0, peakY - neck))),
                           with: .color(Self.sandDeep))
                var bits = Path()
                let span = max(0, peakY - neck)
                for (i, dx) in [-0.9, 0.8, -0.6, 1.0, -1.1].enumerated() {
                    let y = neck + span * CGFloat(i + 1) / 6
                    bits.addEllipse(in: CGRect(x: body.midX + CGFloat(dx) - 0.5, y: y, width: 1, height: 1))
                }
                for (dx, dy) in [(-3.0, -1.2), (2.6, -0.8), (-1.6, -2.2), (3.4, -2.0)] {
                    bits.addEllipse(in: CGRect(x: body.midX + CGFloat(dx), y: peakY + CGFloat(dy), width: 1.1, height: 1.1))
                }
                layer.fill(bits, with: .color(Self.sandDeep))
            }
        }

        // 玻璃的反光：左邊一長條、右邊一短條、左上一個亮點
        for (y0, y1) in [(top + half * 0.14, top + half * 0.66), (neck + half * 0.34, bottom - half * 0.14)] {
            var hl = Path()
            hl.move(to: CGPoint(x: body.minX + body.width * 0.15, y: y0))
            hl.addQuadCurve(to: CGPoint(x: body.minX + body.width * 0.16, y: y1),
                            control: CGPoint(x: body.minX + body.width * 0.03, y: (y0 + y1) / 2))
            ctx.stroke(hl, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            var rim = Path()
            rim.move(to: CGPoint(x: body.maxX - body.width * 0.12, y: y0 + (y1 - y0) * 0.25))
            rim.addQuadCurve(to: CGPoint(x: body.maxX - body.width * 0.13, y: y0 + (y1 - y0) * 0.7),
                             control: CGPoint(x: body.maxX - body.width * 0.04, y: (y0 + y1) / 2))
            ctx.stroke(rim, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: circleRect(CGPoint(x: body.minX + body.width * 0.26, y: top + half * 0.12), 1.3)),
                 with: .color(.white.opacity(0.8)))

        // 玻璃輪廓：外面一圈深的、疊一條細亮線，看起來有厚度
        ctx.stroke(glass, with: .color(Theme.ink.opacity(0.30)), lineWidth: 1.5)
        ctx.stroke(glass, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
        // 頸部的細環
        ctx.fill(Path(roundedRect: CGRect(x: body.midX - body.width * 0.09, y: neck - 1.2,
                                          width: body.width * 0.18, height: 2.4), cornerRadius: 1.2),
                 with: .color(Theme.ink.opacity(0.18)))

        // 上下木板：上亮下暗，中間一條木紋，上緣一道受光
        for (i, y) in [box.minY, box.maxY - plate].enumerated() {
            let r = CGRect(x: plateX, y: y, width: plateW, height: plate)
            ctx.fill(Path(roundedRect: r, cornerRadius: plate * 0.35),
                     with: .linearGradient(Gradient(colors: [Self.woodLight, Self.woodDark]),
                                           startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            ctx.fill(Path(CGRect(x: r.minX + plate * 0.4, y: r.minY + 0.6, width: r.width - plate * 0.8, height: 0.7)),
                     with: .color(.white.opacity(0.28)))
            var grain = Path()
            grain.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY + 0.3))
            grain.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.15, y: r.midY - 0.2),
                               control: CGPoint(x: r.midX, y: r.midY + (i == 0 ? 0.9 : -0.9)))
            ctx.stroke(grain, with: .color(Self.woodDark.opacity(0.45)), lineWidth: 0.5)
        }
    }

    /// 兩顆圓鼓的玻璃泡：口比肚子窄一點，肚子鼓出去再收進細頸。
    /// 先算右半邊，左半邊左右鏡像。
    static func glassPath(in r: CGRect) -> Path {
        let half = r.width / 2
        let q = r.midY - r.minY
        let lip = 0.74                // 泡口寬度（相對於最寬處）
        let neck = 0.07               // 頸部寬度
        func pt(_ sx: Double, _ y: CGFloat) -> CGPoint { CGPoint(x: r.midX + half * CGFloat(sx), y: y) }

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
                       control1: pt(s, y0 + d * 0.80),
                       control2: pt(s * neck, r.midY - d * 0.20))
            p.addCurve(to: pt(s, y1 - d * 0.40),
                       control1: pt(s * neck, r.midY + d * 0.20),
                       control2: pt(s, y1 - d * 0.80))
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

/// 固定種子的亂數：星星與隕石坑的位置每次都一樣，不會每秒重排
private struct SeededRandom {
    private var seed: UInt64
    init(_ seed: UInt64) { self.seed = seed }
    mutating func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 10_000) / 10_000
    }
}

/// 寫實的月亮：依真實位置排的月海、帶明暗的隕石坑、第谷與哥白尼的射紋，
/// 柔和的明暗交界，以及暗面淡淡的地球反照。夜空參考機械錶的砂金石月相盤。
///
/// 虧月：**亮面在左，光從左邊來**。亮面＝剩下的時間，由滿月缺成新月。
private struct MoonDial: View {
    let c: DialContext
    let size: CGSize

    /// 星星：相對座標、半徑、亮度
    private static let stars: [(CGFloat, CGFloat, CGFloat, Double)] = {
        var rng = SeededRandom(0x57A25)
        var out: [(CGFloat, CGFloat, CGFloat, Double)] = []
        while out.count < 40 {
            let x = rng.next(), y = rng.next() * 0.66
            // 避開月亮本體和它的光暈
            let dx = x - 0.5, dy = y - 0.36
            if dx * dx + dy * dy < 0.09 { continue }
            out.append((x, y, 0.35 + rng.next() * 0.9, 0.3 + Double(rng.next()) * 0.6))
        }
        return out
    }()

    /// 月海：中心（相對月心，以半徑為單位，北在上）與兩軸半徑。依真實月面位置排
    private static let maria: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (-0.56, 0.02, 0.28, 0.44),   // 風暴洋
        (-0.44, 0.26, 0.20, 0.18),   // 風暴洋南側
        (-0.28, -0.38, 0.25, 0.21),  // 雨海
        (-0.04, -0.68, 0.40, 0.08),  // 冷海
        (0.18, -0.38, 0.15, 0.14),   // 澄海
        (0.32, -0.08, 0.20, 0.16),   // 靜海
        (0.66, -0.30, 0.12, 0.10),   // 危海
        (0.56, 0.16, 0.12, 0.17),    // 豐富海
        (0.36, 0.30, 0.09, 0.09),    // 酒海
        (-0.18, 0.38, 0.18, 0.13),   // 雲海
        (-0.48, 0.42, 0.09, 0.09),   // 濕海
        (0.00, -0.12, 0.10, 0.08),   // 汽海
        (-0.24, -0.04, 0.12, 0.09),  // 島海
    ]

    /// 小隕石坑：相對月心的位置與半徑
    private static let craters: [(CGFloat, CGFloat, CGFloat)] = {
        var rng = SeededRandom(0xC7A7E)
        var out: [(CGFloat, CGFloat, CGFloat)] = []
        while out.count < 40 {
            let x = rng.next() * 1.8 - 0.9, y = rng.next() * 1.8 - 0.9
            if x * x + y * y > 0.78 { continue }
            out.append((x, y, 0.015 + rng.next() * 0.045))
        }
        return out
    }()

    /// 有射紋的年輕隕石坑：第谷（南方高地）與哥白尼
    private static let rayed: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (-0.12, 0.66, 0.045, 0.7),   // 第谷：射紋最長
        (-0.32, -0.12, 0.040, 0.35), // 哥白尼
    ]

    private static let gold = Color(hex: 0xF1D9A0)

    var body: some View {
        let w = size.width, h = size.height
        // 月亮和光暈放上半部、數字放下半部，兩者不能疊到
        let r = w * 0.22
        let center = CGPoint(x: w / 2, y: h * 0.36)

        ZStack {
            Canvas { ctx, _ in
                // 夜空：上面略亮的深藍漸層。半透明疊在底色上，提醒時的底色閃光才透得過來
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x1B2550).opacity(0.85),
                                                                 Color(hex: 0x070A17).opacity(0.85)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                // 砂金石般的金色細點，少數帶十字星芒
                for (i, (x, y, s, a)) in Self.stars.enumerated() {
                    let p = CGPoint(x: w * x, y: h * y)
                    ctx.fill(Path(ellipseIn: circleRect(p, s)), with: .color(Self.gold.opacity(a)))
                    if i % 9 == 0 {
                        var cross = Path()
                        cross.move(to: CGPoint(x: p.x - s * 4, y: p.y))
                        cross.addLine(to: CGPoint(x: p.x + s * 4, y: p.y))
                        cross.move(to: CGPoint(x: p.x, y: p.y - s * 4))
                        cross.addLine(to: CGPoint(x: p.x, y: p.y + s * 4))
                        ctx.stroke(cross, with: .color(Self.gold.opacity(a * 0.5)), lineWidth: 0.5)
                    }
                }

                // 光暈跟著亮面大小變淡
                ctx.fill(Path(ellipseIn: circleRect(center, r * 1.8)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xFBF6E6).opacity(0.03 + 0.14 * c.remaining),
                                                                 .clear]),
                                               center: center, startRadius: r * 0.9, endRadius: r * 1.8))

                let disk = Path(ellipseIn: circleRect(center, r))

                // 暗面：地球反照。同一張月面壓得很暗、偏藍，看得出月海的輪廓
                ctx.drawLayer { l in
                    l.clip(to: disk)
                    Self.drawSurface(in: &l, center: center, r: r)
                    l.fill(disk, with: .color(Color(hex: 0x0A0F26).opacity(0.86)))
                }

                // 亮面：三層往暗面偏一點、越外越淡，明暗交界才是柔和的漸層而不是一刀切
                let f = c.remaining
                if f > 0.002 {
                    for (extra, alpha) in [(0.035, 0.30), (0.017, 0.55), (0.0, 1.0)] {
                        ctx.drawLayer { l in
                            l.clip(to: Self.litPath(center: center, r: r, fraction: min(1, f + extra)))
                            l.opacity = alpha
                            Self.drawSurface(in: &l, center: center, r: r)
                        }
                    }
                }
                ctx.stroke(disk, with: .color(.white.opacity(0.07)), lineWidth: 0.8)
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

    /// 滿月的月面：底色、臨邊昏暗、月海、隕石坑、射紋。亮面和暗面都用它，再各自裁切、調亮度。
    private static func drawSurface(in ctx: inout GraphicsContext, center: CGPoint, r: CGFloat) {
        let disk = Path(ellipseIn: circleRect(center, r))
        // 底色偏暖的灰白，中間亮、邊緣暗（臨邊昏暗）；最亮處偏向光源所在的左邊
        ctx.fill(disk, with: .radialGradient(
            Gradient(colors: [Color(hex: 0xF2EEE4), Color(hex: 0xDCD6C9), Color(hex: 0xAFA898)]),
            center: CGPoint(x: center.x - r * 0.22, y: center.y - r * 0.12),
            startRadius: 0, endRadius: r * 1.15))

        // 月海：先畫一圈放大的淡色，再畫本體，邊緣才不是整齊的橢圓
        var halo = Path(), core = Path()
        for (dx, dy, rx, ry) in maria {
            let c0 = CGPoint(x: center.x + dx * r, y: center.y + dy * r)
            halo.addEllipse(in: CGRect(x: c0.x - rx * r * 1.18, y: c0.y - ry * r * 1.12,
                                       width: rx * r * 2.36, height: ry * r * 2.24))
            core.addEllipse(in: CGRect(x: c0.x - rx * r, y: c0.y - ry * r, width: rx * r * 2, height: ry * r * 2))
            // 每片再加一個錯開的小橢圓，讓輪廓不規則
            core.addEllipse(in: CGRect(x: c0.x + rx * r * 0.2, y: c0.y - ry * r * 0.9,
                                       width: rx * r * 1.1, height: ry * r * 1.2))
        }
        ctx.fill(halo, with: .color(Color(hex: 0x6F695E).opacity(0.14)))
        ctx.fill(core, with: .color(Color(hex: 0x6F695E).opacity(0.30)))

        // 隕石坑是凹下去的：光從左邊來，所以坑的左半（靠光源那側的內壁）在陰影裡、
        // 右半（背光那側的內壁）受光。先畫一片暗的、再往右錯開疊一片亮的
        var shade = Path(), lit = Path()
        for (dx, dy, cr) in craters {
            let p = CGPoint(x: center.x + dx * r, y: center.y + dy * r)
            let s = cr * r
            shade.addEllipse(in: circleRect(CGPoint(x: p.x - s * 0.18, y: p.y), s))
            lit.addEllipse(in: circleRect(CGPoint(x: p.x + s * 0.25, y: p.y), s * 0.72))
        }
        // 這個尺寸下真實的坑很淡，太深會像一顆顆灰點
        ctx.fill(shade, with: .color(.black.opacity(0.11)))
        ctx.fill(lit, with: .color(.white.opacity(0.13)))

        // 年輕隕石坑：亮白的坑和放射狀的射紋
        for (dx, dy, cr, rayLen) in rayed {
            let p = CGPoint(x: center.x + dx * r, y: center.y + dy * r)
            var rays = Path()
            for i in 0..<14 {
                let a = Double(i) / 14 * 2 * .pi + 0.2
                let len = r * rayLen * (0.55 + 0.45 * CGFloat(abs(sin(Double(i) * 1.7))))
                rays.move(to: p)
                rays.addLine(to: CGPoint(x: p.x + len * CGFloat(cos(a)), y: p.y + len * CGFloat(sin(a))))
            }
            ctx.drawLayer { l in
                l.clip(to: disk)
                l.stroke(rays, with: .color(.white.opacity(0.12)), lineWidth: max(0.6, r * 0.018))
            }
            ctx.fill(Path(ellipseIn: circleRect(p, cr * r * 1.6)), with: .color(.white.opacity(0.25)))
            ctx.fill(Path(ellipseIn: circleRect(CGPoint(x: p.x - cr * r * 0.2, y: p.y), cr * r)),
                     with: .color(.black.opacity(0.18)))
            ctx.fill(Path(ellipseIn: circleRect(CGPoint(x: p.x + cr * r * 0.25, y: p.y), cr * r * 0.7)),
                     with: .color(.white.opacity(0.55)))
        }
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
            p.addLine(to: CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a))))
        }
        // 明暗交界：下 → 上，中間在 x = center + k·r
        for i in 1...n {
            let a = Double.pi / 2 - Double.pi * Double(i) / Double(n)
            p.addLine(to: CGPoint(x: center.x + CGFloat(k) * r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a))))
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

/// 參考 Herbert Bayer 等包浩斯海報的構成：紅圓是視覺焦點，扇形＝剩下的時間；
/// 右上四片四分之一圓拼成一個圓，完成幾輪就填幾片藍；底下一條黑色粗帶承載數字。
private struct BauhausDial: View {
    let c: DialContext
    let size: CGSize

    private static let red = Color(hex: 0xD0342C)
    private static let yellow = Color(hex: 0xF2B51C)
    private static let blue = Color(hex: 0x1F4E9C)
    private static let ink = Color(hex: 0x1A1A1A)
    private static let paper = Color(hex: 0xF1EADB)

    var body: some View {
        let w = size.width, h = size.height
        let band = CGRect(x: w * 0.06, y: h * 0.68, width: w * 0.88, height: h * 0.24)

        ZStack {
            Canvas { ctx, _ in
                let line = max(1.2, w * 0.01)
                let cc = CGPoint(x: w * 0.34, y: h * 0.34)
                let r = w * 0.24
                ctx.fill(pie(center: cc, radius: r, fraction: c.remaining), with: .color(Self.red))
                ctx.stroke(Path(ellipseIn: circleRect(cc, r)), with: .color(Self.ink), lineWidth: line)

                // 輪數：四片四分之一圓，從左上順時針填。一輪不是 4 個的話按比例換算
                let q = w * 0.13
                let hub = CGPoint(x: w * 0.64 + q, y: h * 0.08 + q)
                let done = c.rounds > 0
                    ? min(4, Int((Double(min(c.roundInCycle, c.rounds)) / Double(c.rounds) * 4).rounded()))
                    : 0
                for i in 0..<4 {
                    // 左上從 180° 開始，每片 90°（y 軸朝下，角度增加就是順時針）
                    let a0 = Double.pi * (1 + 0.5 * Double(i))
                    var wedge = Path()
                    wedge.move(to: hub)
                    for k in 0...16 {
                        let a = a0 + Double.pi / 2 * Double(k) / 16
                        wedge.addLine(to: CGPoint(x: hub.x + q * CGFloat(cos(a)), y: hub.y + q * CGFloat(sin(a))))
                    }
                    wedge.closeSubpath()
                    if i < done {
                        ctx.fill(wedge, with: .color(Self.blue))
                    } else {
                        ctx.stroke(wedge, with: .color(Self.ink.opacity(0.55)), lineWidth: 1)
                    }
                }

                ctx.fill(Path(CGRect(x: w * 0.64, y: h * 0.44, width: w * 0.28, height: h * 0.07)),
                         with: .color(Self.yellow))
                ctx.fill(Path(band), with: .color(Self.ink))

                // 固定配色的風格不改色，休息時黑帶上坐著一個藍色半圓。
                // 放左邊：右邊那塊空位留給提醒文字（提醒時通常已經進入休息）
                if c.phase.isBreak {
                    let hc = CGPoint(x: band.minX + w * 0.12, y: band.minY)
                    let hr = w * 0.065
                    var dome = Path()
                    dome.move(to: CGPoint(x: hc.x - hr, y: hc.y))
                    for k in 0...24 {
                        let a = Double.pi + Double.pi * Double(k) / 24
                        dome.addLine(to: CGPoint(x: hc.x + hr * CGFloat(cos(a)), y: hc.y + hr * CGFloat(sin(a))))
                    }
                    dome.closeSubpath()
                    ctx.fill(dome, with: .color(Self.blue))
                }
            }

            // Futura-Bold 的數字約 0.6 倍字級寬。原本字級 0.16w 配 0.10w 的格子，
            // 格子等於字寬、字黏在一起；現在每個字兩側各留約 0.015w
            CellText(text: c.clock, font: .custom("Futura-Bold", size: w * 0.135),
                     cell: w * 0.112, color: Self.paper, colonRatio: 0.55)
                .frame(width: band.width - w * 0.08, alignment: .leading)
                .position(x: band.midX, y: band.midY)

            // 靠右、塞在黃條和黑帶之間的空位。放左邊會壓到紅圓。
            if c.alerting {
                Text(c.eyebrow)
                    .font(.custom("Futura-Bold", size: max(9, w * 0.065)))
                    .foregroundStyle(Self.red)
                    .frame(width: w * 0.80, alignment: .trailing)
                    .position(x: w / 2, y: h * 0.59)
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
                .applying(CGAffineTransform(translationX: c.x + CGFloat(sin(a)) * mid, y: c.y - CGFloat(cos(a)) * mid)))
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

/// 白錶面、黑刻度、紅秒針。參考一般鐵路月台鐘和包浩斯系的牆鐘：
/// 12／3／9 三個無襯線數字、外緣一條紅色細弧＝剩下的時間、數位時間收進錶面下方的小窗。
/// 刻意不叫「瑞士鐵路鐘」、秒針也不做尖端紅色圓盤——那是 SBB 受保護的設計。
private struct StationDial: View {
    let c: DialContext
    let size: CGSize

    private static let ink = Color(hex: 0x141414)
    private static let red = Color(hex: 0xD62718)

    var body: some View {
        let r = size.width / 2 - (c.isCompact ? 5 : 3)
        // 紅弧畫在刻度外面、錶面邊緣裡面那一圈縫
        let rim: CGFloat = c.isCompact ? 2.5 : 1.5
        ZStack {
            StationTicks(radius: r).fill(Self.ink)
            Circle()
                .trim(from: min(1, max(0, c.progress)), to: 1)
                .stroke(Self.red, lineWidth: c.isCompact ? 1.8 : 1.2)
                .rotationEffect(.degrees(-90))
                .frame(width: 2 * (r + rim), height: 2 * (r + rim))

            // 12、3、9。6 的位置留給數位小窗
            numeral("12", at: 0, r: r)
            numeral("3", at: 90, r: r)
            numeral("9", at: 270, r: r)

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
            .offset(y: r * 0.66)

            RoundedRectangle(cornerRadius: r * 0.05, style: .continuous)
                .fill(Self.ink.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: r * 0.05, style: .continuous)
                    .stroke(Self.ink.opacity(0.18), lineWidth: 0.75))
                .frame(width: r * 0.72, height: r * 0.27)
                .offset(y: r * 0.40)
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

    private func numeral(_ label: String, at degrees: Double, r: CGFloat) -> some View {
        let a = degrees * .pi / 180
        return Text(label)
            .font(.custom("Helvetica-Bold", size: r * 0.17))
            .foregroundStyle(Self.ink)
            .offset(x: r * 0.60 * CGFloat(sin(a)), y: -r * 0.60 * CGFloat(cos(a)))
    }
}

// MARK: - 蠟燭

/// 蠟燭高度＝剩下的時間。燭淚的形狀是固定的，蠟燭燒短了就一起變短。
/// 火焰是靜態的漸層水滴，不閃爍（閃爍就是常駐動畫）；暫停時火焰暗一點，燒完只剩一縷煙。
private struct CandleDial: View {
    let c: DialContext
    let size: CGSize

    private static let waxHi = Color(hex: 0xFFF8EA)
    private static let waxMid = Color(hex: 0xEADFC6)
    private static let waxLo = Color(hex: 0xCDBC98)
    private static let ink = Color(hex: 0xF3E9D8)
    /// 燭淚：沿寬度的位置、長度（相對於燭身寬）
    private static let drips: [(CGFloat, CGFloat)] = [(0.12, 0.9), (0.34, 0.45), (0.71, 1.25), (0.9, 0.6)]

    var body: some View {
        let w = size.width, h = size.height
        // 縮小模式燭台放高一點、蠟燭短一點，底下才放得下兩行字
        let baseY = h * (c.isCompact ? 0.67 : 0.72)

        ZStack {
            Canvas { ctx, _ in
                let cx = w / 2
                let cw = w * 0.30
                let maxH = h * (c.isCompact ? 0.44 : 0.46)
                let ch = maxH * (0.10 + 0.90 * c.remaining)
                let topY = baseY - ch
                let lit = c.remaining > 0.001
                let flameAlpha = c.running ? 1.0 : 0.7

                // 燭光映在牆上
                if lit {
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                             with: .radialGradient(Gradient(colors: [Color(hex: 0xFFB347).opacity(0.28 * flameAlpha), .clear]),
                                                   center: CGPoint(x: cx, y: topY - w * 0.1),
                                                   startRadius: 0, endRadius: w * 0.75))
                }

                // 燭台：黃銅盤
                let dish = CGRect(x: cx - w * 0.34, y: baseY - w * 0.05, width: w * 0.68, height: w * 0.12)
                ctx.fill(Path(ellipseIn: dish.offsetBy(dx: 0, dy: w * 0.02)), with: .color(.black.opacity(0.35)))
                ctx.fill(Path(ellipseIn: dish), with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xE2B866), Color(hex: 0x9A7132)]),
                    startPoint: CGPoint(x: dish.minX, y: dish.minY), endPoint: CGPoint(x: dish.maxX, y: dish.maxY)))
                ctx.fill(Path(ellipseIn: dish.insetBy(dx: dish.width * 0.12, dy: dish.height * 0.22)),
                         with: .color(Color(hex: 0x6F5020).opacity(0.5)))

                // 燭身：橫向亮暗漸層表現圓柱
                let body = CGRect(x: cx - cw / 2, y: topY, width: cw, height: baseY - topY)
                let wax = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Self.waxLo, Self.waxHi, Self.waxMid, Self.waxLo]),
                    startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0))
                ctx.fill(Path(body), with: wax)
                // 靠近火焰的蠟透著光
                if lit {
                    ctx.fill(Path(CGRect(x: body.minX, y: topY, width: cw, height: min(ch, cw * 0.9))),
                             with: .linearGradient(Gradient(colors: [Color(hex: 0xFFD27A).opacity(0.35 * flameAlpha), .clear]),
                                                   startPoint: CGPoint(x: 0, y: topY), endPoint: CGPoint(x: 0, y: topY + cw * 0.9)))
                }

                // 燭淚：從頂端往下流，末端一顆圓滴
                var drips = Path()
                for (fx, len) in Self.drips {
                    let x = body.minX + cw * fx
                    let L = min(ch * 0.7, cw * len)
                    let dw = cw * 0.11
                    drips.addRoundedRect(in: CGRect(x: x - dw / 2, y: topY, width: dw, height: L),
                                         cornerSize: CGSize(width: dw / 2, height: dw / 2))
                    drips.addEllipse(in: CGRect(x: x - dw * 0.75, y: topY + L - dw * 1.2, width: dw * 1.5, height: dw * 1.6))
                }
                ctx.fill(drips, with: wax)
                ctx.fill(drips, with: .color(.white.opacity(0.12)))

                // 頂端：融化的蠟池
                let pool = CGRect(x: body.minX, y: topY - cw * 0.12, width: cw, height: cw * 0.26)
                ctx.fill(Path(ellipseIn: pool), with: .color(Self.waxMid))
                ctx.fill(Path(ellipseIn: pool.insetBy(dx: cw * 0.14, dy: pool.height * 0.22)),
                         with: .color(Color(hex: 0xF7E3B0).opacity(lit ? 0.9 : 0.5)))

                // 燭芯
                var wick = Path()
                wick.move(to: CGPoint(x: cx, y: topY))
                wick.addQuadCurve(to: CGPoint(x: cx + 1, y: topY - w * 0.055), control: CGPoint(x: cx - 1.2, y: topY - w * 0.03))
                ctx.stroke(wick, with: .color(Color(hex: 0x2A1E16)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                if lit {
                    // 火焰：水滴形，外焰橘、內焰白黃、底部一點藍
                    let fb = CGPoint(x: cx + 0.5, y: topY - w * 0.035)
                    let fh = w * 0.19, fw = w * 0.075
                    var flame = Path()
                    flame.move(to: CGPoint(x: fb.x, y: fb.y - fh))
                    flame.addCurve(to: CGPoint(x: fb.x, y: fb.y),
                                   control1: CGPoint(x: fb.x + fw * 0.35, y: fb.y - fh * 0.62),
                                   control2: CGPoint(x: fb.x + fw * 1.25, y: fb.y - fh * 0.05))
                    flame.addCurve(to: CGPoint(x: fb.x, y: fb.y - fh),
                                   control1: CGPoint(x: fb.x - fw * 1.25, y: fb.y - fh * 0.05),
                                   control2: CGPoint(x: fb.x - fw * 0.35, y: fb.y - fh * 0.62))
                    flame.closeSubpath()
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 3))
                        l.fill(flame, with: .color(Color(hex: 0xFF8A2A).opacity(0.7 * flameAlpha)))
                    }
                    ctx.fill(flame, with: .radialGradient(
                        Gradient(colors: [Color(hex: 0xFFFBEA).opacity(flameAlpha), Color(hex: 0xFFD35A).opacity(flameAlpha),
                                          Color(hex: 0xFF8A2A).opacity(0.85 * flameAlpha)]),
                        center: CGPoint(x: fb.x, y: fb.y - fh * 0.28), startRadius: 0, endRadius: fh * 0.75))
                    ctx.fill(Path(ellipseIn: CGRect(x: fb.x - fw * 0.22, y: fb.y - fh * 0.13, width: fw * 0.44, height: fh * 0.13)),
                             with: .color(Color(hex: 0x5C8DFF).opacity(0.28 * flameAlpha)))
                } else {
                    // 燒完了：一縷煙
                    var smoke = Path()
                    smoke.move(to: CGPoint(x: cx + 1, y: topY - w * 0.06))
                    smoke.addCurve(to: CGPoint(x: cx + 2, y: topY - w * 0.32),
                                   control1: CGPoint(x: cx + 7, y: topY - w * 0.14),
                                   control2: CGPoint(x: cx - 6, y: topY - w * 0.22))
                    ctx.stroke(smoke, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }

            VStack(spacing: c.isCompact ? 1 : 3) {
                Text(c.clock)
                    .font(Theme.clock(c.isCompact ? 22 : 26))
                    .foregroundStyle(Self.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                StatusLine(c: c, dot: 3.5)
            }
            // 縮小模式提醒時，閃動的外框畫在輪廓裡面；文字要離底邊遠一點，不然「休息時間」會壓在外框上
            .position(x: w / 2, y: baseY + (h - baseY) / 2 + (c.isCompact ? 0 : 4))
        }
        .frame(width: w, height: h)
    }
}

// MARK: - 黑膠唱片

/// 唱片圖上要印的東西。只有這些變了才重畫唱片圖，計時中每秒的更新不會碰到它。
private struct RecordKey: Hashable {
    let title: String
    let sideB: Bool
    let mode: TimerMode
    let track: Int
    let tracks: Int
    let diameter: CGFloat
    let scale: CGFloat
}

/// 唱片本體：溝紋、軌間空白、外緣、標籤、中心孔。這張圖會整張轉，
/// 所以上面只放會跟著唱片轉的東西——時間、提醒文字、輪數都不放在這裡。
private struct RecordArt: View {
    let key: RecordKey

    private var sideLabel: String {
        switch key.mode {
        case .pomodoro:  return "SIDE \(key.sideB ? "B" : "A") · TRACK \(key.track)"
        case .countdown: return "SINGLE"
        case .stopwatch: return "LIVE"
        }
    }

    var body: some View {
        let d = key.diameter
        let R = d / 2
        let labelR = R * 0.40
        let labelColor = key.sideB ? Color(hex: 0x1F5C63) : Color(hex: 0xC8452F)
        let paper = Color(hex: 0xF6EBDD)

        ZStack {
            Canvas { ctx, _ in
                let c = CGPoint(x: R, y: R)
                // 唱片本體
                ctx.fill(Path(ellipseIn: circleRect(c, R * 0.985)), with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x1E1E1E), Color(hex: 0x0B0B0B)]),
                    center: c, startRadius: labelR, endRadius: R))

                // 溝紋：一圈一圈，亮度微微交錯，看起來才像有深淺的刻痕
                let outer = R * 0.955, inner = labelR * 1.12
                let pitch = max(1.2, R * 0.018)
                var even = Path(), odd = Path()
                var gr = inner, i = 0
                while gr < outer {
                    if i % 2 == 0 { even.addEllipse(in: circleRect(c, gr)) } else { odd.addEllipse(in: circleRect(c, gr)) }
                    gr += pitch
                    i += 1
                }
                ctx.stroke(even, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                ctx.stroke(odd, with: .color(.white.opacity(0.025)), lineWidth: 0.5)

                // 軌與軌之間的空白帶：比溝紋亮一點的平滑環。番茄鐘一輪幾個番茄就分幾軌
                let tracks = max(1, key.tracks)
                if tracks > 1 {
                    var gaps = Path()
                    for t in 1..<tracks {
                        let gapR = outer - (outer - inner) * CGFloat(t) / CGFloat(tracks)
                        gaps.addEllipse(in: circleRect(c, gapR))
                    }
                    ctx.stroke(gaps, with: .color(.white.opacity(0.10)), lineWidth: max(1, R * 0.018))
                }
                // 導入溝（最外圈）和收尾溝（標籤外）
                ctx.stroke(Path(ellipseIn: circleRect(c, outer + R * 0.012)),
                           with: .color(.white.opacity(0.08)), lineWidth: 0.8)
                ctx.stroke(Path(ellipseIn: circleRect(c, inner - R * 0.03)),
                           with: .color(.white.opacity(0.07)), lineWidth: 0.8)
                // 唱片邊緣的亮邊
                ctx.stroke(Path(ellipseIn: circleRect(c, R * 0.98)),
                           with: .color(.white.opacity(0.14)), lineWidth: 0.8)

                // 標籤：底色、一圈細環
                ctx.fill(Path(ellipseIn: circleRect(c, labelR)), with: .radialGradient(
                    Gradient(colors: [labelColor.opacity(0.92), labelColor]),
                    center: c, startRadius: 0, endRadius: labelR))
                ctx.stroke(Path(ellipseIn: circleRect(c, labelR * 0.93)),
                           with: .color(paper.opacity(0.4)), lineWidth: 0.6)
                // 中心孔
                ctx.fill(Path(ellipseIn: circleRect(c, max(1.6, R * 0.024))), with: .color(Color(hex: 0x0E0E0E)))
            }

            // 標籤上的字：廠牌、歌名（＝任務）、面與軌、轉速
            Text("POMODORO RECORDS")
                .font(.system(size: max(4.5, labelR * 0.13), weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(paper.opacity(0.75))
                .position(x: R, y: R - labelR * 0.64)
            Text(key.title)
                .font(.system(size: max(6, labelR * 0.25), weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .foregroundStyle(paper)
                .frame(width: labelR * 1.45, height: labelR * 0.55)
                .position(x: R, y: R - labelR * 0.27)
            Text(sideLabel)
                .font(.system(size: max(4.5, labelR * 0.14), weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(paper.opacity(0.9))
                .position(x: R, y: R + labelR * 0.34)
            Text("33⅓ RPM")
                .font(.system(size: max(4.5, labelR * 0.13), weight: .medium))
                .foregroundStyle(paper.opacity(0.7))
                .position(x: R, y: R + labelR * 0.58)
        }
        .frame(width: d, height: d)
    }
}

/// 唱片圖的快取。ImageRenderer 不便宜，只在標籤內容或尺寸變了才重畫；
/// 同一個 key 回傳同一個 CGImage 物件，SpinningRecord 靠這個判斷「圖沒變」。
@MainActor
private enum RecordArtCache {
    private static var images: [RecordKey: CGImage] = [:]

    static func image(for key: RecordKey) -> CGImage? {
        if let hit = images[key] { return hit }
        let renderer = ImageRenderer(content: RecordArt(key: key))
        renderer.scale = key.scale
        guard let img = renderer.cgImage else { return nil }
        // 縮小模式、完整模式、設定縮圖各一張，加上換任務名稱時的舊圖；超過就整個清掉重來
        if images.count > 8 { images.removeAll() }
        images[key] = img
        return img
    }
}

/// 轉唱片的那層：一個 CALayer 放唱片圖，由 Core Animation 轉——
/// 動畫交給 WindowServer 合成，SwiftUI 仍然只吃 1 Hz 的更新。
private final class RecordSpinView: NSView {
    private let disc = CALayer()
    private var spinning = false
    private var currentImage: CGImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        disc.contentsGravity = .resizeAspect
        layer?.addSublayer(disc)

        // 動畫只在這裡加一次，之後只用 speed / timeOffset 暫停與恢復。
        // 每秒 updateNSView 重加的話，唱片會每秒跳回原點。
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi            // 圖層座標 y 朝上，負的才是順時針
        spin.duration = 1.8                      // 33⅓ RPM
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        spin.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 20, preferred: 20)
        disc.add(spin, forKey: "spin")
        pause()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 滑鼠事件穿過去給 SwiftUI：拖曳設定時間、點一下停止提醒都靠它
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.bounds = CGRect(origin: .zero, size: bounds.size)
        disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func setImage(_ image: CGImage, scale: CGFloat) {
        if let current = currentImage, current === image { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.contents = image
        disc.contentsScale = scale
        CATransaction.commit()
        currentImage = image
    }

    func setSpinning(_ on: Bool) {
        guard on != spinning else { return }
        spinning = on
        if on { resume() } else { pause() }
    }

    /// 停在當下角度（Apple 文件的標準做法）
    private func pause() {
        let t = disc.convertTime(CACurrentMediaTime(), from: nil)
        disc.speed = 0
        disc.timeOffset = t
    }

    /// 從暫停的角度接著轉
    private func resume() {
        let paused = disc.timeOffset
        disc.speed = 1
        disc.timeOffset = 0
        disc.beginTime = 0
        disc.beginTime = disc.convertTime(CACurrentMediaTime(), from: nil) - paused
    }
}

private struct SpinningRecord: NSViewRepresentable {
    let image: CGImage
    let scale: CGFloat
    let spins: Bool

    func makeNSView(context: Context) -> RecordSpinView {
        let v = RecordSpinView(frame: .zero)
        v.setImage(image, scale: scale)
        v.setSpinning(spins)
        return v
    }

    /// 冪等：圖沒換、spins 沒變就什麼都不做
    func updateNSView(_ v: RecordSpinView, context: Context) {
        v.setImage(image, scale: scale)
        v.setSpinning(spins)
    }
}

/// 黑膠唱片：唱臂從外圈往內走＝進度。
///
/// 四層：會轉的唱片圖（只在完整模式計時中轉）、不轉的光澤與「播過的外圈」、
/// 不轉的唱臂、不轉的時間膠囊。縮小模式不轉——讀書時眼角有東西一直轉會分心。
private struct VinylDial: View {
    let c: DialContext
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let R = min(w, h) / 2 - (c.isCompact ? 3 : 2)
        let center = CGPoint(x: w / 2, y: h / 2)
        let labelR = R * 0.40
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let trimmed = c.task.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RecordKey(title: trimmed.isEmpty ? "專注時光" : trimmed,
                            sideB: c.phase.isBreak, mode: c.mode,
                            track: c.roundInCycle + 1, tracks: c.mode == .pomodoro ? c.rounds : 1,
                            diameter: (2 * R).rounded(), scale: scale)
        let art = RecordArtCache.image(for: key)

        ZStack {
            Circle().fill(Color(hex: 0x111111))
                .frame(width: 2 * R, height: 2 * R)
                .position(center)

            if let art {
                Group {
                    if c.usesLiveRecord {
                        SpinningRecord(image: art, scale: scale, spins: c.spins)
                    } else {
                        Image(decorative: art, scale: scale)
                    }
                }
                .frame(width: key.diameter, height: key.diameter)
                .position(center)
            }

            Canvas { ctx, _ in
                // 光澤：光源不動，唱片在底下轉，反光就該停在原地
                for start in [0.58, 0.08] {
                    ctx.fill(sector(center: center, radius: R * 0.96, from: start).intersection(
                        pie(center: center, radius: R * 0.96, fraction: start + 0.07)),
                             with: .color(.white.opacity(0.07)))
                }

                // 唱針所在的半徑：從外圈往內走
                let playR = R * 0.95 - (R * 0.95 - labelR * 1.1) * c.progress

                // 播過的外圈稍微暗一點（畫在不轉的這層，唱片圖不用每秒重畫）
                if c.progress > 0.002 {
                    var played = Path(ellipseIn: circleRect(center, R * 0.955))
                    played.addEllipse(in: circleRect(center, playR))
                    ctx.fill(played, with: .color(.black.opacity(0.25)), style: FillStyle(eoFill: true))
                }

                // 唱臂：支點在右上
                let pivot = CGPoint(x: center.x + R * 0.62, y: center.y - R * 0.62)
                let L = R * 0.95
                let idle = !c.running && c.progress < 0.001 && !c.alerting
                let needle: CGPoint
                if idle {
                    // 還沒開始／歸零：擱在唱片外緣的支架上
                    let a = 15.0 * .pi / 180
                    needle = CGPoint(x: pivot.x + L * CGFloat(sin(a)), y: pivot.y + L * CGFloat(cos(a)))
                    ctx.fill(Path(roundedRect: CGRect(x: needle.x - R * 0.035, y: needle.y - R * 0.02,
                                                      width: R * 0.07, height: R * 0.1), cornerRadius: 1.5),
                             with: .color(Color(hex: 0x5A5A5A)))
                } else {
                    // 唱針落在半徑 playR 的地方：兩圓交點取右下那一個
                    let px = pivot.x - center.x, py = pivot.y - center.y
                    let d = (px * px + py * py).squareRoot()
                    let a = (playR * playR - L * L + d * d) / (2 * d)
                    let hh = max(0, playR * playR - a * a).squareRoot()
                    needle = CGPoint(x: center.x + a * px / d - hh * py / d,
                                     y: center.y + a * py / d + hh * px / d)
                }
                // 暫停時唱臂在原位抬起：影子拉遠變淡，唱臂本身往上一點
                let lifted = !c.running && !idle
                let lift: CGFloat = lifted ? -1.5 : 0
                let shadowOffset = lifted ? CGSize(width: 4, height: 5.5) : CGSize(width: 1.5, height: 2)
                let shadowAlpha = lifted ? 0.25 : 0.45

                let tail = CGPoint(x: pivot.x + (pivot.x - needle.x) * 0.16, y: pivot.y + (pivot.y - needle.y) * 0.16)
                var arm = Path()
                arm.move(to: tail)
                arm.addLine(to: needle)
                ctx.stroke(arm.applying(CGAffineTransform(translationX: shadowOffset.width, y: shadowOffset.height)),
                           with: .color(.black.opacity(shadowAlpha)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                let raised = arm.applying(CGAffineTransform(translationX: 0, y: lift))
                ctx.stroke(raised, with: .linearGradient(Gradient(colors: [Color(hex: 0xF2F2F2), Color(hex: 0x9C9C9C)]),
                                                         startPoint: pivot, endPoint: needle),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                // 配重：唱臂尾端的圓柱
                ctx.fill(Path(ellipseIn: circleRect(CGPoint(x: tail.x, y: tail.y + lift), R * 0.06)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xDADADA), Color(hex: 0x555555)]),
                                               center: CGPoint(x: tail.x - R * 0.02, y: tail.y - R * 0.02),
                                               startRadius: 0, endRadius: R * 0.07))
                // 唱頭
                let angle = atan2(Double(needle.y - pivot.y), Double(needle.x - pivot.x))
                let head = Path(roundedRect: CGRect(x: -R * 0.065, y: -R * 0.038, width: R * 0.13, height: R * 0.076),
                                cornerRadius: 1.5)
                    .applying(CGAffineTransform(rotationAngle: angle))
                    .applying(CGAffineTransform(translationX: needle.x, y: needle.y + lift))
                ctx.fill(head, with: .color(Color(hex: 0xD8D8D8)))
                // 升降桿：支點旁的小柱
                ctx.fill(Path(roundedRect: CGRect(x: pivot.x - R * 0.2, y: pivot.y + R * 0.1,
                                                  width: R * 0.05, height: R * 0.12), cornerRadius: 1),
                         with: .color(Color(hex: 0x8A8A8A)))
                // 支點
                ctx.fill(Path(ellipseIn: circleRect(pivot, R * 0.09)), with: .radialGradient(
                    Gradient(colors: [Color(hex: 0xF4F4F4), Color(hex: 0x7A7A7A)]),
                    center: CGPoint(x: pivot.x - R * 0.03, y: pivot.y - R * 0.03), startRadius: 0, endRadius: R * 0.1))
            }

            // 時間膠囊：不轉。中心在圓心下方 0.65R，高 0.36R（0.47R～0.83R），
            // 在標籤（0.40R）之外、圓形輪廓之內；唱針最內圈在右側約 0.44R 處，碰不到它
            VStack(spacing: 2) {
                Text(c.clock)
                    .font(.system(size: R * 0.19, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(hex: 0xF6EBDD))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                StatusLine(c: c, dot: 3.5)
            }
            .frame(width: R * 0.9, height: R * 0.36)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
            .position(x: center.x, y: center.y + R * 0.65)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - 輝光管

/// 每支玻璃管裡一個橘色發光的數字，後面淡淡疊著沒亮的數字——輝光管的陰極是一疊數字。
/// 底座一排小燈＝剩下的時間。
private struct NixieDial: View {
    let c: DialContext
    let size: CGSize

    private static let glow = Color(hex: 0xFF7A1F)
    private static let core = Color(hex: 0xFFC27A)

    var body: some View {
        let w = size.width, h = size.height
        let digits = c.clock.filter { $0 != ":" }.map { String($0) }
        let minuteCount = c.minutes.count

        Canvas { ctx, _ in
            let pad = w * 0.05
            let colonW = w * 0.05
            let gap = w * 0.018
            let n = CGFloat(digits.count)
            let tubeW = (w - 2 * pad - colonW - gap * (n - 1)) / n
            let tubeTop = h * 0.07
            let tubeH = h * 0.64
            let font = Font.system(size: tubeH * 0.66, weight: .light)

            var x = pad
            for (i, digit) in digits.enumerated() {
                if i == minuteCount {
                    // 冒號：兩顆氖燈，計時中一秒亮一秒暗
                    let on = !c.running || (Int(c.seconds) ?? 0) % 2 == 0
                    for fy in [0.38, 0.62] {
                        let dot = circleRect(CGPoint(x: x - gap / 2 + colonW / 2, y: tubeTop + tubeH * CGFloat(fy)), 2)
                        if on {
                            ctx.drawLayer { l in
                                l.addFilter(.blur(radius: 2.5))
                                l.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(Self.glow))
                            }
                        }
                        ctx.fill(Path(ellipseIn: dot), with: .color(on ? Self.core : Color(hex: 0x4A2E1C)))
                    }
                    x += colonW
                }

                let tube = CGRect(x: x, y: tubeTop, width: tubeW, height: tubeH)
                let shape = Path(roundedRect: tube, cornerSize: CGSize(width: tubeW * 0.45, height: tubeW * 0.45))
                // 玻璃管
                ctx.fill(shape, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.10), .white.opacity(0.02), .white.opacity(0.06)]),
                    startPoint: CGPoint(x: tube.minX, y: 0), endPoint: CGPoint(x: tube.maxX, y: 0)))
                // 陽極網：淡淡的斜格
                ctx.drawLayer { l in
                    l.clip(to: shape)
                    var mesh = Path()
                    var mx = tube.minX - tubeH
                    while mx < tube.maxX {
                        mesh.move(to: CGPoint(x: mx, y: tube.maxY))
                        mesh.addLine(to: CGPoint(x: mx + tubeH, y: tube.minY))
                        mx += 3.5
                    }
                    l.stroke(mesh, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
                }
                let mid = CGPoint(x: tube.midX, y: tube.midY + tubeH * 0.02)
                // 沒亮的陰極數字
                for ghost in ["8", "0"] where ghost != digit {
                    ctx.draw(Text(ghost).font(font).foregroundColor(Color(hex: 0x6B4A33).opacity(0.35)), at: mid)
                }
                // 亮的數字：先畫一層模糊的光暈，再畫本體
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 4))
                    l.draw(Text(digit).font(font).foregroundColor(Self.glow), at: mid)
                }
                ctx.draw(Text(digit).font(font).foregroundColor(Self.core), at: mid)
                // 玻璃反光與輪廓
                ctx.fill(Path(roundedRect: CGRect(x: tube.minX + tubeW * 0.14, y: tube.minY + tubeW * 0.25,
                                                  width: 1.4, height: tubeH * 0.5), cornerRadius: 0.7),
                         with: .color(.white.opacity(0.25)))
                ctx.stroke(shape, with: .color(.white.opacity(0.16)), lineWidth: 0.8)
                // 管座
                ctx.fill(Path(roundedRect: CGRect(x: tube.minX + 1, y: tube.maxY - 2, width: tubeW - 2, height: h * 0.05),
                              cornerRadius: 1.5), with: .color(Color(hex: 0x2B2B2B)))
                x += tubeW + gap
            }

            // 底座與一排小燈：剩多少亮多少
            let base = CGRect(x: pad * 0.6, y: h * 0.79, width: w - pad * 1.2, height: h * 0.14)
            ctx.fill(Path(roundedRect: base, cornerRadius: 3), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x3A2B20), Color(hex: 0x1E1611)]),
                startPoint: CGPoint(x: 0, y: base.minY), endPoint: CGPoint(x: 0, y: base.maxY)))
            let lamps = 12
            let litCount = c.remaining > 0 ? Int(ceil(c.remaining * Double(lamps))) : 0
            let lampSpan = base.width * 0.62
            for i in 0..<lamps {
                let p = CGPoint(x: base.minX + base.width * 0.06 + lampSpan * CGFloat(i) / CGFloat(lamps - 1),
                                y: base.midY)
                if i < litCount {
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 2))
                        l.fill(Path(ellipseIn: circleRect(p, 2.6)), with: .color(Self.glow.opacity(0.9)))
                    }
                    ctx.fill(Path(ellipseIn: circleRect(p, 1.5)), with: .color(Self.core))
                } else {
                    ctx.fill(Path(ellipseIn: circleRect(p, 1.5)), with: .color(Color(hex: 0x4A3526)))
                }
            }
            // 底座右邊的小字：提醒、休息，或模式名稱
            let tag = c.alerting ? c.eyebrow : (c.phase.isBreak || !c.showsRounds ? c.eyebrow : "")
            if !tag.isEmpty {
                ctx.draw(Text(tag).font(.system(size: max(7.5, h * 0.075), weight: .semibold))
                            .foregroundColor(c.alerting ? Self.core : Color(hex: 0xC9A27E)),
                         at: CGPoint(x: base.maxX - base.width * 0.14, y: base.midY))
            }
        }
        .frame(width: w, height: h)
    }
}
