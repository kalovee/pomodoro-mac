import SwiftUI
import AppKit

/// 取代 @State 用的。
///
/// macOS 27 的 SDK 把 @State 改成巨集實作，而那個巨集外掛只跟完整版 Xcode 一起出貨，
/// 純命令列工具（xcode-select --install）編不出來。用 @StateObject 包一個小物件，
/// 行為完全相同，也不必為了編譯去裝整包 Xcode。
final class ViewState: ObservableObject {
    @Published var showSettings = false
    @Published var showHistory = false
    @Published var hovering = false
    /// 拖曳錶盤設定時間時，目前指到的分鐘數；沒在拖就是 nil
    @Published var dragMinutes: Int?
}

extension Notification.Name {
    /// 縮小模式的錶盤要不要淡出。object 是 Bool。
    static let dialFadeChanged = Notification.Name("dialFadeChanged")
}

/// 完整模式錶盤區的寬度：視窗寬減掉左右內距。拖曳設定時間要用它找圓心。
private let dialAreaWidth: CGFloat = Metrics.full.width - 36
private let dialAreaHeight: CGFloat = 222

/// 完整模式錶盤在視窗裡的位置（視窗內容座標，左上角為原點）。
/// 給 PanelHostingView 用：這一塊的拖曳要留給「拖曳設定時間」，不能拿來移動視窗。
@MainActor
enum DialDragZone {
    static var rect: CGRect?
}

/// 提醒時錶盤該顯示的字。放在這裡是因為完整模式和縮小模式都要用。
func alertEyebrow(for finished: Phase?) -> String {
    finished == .work ? "休息時間" : "該專注了"
}

struct ContentView: View {
    @EnvironmentObject var model: PomodoroModel
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        ZStack {
            if prefs.compact {
                CompactView().transition(.opacity)
            } else {
                FullView().transition(.opacity)
            }
        }
        // 視窗會比內容高出一個標題列，底色鋪滿整個視窗才不會出現接縫
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if prefs.compact { Color.clear } else { GlowBackdrop(tint: Theme.accent(model.phase)) }
        }
        .clipped()
        // 必須放在 .clipped() 之後：SwiftUI 會為標題列留一塊安全區，
        // 內容和底色只鋪在安全區內，最上面 20pt 會是沒畫到的透明帶。
        // 放在 clipped 前面的話會被它切回去。
        .ignoresSafeArea()
        .animation(.easeInOut(duration: Metrics.morph), value: prefs.compact)
        .animation(.easeInOut(duration: 0.28), value: model.phase)
    }
}

/// 完整模式的背景：底色上兩團靜態的光暈，給上面的玻璃控制項有東西可以折射。
/// 刻意不用 .blur（模糊濾鏡每次重畫都要重算），也不做會動的光暈——只在換階段時跟著變色。
private struct GlowBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            Theme.ground
            RadialGradient(colors: [tint.opacity(0.20), tint.opacity(0)],
                           center: UnitPoint(x: 0.12, y: 0.10), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(hex: 0xF2A65A).opacity(0.14), Color(hex: 0xF2A65A).opacity(0)],
                           center: UnitPoint(x: 0.92, y: 0.95), startRadius: 0, endRadius: 300)
        }
    }
}

// MARK: - 完整模式

private struct FullView: View {
    @EnvironmentObject var model: PomodoroModel
    @EnvironmentObject var prefs: Prefs
    @StateObject private var ui = ViewState()
    @FocusState private var taskFocused: Bool

    private var tint: Color { Theme.accent(model.phase) }

