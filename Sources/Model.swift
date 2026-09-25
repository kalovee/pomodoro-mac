import SwiftUI

// MARK: - 階段

enum Phase: String, Codable, CaseIterable {
    case work, shortBreak, longBreak

    var title: String {
        switch self {
        case .work: return "專注"
        case .shortBreak: return "短休息"
        case .longBreak: return "長休息"
        }
    }

    var tint: Color {
        switch self {
        case .work: return Color(red: 0.91, green: 0.31, blue: 0.27)
        case .shortBreak: return Color(red: 0.20, green: 0.68, blue: 0.53)
        case .longBreak: return Color(red: 0.24, green: 0.53, blue: 0.85)
        }
    }

    var isBreak: Bool { self != .work }
}

// MARK: - 已完成紀錄

struct Session: Codable, Identifiable {
    var id = UUID()
    var finishedAt: Date
    var task: String
    var minutes: Int
}

/// 一天的紀錄。紀錄頁按日期分組，不然幾天之後就是一長串看不出段落的清單。
struct DaySummary: Identifiable {
    let day: Date
    let sessions: [Session]

    var id: Date { day }
    var count: Int { sessions.count }
    var minutes: Int { sessions.reduce(0) { $0 + $1.minutes } }

    /// 今天／昨天用相對說法，其餘給月日和星期——
    /// 「9月18日 週四」比「2026-09-18」好對上記憶。
    var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant")
        formatter.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
            ? "M月d日 EEE" : "yyyy年M月d日 EEE"
        return formatter.string(from: day)
    }

    var summary: String {
        minutes >= 60
            ? "\(count) 個 · \(minutes / 60) 小時 \(minutes % 60) 分"
            : "\(count) 個 · \(minutes) 分鐘"
    }
}

// MARK: - 時間組合

/// 常用的專注／休息組合。切換時四個欄位一起換，行為才可預期。
struct Preset: Identifiable, Equatable {
    var id: String { label }
    let label: String          // 使用者認得的寫法，例如「50 / 10」
    let note: String           // 適合什麼情境
    let work: Int
    let short: Int
    let long: Int
    let rounds: Int

    static let all: [Preset] = [
        Preset(label: "25 / 5",  note: "經典番茄鐘",   work: 25, short: 5,  long: 15, rounds: 4),
        Preset(label: "30 / 10", note: "稍長一點",     work: 30, short: 10, long: 20, rounds: 4),
        Preset(label: "50 / 10", note: "一節課",       work: 50, short: 10, long: 20, rounds: 3),
        Preset(label: "90 / 20", note: "深度工作",     work: 90, short: 20, long: 30, rounds: 2),
    ]
}

// MARK: - 休息遮罩

/// 遮罩要在什麼時候出現。三態而不是開關，是因為「休息時遮罩」這句話
/// 可以解讀成「休息開始時」或「每一段結束都遮」，做成選項就不必猜。
enum OverlayMode: String, CaseIterable, Identifiable {
    case off, breakStart, every
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "關閉"
        case .breakStart: return "休息開始時"
        case .every: return "每段結束"
        }
    }

    var note: String {
        switch self {
        case .off: return "不使用全螢幕遮罩"
        case .breakStart: return "專注結束、該休息時蓋住畫面"
        case .every: return "專注與休息結束都蓋住畫面"
        }
    }
}

// MARK: - 偏好設定

final class Prefs: ObservableObject {
    private let d = UserDefaults.standard

