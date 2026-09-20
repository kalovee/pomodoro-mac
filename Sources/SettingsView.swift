import SwiftUI

/// sheet 不能比母視窗大，超過的部分會被直接切掉。
/// 所以標題和按鈕固定在上下、中間內容用 ScrollView，尺寸留餘裕。
private let sheetSize = CGSize(width: 320, height: 412)

struct SettingsView: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: PomodoroModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "設定") {
            group("時間長度") {
                presetRow
                row("專注", value: $prefs.workMin, range: 1...120, unit: "分鐘")
                row("短休息", value: $prefs.shortMin, range: 1...60, unit: "分鐘")
                row("長休息", value: $prefs.longMin, range: 1...60, unit: "分鐘")
                row("幾輪後長休息", value: $prefs.roundsPerLong, range: 2...8, unit: "輪")
            }

            group("提醒") {
                Toggle("時間到播放音效", isOn: $prefs.soundOn)
                Toggle("時間到顯示系統通知", isOn: $prefs.notifyOn)
            }
            .toggleStyle(.checkbox)

            group("鈴聲") {
                soundRow
                mySoundsHint
                row("音量", value: $prefs.alertVolume, range: 0...100, unit: "%", step: 10)
                caption("這是相對系統音量的衰減。系統音量本身太小的話，調這裡也不會變大聲。")

                choiceRow(["響固定次數", "直到按掉"],
                          selected: prefs.ringUntilAck ? 1 : 0,
                          caption: prefs.ringUntilAck
                            ? "會一直響到你按掉圓盤為止，最久 5 分鐘"
                            : "響完設定的次數就自動停止") { prefs.ringUntilAck = ($0 == 1) }

                if !prefs.ringUntilAck {
                    row("響幾聲", value: $prefs.ringCount, range: 1...20, unit: "聲")
                    row("間隔", value: $prefs.ringGap, range: 1...10, unit: "秒")
                }
            }

