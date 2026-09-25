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
}

extension Notification.Name {
    /// 縮小模式的錶盤要不要淡出。object 是 Bool。
    static let dialFadeChanged = Notification.Name("dialFadeChanged")
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
        .background(prefs.compact ? Color.clear : Theme.ground)
        .clipped()
        // 必須放在 .clipped() 之後：SwiftUI 會為標題列留一塊安全區，
        // 內容和底色只鋪在安全區內，最上面 20pt 會是沒畫到的透明帶。
        // 放在 clipped 前面的話會被它切回去。
        .ignoresSafeArea()
        .animation(.easeInOut(duration: Metrics.morph), value: prefs.compact)
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
            topBar
            dial.padding(.top, 2)
            taskField.padding(.top, 18)
            controls.padding(.top, 14)
            logProgress
            Spacer(minLength: 12)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer.padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
        // 不寫死高度：拿到多少就用多少，視窗內容區跟設計值有落差時才不會被裁掉
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .animation(.easeInOut(duration: 0.28), value: model.phase)
        .sheet(isPresented: $ui.showSettings) { SettingsView() }
        .sheet(isPresented: $ui.showHistory) { HistoryView() }
        .onChange(of: prefs.workMin) { model.syncDurationIfIdle() }
        .onChange(of: prefs.shortMin) { model.syncDurationIfIdle() }
        .onChange(of: prefs.longMin) { model.syncDurationIfIdle() }
    }

    // 上排：釘選 / 縮小。兩個都是「視窗怎麼待在桌面上」的控制，放在一起。
    // 靠右擺，左上角留給系統的紅綠燈按鈕。
    private var topBar: some View {
        HStack(spacing: 2) {
            Spacer()
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
        .frame(height: 22)
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
        .frame(height: 222)
        .animation(.easeInOut(duration: Metrics.pulse), value: model.breath)
        .contentShape(Rectangle())
        .onTapGesture { if model.alerting { model.acknowledge() } }
    }

    private var taskField: some View {
        TextField("正在做什麼？", text: $model.task)
            .textFieldStyle(.plain)
            .font(Theme.label)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .focused($taskFocused)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(taskFocused ? tint.opacity(0.55) : Theme.hairline,
                                    lineWidth: taskFocused ? 1.5 : 1)
                    )
            )
            .onSubmit { taskFocused = false }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            circleButton("arrow.counterclockwise", help: "重設這一段") { model.reset() }

            Button {
                taskFocused = false
                model.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(model.running ? "暫停" : "開始")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            // ⌘↩ 交給選單列處理：縮小模式沒有這顆按鈕，
            // 放在選單才是兩種模式都有效，也不會兩邊搶同一組鍵。
            circleButton("forward.end.fill", help: "跳過這一段") { model.skip() }
        }
    }

    /// 只有真的累積到一分鐘以上才出現。
    /// 放在按鈕下方本來就空著的那塊，不必為它挪版面。
    @ViewBuilder
    private var logProgress: some View {
        if model.canLogProgress {
            Button { model.logProgressAndBreak() } label: {
                Text("結束並記下 \(model.elapsedMinutes) 分鐘")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(tint.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("把已經專注的時間記進紀錄，然後進入休息")
            .padding(.top, 12)
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
            .buttonStyle(.plain)
            .help("查看完成紀錄")

            Spacer()

            ghostButton("gearshape", active: false, tint: tint, help: "設定") {
                ui.showSettings = true
            }
        }
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
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.fill))
        }
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
            }
            // 只內縮不放大：外層有 .clipped()，放大的部分會被切在視窗邊緣
            .scaleEffect(model.alerting && model.breath ? 0.96 : 1)

            // 滑鼠移上去才出現控制項，平常只剩計時器本身
            HStack(spacing: 8) {
                compactButton(model.running ? "pause.fill" : "play.fill") { model.toggle() }
                compactButton("arrow.up.left.and.arrow.down.right") { prefs.compact = false }
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
            Button("重設這一段") { model.reset() }
            if model.canLogProgress {
                Button("結束並記下 \(model.elapsedMinutes) 分鐘") { model.logProgressAndBreak() }
            }
            Divider()
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
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.fill))
        }
        .buttonStyle(.plain)
    }
}