    var body: some View {
        VStack(spacing: 0) {
            // 高度預算見 Metrics.full：每一列都是固定高度，只有 Spacer 會伸縮
            topBar
            dial.padding(.top, 2)
            taskField.padding(.top, 16)
            controls.padding(.top, 14)
            logProgress
            Spacer(minLength: 12)
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        // 不寫死高度：拿到多少就用多少，視窗內容區跟設計值有落差時才不會被裁掉
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 底色和光暈畫在 ContentView 最外層，才會鋪到標題列那一塊
        .animation(.easeInOut(duration: 0.28), value: model.phase)
        .sheet(isPresented: $ui.showSettings) { SettingsView() }
        .sheet(isPresented: $ui.showHistory) { HistoryView() }
        .onChange(of: prefs.workMin) { model.syncDurationIfIdle() }
        .onChange(of: prefs.shortMin) { model.syncDurationIfIdle() }
        .onChange(of: prefs.longMin) { model.syncDurationIfIdle() }
        .onChange(of: prefs.countdownMin) { model.syncDurationIfIdle() }
    }

    // 上排：模式選單在視窗正中間；釘選／縮小靠右。
    // 兩層疊起來而不是排成一列，選單才是以整個視窗置中，不會被左邊紅綠燈的留白推偏。
    private var topBar: some View {
        ZStack {
            modePicker
            HStack(spacing: 2) {
                Spacer()
                topButtons
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private var topButtons: some View {
        ghostButton(prefs.alwaysOnTop ? "pin.fill" : "pin",
                    active: prefs.alwaysOnTop,
                    tint: tint,
                    help: prefs.alwaysOnTop ? "取消浮動" : "浮在最上層，全螢幕 App 上也看得到") {
            prefs.alwaysOnTop.toggle()
        }
        ghostButton("arrow.down.right.and.arrow.up.left",
                    active: false, tint: tint, help: "縮小成計時器") {
            prefs.compact = true
        }
    }

    /// 番茄鐘／倒數／碼錶。用系統的分段選單：macOS 26 會把它畫成 Liquid Glass，
    /// 選中的那一格會滑過去。寬度固定 156pt，置中後左緣約在 x=82，避開紅綠燈。
    private var modePicker: some View {
        Picker("模式", selection: Binding(get: { prefs.timerMode },
                                          set: { m in
                                              taskFocused = false
                                              model.setMode(m)
                                          })) {
            ForEach(TimerMode.allCases) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 156)
        .help(prefs.timerMode.note)
    }

    private var dial: some View {
        let style = prefs.dialStyle
        let panel = style.fullSize
        return ZStack {
            if style.showsPanelInFull {
                style.silhouette
                    .fill(style.surface)
                    .overlay(style.silhouette.stroke(style.outline, lineWidth: 1))
                    .frame(width: panel.width, height: panel.height)
            }
            if model.alerting {
                PulseOutline(shape: style.silhouette, tint: tint, breath: model.breath ? 1 : 0)
                    .frame(width: panel.width + 18, height: panel.height + 18)
            }
            StyledDial(style: style,
                       context: DialContext(model: model, prefs: prefs, isCompact: false),
                       size: panel)
                .frame(width: panel.width, height: panel.height)
                // 有面板的風格內容不能超出面板——水位的水是整塊矩形，靠這裡切成圓的
                .clipShape(style.showsPanelInFull ? style.silhouette : AnyShape(Rectangle()))
        }
        .overlay {
            CompletionBurst(trigger: model.completionCount, tint: tint,
                            diameter: min(max(panel.width, panel.height) + 20, dialAreaHeight))
        }
        .overlay(alignment: .bottom) {
            if let m = ui.dragMinutes {
                Text("\(m) 分鐘")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(width: dialAreaWidth, height: dialAreaHeight)
        // 回報錶盤的位置，視窗才知道這一塊不能拿來拖著移動（見 PanelHostingView）
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { DialDragZone.rect = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, r in DialDragZone.rect = r }
                    .onDisappear { DialDragZone.rect = nil }
            }
        }
        .animation(.easeInOut(duration: Metrics.pulse), value: model.breath)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: ui.dragMinutes == nil)
        .contentShape(Rectangle())
        .onTapGesture { if model.alerting { model.acknowledge() } }
        // 像轉實體計時器一樣：從正上方順時針拖到幾分鐘就是幾分鐘，一分鐘一格
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { v in
                    guard model.canSetDurationByDrag else { return }
                    let dx = v.location.x - dialAreaWidth / 2
                    let dy = v.location.y - dialAreaHeight / 2
                    var angle = atan2(Double(dx), Double(-dy))
                    if angle < 0 { angle += 2 * .pi }
                    var m = Int((angle / (2 * .pi) * 60).rounded())
                    if m == 0 { m = 60 }
                    if m != ui.dragMinutes {
                        ui.dragMinutes = m
                        model.setDurationByDrag(minutes: m)
                        // 每跨一格給一下觸控板回饋，像旋鈕的段落感
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                }
                .onEnded { _ in ui.dragMinutes = nil }
        )
        .help(model.canSetDurationByDrag ? "拖曳錶盤可以調整時間" : "")
    }

    private var taskField: some View {
        TextField("正在做什麼？", text: $model.task)
            .textFieldStyle(.plain)
            .font(Theme.label)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .focused($taskFocused)
            // 兩邊都留出選單圖示的寬度，文字才會保持置中、長字也不會壓到圖示
            .padding(.horizontal, 28)
            .frame(height: 34)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            // 聚焦時外加一圈階段色細框，看得出游標在這裡
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(taskFocused ? 0.55 : 0), lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.15), value: taskFocused)
            .onSubmit { taskFocused = false }
            .overlay(alignment: .trailing) { recentTaskMenu }
    }

    /// 任務欄右邊的小選單：最近用過的任務，點一下就填好。
    /// 重打容易多一個空格或少一個字，統計就會把同一件事拆成兩筆。
    @ViewBuilder
    private var recentTaskMenu: some View {
        let recent = model.recentTasks
        if !recent.isEmpty {
            Menu {
                ForEach(recent, id: \.self) { name in
                    Button(name) {
                        model.task = name
                        taskFocused = false
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 9)
            .help("最近的任務")
        }
    }

    /// 三顆按鈕放在同一個玻璃容器裡，靠近時玻璃會融在一起。
    /// 高度固定 40：按鈕樣式自己的內距不會把這一列撐高，高度預算才算得準。
    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
        HStack(spacing: 10) {
            circleButton("arrow.counterclockwise",
                         help: prefs.timerMode == .stopwatch ? "歸零" : "重設這一段") { model.reset() }

            Button {
                taskFocused = false
                model.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(model.running ? "暫停" : "開始")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // 染上階段色的玻璃；interactive 讓它按下會彈、滑鼠移上去會亮
            .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
            // ⌘↩ 交給選單列處理：縮小模式沒有這顆按鈕，
            // 放在選單才是兩種模式都有效，也不會兩邊搶同一組鍵。
            circleButton("forward.end.fill", help: "跳過這一段") { model.skip() }
                .disabled(!model.canSkip)
                .opacity(model.canSkip ? 1 : 0.35)
        }
        }
        .frame(height: 40)
    }

    /// 只有真的累積到一分鐘以上才出現。
    /// 視窗高度（Metrics.full）已經替這一列留了位置：平常是下方 Spacer 的空白，
    /// 按鈕出現時吃掉那塊空白，上面的東西和底部那列都不會移動。
    @ViewBuilder
    private var logProgress: some View {
        if model.canLogProgress {
            Button { model.logProgressAndBreak() } label: {
                Text("結束並記下 \(model.elapsedMinutes) 分鐘")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .capsule)
            .help(prefs.timerMode == .stopwatch
                  ? "把這段時間記進紀錄，碼錶歸零"
                  : "把已經專注的時間記進紀錄，然後進入休息")
            .padding(.top, 10)
        } else if model.canSetDurationByDrag && ui.dragMinutes == nil {
            // 閒置時告訴使用者錶盤可以拖。放在同一個位置，版面不會跳
            Text("拖曳錶盤可以調整時間")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted.opacity(0.75))
                .frame(height: 14)
                .padding(.top, 14)
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button { ui.showHistory = true } label: {
                HStack(spacing: 5) {
                    Text("今日 \(model.todayCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text(durationText)
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .help("查看完成紀錄")

            Spacer()

            ghostButton("gearshape", active: false, tint: tint, help: "設定") {
                ui.showSettings = true
            }
        }
        // 底部列本身是一條玻璃膠囊，取代原本的分隔線
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }

    private var durationText: String {
        let m = model.todayMinutes
        guard m > 0 else { return "· 還沒開始" }
        return m >= 60 ? "· 專注 \(m / 60) 小時 \(m % 60) 分" : "· 專注 \(m) 分鐘"
    }

    // MARK: 按鈕樣式

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }

    private func ghostButton(_ symbol: String, active: Bool, tint: Color,
                             help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? tint : Theme.muted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .hoverLift(1.12)
        .help(help)
    }
}

// MARK: - 縮小模式：一個可以拖著走的浮動錶盤

private struct CompactView: View {
    @EnvironmentObject var model: PomodoroModel
    @EnvironmentObject var prefs: Prefs
    @StateObject private var ui = ViewState()

    private var tint: Color { Theme.accent(model.phase) }
    private var style: DialStyle { prefs.dialStyle }
    /// 視窗尺寸——形狀跟著風格走
    private var size: CGSize { style.compactSize }
    /// 輪廓尺寸：視窗往內縮一圈，讓輪廓的抗鋸齒邊不會被視窗邊界切平
    private var panel: CGSize {
        CGSize(width: size.width - 2 * DialStyle.inset, height: size.height - 2 * DialStyle.inset)
    }

    var body: some View {
        ZStack {
            // 輪廓本身不縮放、不改透明度。系統陰影是依輪廓的透明度算一次就快取起來的，
            // 輪廓一縮一放，陰影跟不上，邊緣會露出一圈——等於換個形式把框框請回來。
            // 脈動、提醒色、內容都疊在它上面各自動。
            //
            // 陰影交給系統畫（PanelController 的 hasShadow）。原本這裡的 .shadow(radius: 12, y: 4)
            // 要伸出約 16pt，但圓盤離視窗邊緣只有 6pt，被外層 .clipped() 和視窗邊界硬切，
            // 切口就是圓盤後面那圈方框。
            style.silhouette
                .fill(style.surface)
                .overlay(style.silhouette.stroke(style.outline, lineWidth: 1))

            ZStack {
                style.silhouette.fill(tint.opacity(alertWash))
                if model.alerting {
                    PulseOutline(shape: style.silhouette, tint: tint, breath: model.breath ? 1 : 0)
                }
                StyledDial(style: style,
                           context: DialContext(model: model, prefs: prefs,
                                                isCompact: true,
                                                hovering: ui.hovering && !style.dimsOnHover),
                           size: panel)
                    .clipShape(style.silhouette)
                    // 寬的、高的和指針式的風格沒有空位放按鈕，懸停時把錶面壓暗、按鈕疊在正中間
                    .opacity(ui.hovering && style.dimsOnHover ? 0.22 : 1)
                CompletionBurst(trigger: model.completionCount, tint: tint,
                                diameter: min(panel.width, panel.height) - 8)
            }
            // 只內縮不放大：外層有 .clipped()，放大的部分會被切在視窗邊緣
            .scaleEffect(model.alerting && model.breath ? 0.96 : 1)

            // 滑鼠移上去才出現控制項，平常只剩計時器本身
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    compactButton(model.running ? "pause.fill" : "play.fill") { model.toggle() }
                    compactButton("arrow.up.left.and.arrow.down.right") { prefs.compact = false }
                }
            }
            .offset(y: style.dimsOnHover ? 0 : panel.height * 0.26)
            .opacity(ui.hovering ? 1 : 0)
        }
        .frame(width: panel.width, height: panel.height)
        // 只有輪廓裡面算數：透明的角落點下去要能穿到後面的 App
        .contentShape(style.silhouette)
        .padding(DialStyle.inset)
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.18), value: ui.hovering)
        .animation(.easeInOut(duration: 0.28), value: model.phase)
        .animation(.easeInOut(duration: Metrics.pulse), value: model.breath)
        // 淡出交給視窗的 alphaValue，不用 SwiftUI 的 opacity：系統陰影是快取的，
        // 只把內容調淡的話，會變成很淡的錶盤配一圈全黑的陰影。alphaValue 會連陰影一起淡。
        .onAppear { postFade() }
        .onChange(of: isFaded) { postFade() }
        .onHover { ui.hovering = $0 }
        // 只在提醒中才吃點擊，平常拖曳圓盤的行為不受影響
        .onTapGesture { if model.alerting { model.acknowledge() } }
        // 附屬模式下沒有 Dock 圖示也沒有選單列，右鍵選單是確保隨時出得去的後路
        .contextMenu {
            if model.alerting {
                Button("停止提醒") { model.acknowledge() }
                Divider()
            }
            Button(model.running ? "暫停" : "開始") { model.toggle() }
            Button(prefs.timerMode == .stopwatch ? "歸零" : "重設這一段") { model.reset() }
            if model.canLogProgress {
                Button("結束並記下 \(model.elapsedMinutes) 分鐘") { model.logProgressAndBreak() }
            }
            Divider()
            Menu("模式") {
                ForEach(TimerMode.allCases) { m in
                    Button {
                        model.setMode(m)
                    } label: {
                        Text(prefs.timerMode == m ? "✓ \(m.label)" : m.label)
                    }
                }
            }
            // 讀書時番茄鐘是縮小的，右鍵是最順手的切換入口
            Menu("時間長度") {
                ForEach(Preset.all) { preset in
                    Button {
                        prefs.apply(preset)
                        model.syncDurationIfIdle()
                    } label: {
                        Text(prefs.activePreset == preset
                             ? "✓ \(preset.label)　\(preset.note)"
                             : "\(preset.label)　\(preset.note)")
                    }
                }
            }
            Menu("風格") {
                ForEach(DialStyle.allCases) { style in
                    Button {
                        prefs.dialStyle = style
                    } label: {
                        Text(prefs.dialStyle == style ? "✓ \(style.label)" : style.label)
                    }
                }
            }
            Divider()
            Button("放大") { prefs.compact = false }
            Button("取消浮動（顯示 Dock 圖示）") { prefs.alwaysOnTop = false }
            Divider()
            Button("結束番茄鐘") { NSApp.terminate(nil) }
        }
    }

    /// 讀書時不要太搶眼：沒有滑鼠在上面就淡下去，移過去才恢復。
    /// 但提醒中一律全亮——這是「一直漏看」的主要修法。
    private var isFaded: Bool {
        !(model.alerting || ui.hovering || !prefs.idleFade)
    }

    private func postFade() {
        NotificationCenter.default.post(name: .dialFadeChanged, object: isFaded)
    }

    private var alertWash: Double {
        guard model.alerting else { return 0 }
        return model.breath ? 0.22 : 0.10
    }

    private func compactButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}