            group("熱鍵") {
                Toggle("啟用全域熱鍵", isOn: $prefs.globalHotkeys)
                    .toggleStyle(.checkbox)
                ForEach(Hotkeys.Action.allCases, id: \.rawValue) { action in
                    HStack {
                        Text(action.what).font(Theme.label)
                        Spacer()
                        Text(action.label)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fill))
                    }
                    .opacity(prefs.globalHotkeys ? 1 : 0.4)
                }
                caption("全域熱鍵在焦點於其他 App 時也有效，不需要任何系統權限。"
                        + "若某組鍵已被別的 App 佔用，那一組會自動跳過。")
                caption("番茄鐘視窗自己有焦點時不用按修飾鍵：空白鍵開始／暫停、"
                        + "R 重設、S 跳過、Esc 停止提醒。打字時這些鍵不會被攔截。")
            }

            group("背景音效") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("macOS 內建的白噪音").font(Theme.label)
                    Spacer(minLength: 0)
                    Button("打開系統設定") { openBackgroundSounds() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent(model.phase))
                }
                caption("雨聲、海洋、溪流和三種噪音，都是 Apple 自己的素材。"
                        + "番茄鐘沒辦法幫你自動開關——macOS 沒有提供對應的捷徑動作。")
                caption("小技巧：系統設定 → 控制中心 → 聽力，設成「在選單列中顯示」，"
                        + "之後就能一鍵開關。")
            }

            group("休息遮罩") {
                choiceRow(OverlayMode.allCases.map(\.label),
                          selected: OverlayMode.allCases.firstIndex(of: prefs.overlayMode) ?? 1,
                          caption: prefs.overlayMode.note) {
                    prefs.overlayMode = OverlayMode.allCases[$0]
                }
            }

            group("行為") {
                Toggle("浮在最上層（全螢幕 App 上也顯示）", isOn: $prefs.alwaysOnTop)
                Toggle("時間到自動接下一段", isOn: $prefs.autoContinue)
                Toggle("浮動時隱藏 Dock 圖示", isOn: $prefs.hideDock)
                Toggle("縮小時閒置變半透明", isOn: $prefs.idleFade)
            }
            .toggleStyle(.checkbox)
        } footer: {
            Button("恢復預設") {
                prefs.restoreDefaults()
                model.syncDurationIfIdle()
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// 常用組合，點一下四個數字一起換
    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(Preset.all.enumerated()), id: \.element.id) { index, preset in
                    let active = prefs.activePreset == preset
                    Button {
                        prefs.apply(preset)
                        model.syncDurationIfIdle()
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(active ? .white : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(
                                Capsule().fill(active ? Theme.accent(model.phase) : Theme.fill)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("\(preset.note)　⌘\(index + 1)")
                }
            }
            Text(prefs.activePreset.map { "\($0.note)．鍵盤 ⌘1 – ⌘4 可直接切換" } ?? "自訂")
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 4)
    }

    /// 鈴聲選擇 + 試聽。試聽走跟真實響鈴同一條路徑與同一個音量，
    /// 才不會發生「試聽聽得到、真的響起來卻沒聲音」。
    private var soundRow: some View {
        HStack {
            Text("鈴聲").font(Theme.label)
            Spacer()
            Picker("", selection: $prefs.alertSound) {
                // 中文描述擺前面：真正幫使用者選的是它，
                // 英文檔名放後面，被截斷也不影響判斷
                let mine = Alarm.userSounds()
                if mine.isEmpty {
                    ForEach(Alarm.builtIn) { sound in
                        Text("\(sound.note) \(sound.name)").tag(sound.name)
                    }
                } else {
                    Section("系統") {
                        ForEach(Alarm.builtIn) { sound in
                            Text("\(sound.note) \(sound.name)").tag(sound.name)
                        }
                    }
                    Section("我的") {
                        ForEach(mine) { sound in
                            Text(sound.name).tag(sound.name)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 168)

            Button {
                Alarm.shared.preview(sound: prefs.alertSound, volume: prefs.alertVolume)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help("試聽")
        }
    }

    /// 直接跳到輔助使用的音訊面板，背景音效就在那裡。
    /// 比叫使用者自己在系統設定裡翻快得多。
    private func openBackgroundSounds() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Audio")!
        NSWorkspace.shared.open(url)
    }

    /// 指向 macOS 官方的音效擴充點。丟檔案進去就會出現在上面的選單裡。
    private var mySoundsHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            caption("想要更多聲音？把音檔丟進「使用者音效」資料夾就會出現在上面。")
            Spacer(minLength: 0)
            Button("打開") {
                let dir = Alarm.userSoundsDirectory
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.accent(model.phase))
        }
    }

    /// 幾選一的膠囊列。視覺沿用 presetRow，但那邊另外帶 ⌘N 提示，所以不共用。
    private func choiceRow(_ labels: [String], selected: Int,
                           caption text: String, pick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    let active = index == selected
                    Button { pick(index) } label: {
                        Text(label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(active ? .white : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Capsule().fill(active ? Theme.accent(model.phase) : Theme.fill))
                    }
                    .buttonStyle(.plain)
                }
            }
            caption(text)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content()
        }
        .padding(.bottom, 18)
    }

    private func row(_ label: String, value: Binding<Int>,
                     range: ClosedRange<Int>, unit: String, step: Int = 1) -> some View {
        HStack {
            Text(label).font(Theme.label)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) \(unit)")
                    .font(Theme.label)
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize()
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: PomodoroModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "完成紀錄",
                   accessory: "今日 \(model.todayCount) 個 · 專注 \(model.todayMinutes) 分鐘") {
            if model.history.isEmpty {
                VStack(spacing: 6) {
                    Text("還沒有完成的番茄鐘")
                        .font(Theme.label)
                        .foregroundStyle(Theme.muted)
                    Text("完成一段專注後就會記在這裡")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.muted.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.historyByDay) { day in
                        HStack(alignment: .firstTextBaseline) {
                            Text(day.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                            Spacer(minLength: 8)
                            Text(day.summary)
                                .font(Theme.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.muted.opacity(0.75))
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                        ForEach(day.sessions) { s in
                            HStack(alignment: .firstTextBaseline) {
                                Text(s.task)
                                    .font(Theme.label)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 10)
                                Text("\(s.minutes) 分")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.muted.opacity(0.7))
                                Text(clock(s.finishedAt))
                                    .font(Theme.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
            }
        } footer: {
            Button("清除紀錄") { model.clearHistory() }
                .disabled(model.history.isEmpty && model.todayCount == 0)
            Spacer()
            Button("關閉") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// 日期已經是分組的標題了，每一列只要時間
    private func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// 兩個 sheet 共用的外框：標題固定在上、按鈕固定在下、中間可捲動。
private struct SheetFrame<Content: View, Footer: View>: View {
    let title: String
    var accessory: String? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let accessory {
                    Text(accessory)
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack { footer() }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(Theme.ground)
    }
}