    @Published var workMin: Int      { didSet { d.set(workMin, forKey: "workMin") } }
    @Published var shortMin: Int     { didSet { d.set(shortMin, forKey: "shortMin") } }
    @Published var longMin: Int      { didSet { d.set(longMin, forKey: "longMin") } }
    @Published var roundsPerLong: Int { didSet { d.set(roundsPerLong, forKey: "roundsPerLong") } }
    @Published var soundOn: Bool     { didSet { d.set(soundOn, forKey: "soundOn") } }
    @Published var notifyOn: Bool    { didSet { d.set(notifyOn, forKey: "notifyOn") } }
    @Published var alwaysOnTop: Bool { didSet { d.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var autoContinue: Bool { didSet { d.set(autoContinue, forKey: "autoContinue") } }
    @Published var compact: Bool     { didSet { d.set(compact, forKey: "compact") } }
    @Published var hideDock: Bool    { didSet { d.set(hideDock, forKey: "hideDock") } }
    @Published var idleFade: Bool    { didSet { d.set(idleFade, forKey: "idleFade") } }

    // 提醒
    @Published var alertSound: String { didSet { d.set(alertSound, forKey: "alertSound") } }
    @Published var alertVolume: Int   { didSet { d.set(alertVolume, forKey: "alertVolume") } }
    @Published var ringUntilAck: Bool { didSet { d.set(ringUntilAck, forKey: "ringUntilAck") } }
    @Published var ringCount: Int     { didSet { d.set(ringCount, forKey: "ringCount") } }
    @Published var ringGap: Int       { didSet { d.set(ringGap, forKey: "ringGap") } }
    @Published var globalHotkeys: Bool { didSet { d.set(globalHotkeys, forKey: "globalHotkeys") } }
    @Published var dialStyle: DialStyle {
        didSet { d.set(dialStyle.rawValue, forKey: "dialStyle") }
    }
    @Published var overlayMode: OverlayMode {
        didSet { d.set(overlayMode.rawValue, forKey: "overlayMode") }
    }

    init() {
        d.register(defaults: [
            "workMin": 25, "shortMin": 5, "longMin": 15,
            "roundsPerLong": 4, "soundOn": true, "notifyOn": true,
            "alwaysOnTop": false, "autoContinue": false, "compact": false,
            "hideDock": true, "idleFade": true,
            "alertSound": Alarm.defaultSound, "alertVolume": 80,
            "ringUntilAck": false, "ringCount": 5, "ringGap": 2,
            "overlayMode": OverlayMode.breakStart.rawValue,
            "globalHotkeys": true,
            "dialStyle": DialStyle.classic.rawValue,
        ])
        workMin = d.integer(forKey: "workMin")
        shortMin = d.integer(forKey: "shortMin")
        longMin = d.integer(forKey: "longMin")
        roundsPerLong = d.integer(forKey: "roundsPerLong")
        soundOn = d.bool(forKey: "soundOn")
        notifyOn = d.bool(forKey: "notifyOn")
        alwaysOnTop = d.bool(forKey: "alwaysOnTop")
        autoContinue = d.bool(forKey: "autoContinue")
        compact = d.bool(forKey: "compact")
        hideDock = d.bool(forKey: "hideDock")
        idleFade = d.bool(forKey: "idleFade")

        // 這兩個要防禦性讀回。失效的音效名稱會變成一個安靜的鬧鈴，
        // 而那正是這整組功能要消滅的 bug。
        let savedSound = d.string(forKey: "alertSound") ?? ""
        alertSound = Alarm.isKnown(savedSound) ? savedSound : Alarm.defaultSound
        overlayMode = OverlayMode(rawValue: d.string(forKey: "overlayMode") ?? "") ?? .breakStart

        alertVolume = d.integer(forKey: "alertVolume")
        ringUntilAck = d.bool(forKey: "ringUntilAck")
        ringCount = d.integer(forKey: "ringCount")
        ringGap = d.integer(forKey: "ringGap")
        globalHotkeys = d.bool(forKey: "globalHotkeys")
        dialStyle = DialStyle(rawValue: d.string(forKey: "dialStyle") ?? "") ?? .classic
    }

    func minutes(for phase: Phase) -> Int {
        switch phase {
        case .work: return workMin
        case .shortBreak: return shortMin
        case .longBreak: return longMin
        }
    }

    /// 目前的設定剛好等於哪一組預設；都不符合就是自訂
    var activePreset: Preset? {
        Preset.all.first {
            $0.work == workMin && $0.short == shortMin
                && $0.long == longMin && $0.rounds == roundsPerLong
        }
    }

    func apply(_ preset: Preset) {
        workMin = preset.work
        shortMin = preset.short
        longMin = preset.long
        roundsPerLong = preset.rounds
    }

    func restoreDefaults() {
        workMin = 25; shortMin = 5; longMin = 15
        roundsPerLong = 4; soundOn = true; notifyOn = true
        alwaysOnTop = false; autoContinue = false
        hideDock = true; idleFade = true
        alertSound = Alarm.defaultSound; alertVolume = 80
        ringUntilAck = false; ringCount = 5; ringGap = 2
        overlayMode = .breakStart
        globalHotkeys = true
        // 注意：compact 和 dialStyle 刻意不重設——視窗模式和外觀是個人選擇，
        // 「恢復預設」是給計時與提醒用的——使用者的視窗模式不該被「恢復預設」改掉
    }
}

// MARK: - 計時器主體

@MainActor
final class PomodoroModel: ObservableObject {
    @Published private(set) var phase: Phase = .work
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var running = false
    /// 這一組長休息週期內，已完成的專注輪數（0 ..< roundsPerLong）
    @Published private(set) var roundInCycle = 0
    @Published private(set) var history: [Session] = []
    @Published var task = ""

    /// 時間到了但使用者還沒表示看到。聲音有長度上限，這個沒有——
    /// 一個你沒聽到的鈴聲再長也是沒聽到，但三分鐘後還在脈動的圓盤，
    /// 下次瞄到角落就會發現。
    @Published private(set) var alerting = false
    /// 剛結束的是哪一段。不能用 phase 判斷，因為發提醒時 phase 已經是下一段了。
    @Published private(set) var alertFinished: Phase?

    /// 提醒脈動的相位，每 Metrics.pulse 秒翻一次。
    ///
    /// 放在 model 而不是各自的 view，是因為原本的做法有兩個毛病，
    /// 合起來就是「有時候會呼吸、有時候不會」：
    ///
    /// 1. 兩個模式各有自己的 ViewState，而且只掛 onChange。切換縮小／完整時
    ///    整個 view 會重建，onChange 不會為「已經是 true 的值」觸發，
    ///    新的 view 就再也不會開始呼吸。
    /// 2. 在同一個 runloop 裡先設 false 再設 true，SwiftUI 會把更新合併，
    ///    可能只看到最終值而認為沒有變化，repeatForever 就不啟動。
    ///
    /// 改成單一來源加明確的計時器之後，兩個模式共用同一個相位，
    /// 切換模式不會中斷，也不依賴 SwiftUI 動畫的啟動時機。
    @Published private(set) var breath = false

    /// 自動接下一段最多等多久才自己開始
    static let autoContinueGrace: TimeInterval = 300

    let prefs: Prefs
    private var endDate: Date?
    private var ticker: Timer?
    private var graceTimer: Timer?
    private var breathTimer: Timer?
    private let d = UserDefaults.standard

    init(prefs: Prefs) {
        self.prefs = prefs
        loadHistory()
        remaining = TimeInterval(prefs.minutes(for: .work) * 60)
    }

    // 目前階段的總長度，用來畫進度環
    var total: TimeInterval {
        max(1, TimeInterval(prefs.minutes(for: phase) * 60))
    }

    var progress: Double {
        min(1, max(0, 1 - remaining / total))
    }

    var clock: String {
        let s = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: 控制

    func toggle() { running ? pause() : start() }

    func start() {
        clearAlert()
        beginCountdown()
    }

    /// 真正開始倒數。
    ///
    /// 跟公開的 start() 分開是必要的：start() 會先清掉提醒，
    /// 而自動接下一段如果走 start()，就會在提醒升起的下一行把它關掉——
    /// 使用者什麼都沒看到，看起來就像功能沒做出來。
    private func beginCountdown() {
        guard !running else { return }
        if remaining <= 0 { remaining = total }
        endDate = Date().addingTimeInterval(remaining)
        running = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    func pause() {
        clearAlert()
        guard running else { return }
        remaining = max(0, endDate?.timeIntervalSinceNow ?? remaining)
        stopTicker()
    }

    /// 重設目前這一段（不動輪數與今日統計）
    func reset() {
        clearAlert()
        stopTicker()
        remaining = total
    }

    /// 跳過目前這一段，直接進入下一段（不計入完成數）
    func skip() {
        clearAlert()
        stopTicker()
        advance(countAsDone: false)
    }

    /// 把輪數與今日統計歸零
    func resetCycle() {
        clearAlert()
        stopTicker()
        phase = .work
        roundInCycle = 0
        remaining = total
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        running = false
        endDate = nil
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            stopTicker()
            complete()
        } else if Int(left) != Int(remaining) {
            // 只在「顯示出來的秒數」真的改變時才發佈。
            // 每 0.2 秒發佈一次會讓整個畫面以 5Hz 重畫，而浮在全螢幕 App
            // 上面的視窗每次重畫都要重新合成——這是頓挫的主因之一。
            // 內部仍然每 0.2 秒檢查，所以「時間到」的判定精度不變。
            remaining = left
        }
    }

    // MARK: 記錄進度

    /// 這一段已經專注了幾分鐘。
    ///
    /// `remaining` 只在計時中減少，所以 `total - remaining` 就是實際專注的時間——
    /// 中間暫停多久都不會被算進去。
    var elapsedMinutes: Int {
        max(0, Int(((total - remaining) / 60).rounded()))
    }

    /// 有沒有東西可以記。專注段、而且至少滿一分鐘。
    var canLogProgress: Bool {
        phase == .work && elapsedMinutes >= 1
    }

    /// 提前結束這一段，但把已經專注的時間記進紀錄，然後進入休息。
    ///
    /// 跟 skip() 的差別就在這裡：skip 是「這段不算」，這個是「這段算，只是提早收」。
    /// 兩個動作分開，語意才不會混在一起。
    func logProgressAndBreak() {
        guard canLogProgress else { return }
        let minutes = elapsedMinutes
        let label = task.trimmingCharacters(in: .whitespacesAndNewlines)

        clearAlert()
        stopTicker()
        record(minutes: minutes, task: label)
        advance(countAsDone: true)
    }

    private func record(minutes: Int, task label: String) {
        history.insert(
            Session(finishedAt: Date(),
                    task: label.isEmpty ? "未命名" : label,
                    minutes: minutes),
            at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        saveHistory()
    }

    // MARK: 提醒

    /// 使用者表示「我看到了」。
    ///
    /// 在自動接下一段模式下，這也是下一段真正開始的時機——因為使用者選的行為是
    /// 「等按掉才開始」，這樣漏聽的那幾分鐘才不會從休息時間扣掉。
    func acknowledge() {
        guard alerting else { return }
        clearAlert()
        if prefs.autoContinue { beginCountdown() }
    }

    /// 只清掉提醒本身，不碰計時。
    /// 給 pause / reset / skip 這類本來就會自己決定計時狀態的動作用。
    private func clearAlert() {
        graceTimer?.invalidate()
        graceTimer = nil
        stopBreathing()
        Alarm.shared.stop()
        guard alerting else { return }
        alerting = false
        alertFinished = nil
    }

    private func raiseAlert(finished: Phase, task label: String) {
        alerting = true
        alertFinished = finished
        startBreathing()

        if prefs.soundOn {
            Alarm.shared.start(sound: prefs.alertSound,
                               volume: prefs.alertVolume,
                               untilAck: prefs.ringUntilAck,
                               count: prefs.ringCount,
                               gap: TimeInterval(prefs.ringGap))
        }

        Notifier.shared.fire(finished: finished,
                             next: phase,
                             task: label,
                             notify: prefs.notifyOn)

        // 自動接下一段不再立刻開始，改成等使用者確認；但排一個逾時，
        // 免得使用者離開一小時回來發現番茄鐘整個停在原地。
        guard prefs.autoContinue else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.autoContinueGrace, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.acknowledge() }
        }
        RunLoop.main.add(t, forMode: .common)
        graceTimer = t
    }

    private func startBreathing() {
        breathTimer?.invalidate()
        breath = true
        let t = Timer.scheduledTimer(withTimeInterval: Metrics.pulse, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.breath.toggle() }
        }
        // .common：選單打開或拖曳視窗時脈動不該停住
        RunLoop.main.add(t, forMode: .common)
        breathTimer = t
    }

    private func stopBreathing() {
        breathTimer?.invalidate()
        breathTimer = nil
        breath = false
    }

    // MARK: 一段結束

    /// 刻意不是 private：探針要能直接觸發一段結束，
    /// 否則每個測試都得真的等完一整段時間。
    func complete() {
        let finished = phase
        let label = task.trimmingCharacters(in: .whitespacesAndNewlines)

        if finished == .work {
            record(minutes: prefs.workMin, task: label)
        }

        advance(countAsDone: true)

        raiseAlert(finished: finished, task: label)
    }

    /// 決定下一個階段
    private func advance(countAsDone: Bool) {
        switch phase {
        case .work:
            if countAsDone { roundInCycle += 1 }
            if roundInCycle >= prefs.roundsPerLong {
                roundInCycle = 0
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        case .shortBreak, .longBreak:
            phase = .work
        }
        remaining = total
    }

    /// 今日完成的番茄數。
    ///
    /// 從紀錄推導而不是另外存一份：原本存成獨立的 todayCount，
    /// 而「跨日歸零」只在 App 啟動時判斷一次——讀書過了午夜的話，
    /// 數字會從前一天累積下去不會歸零。推導就沒有這個問題，
    /// 也不會跟同一頁的分鐘數對不起來（那個本來就是推導的）。
    var todayCount: Int {
        history.filter { Calendar.current.isDateInToday($0.finishedAt) }.count
    }

    /// 紀錄按日期歸納，新的在前面。
    var historyByDay: [DaySummary] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: history) { calendar.startOfDay(for: $0.finishedAt) }
        return groups.keys.sorted(by: >).map { day in
            DaySummary(day: day,
                       sessions: (groups[day] ?? []).sorted { $0.finishedAt > $1.finishedAt })
        }
    }

    /// 今日累積的專注分鐘數
    var todayMinutes: Int {
        history.filter { Calendar.current.isDateInToday($0.finishedAt) }
               .reduce(0) { $0 + $1.minutes }
    }

    // MARK: 設定變更時同步

    /// 使用者在設定裡改了時長：沒在跑的話就直接套用新長度
    func syncDurationIfIdle() {
        guard !running else { return }
        remaining = total
    }

    // MARK: 儲存

    private func loadHistory() {
        guard let data = d.data(forKey: "history"),
              let list = try? JSONDecoder().decode([Session].self, from: data) else { return }
        history = list
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            d.set(data, forKey: "history")
        }
    }

    func clearHistory() {
        history = []
        saveHistory()
    }
}
