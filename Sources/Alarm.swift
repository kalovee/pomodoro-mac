import AppKit

/// 可選的提醒音效。`note` 是給使用者看的描述，免得要一個一個試聽。
struct AlertSound: Identifiable, Equatable {
    var id: String { name }
    /// 存進偏好設定的鍵，等於檔名（不含副檔名）
    let name: String
    let note: String
    /// 使用者自己丟進 ~/Library/Sounds 的
    var isMine = false
}

/// 響鈴。
///
/// 從 `Notifier` 拆出來是因為兩者本質不同：`Notifier` 是無狀態的「跟系統講一聲」，
/// 而響鈴是有狀態、可取消、要持有 `NSSound` 的東西。混在一起會變成一個類別
/// 兩種生命週期。
///
/// 舊的做法直接 `NSSound(named:)?.play()` 不留參考，所以**根本停不下來**，
/// 也沒有音量控制——那正是這次要修的。
@MainActor
final class Alarm {
    static let shared = Alarm()

    /// 內建可選的音效。前 14 個是 /System/Library/Sounds，
    /// 後面幾個來自 CoreAudio 那組系統音效庫——挑的是長度夠、聽起來像提示的，
    /// 其餘多半是零點幾秒的介面回饋音，當鬧鈴太不明顯。
    nonisolated static let builtIn: [AlertSound] = [
        AlertSound(name: "Submarine", note: "低沉聲納"),
        AlertSound(name: "Funk",      note: "低沉長聲"),
        AlertSound(name: "Basso",     note: "低音警示"),
        AlertSound(name: "Sosumi",    note: "雙聲提示"),
        AlertSound(name: "Hero",      note: "上揚提示"),
        AlertSound(name: "Glass",     note: "清亮玻璃"),
        AlertSound(name: "Ping",      note: "單聲清脆"),
        AlertSound(name: "Bottle",    note: "氣泡聲"),
        AlertSound(name: "Blow",      note: "氣音"),
        AlertSound(name: "Morse",     note: "電報聲"),
        AlertSound(name: "Purr",      note: "柔和低鳴"),
        AlertSound(name: "Frog",      note: "蛙鳴"),
        AlertSound(name: "Pop",       note: "輕點"),
        AlertSound(name: "Tink",      note: "極短輕響"),
        AlertSound(name: "Volume Mount",   note: "上揚鐘聲"),
        AlertSound(name: "Volume Unmount", note: "下降鐘聲"),
        AlertSound(name: "burn complete",  note: "完成提示"),
        AlertSound(name: "payment_success", note: "支付完成"),
        AlertSound(name: "empty trash",    note: "紙團聲"),
        AlertSound(name: "Screen Capture", note: "相機快門"),
    ]

    /// 使用者自己的音效資料夾。macOS 官方的擴充點——
    /// 丟任何 .aiff / .wav / .m4a / .mp3 進去就會出現在選單裡。
    nonisolated static let userSoundsDirectory =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds")

    nonisolated static func userSounds() -> [AlertSound] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: userSoundsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { playableExtensions.contains($0.pathExtension.lowercased()) }
            .map { AlertSound(name: $0.deletingPathExtension().lastPathComponent,
                              note: "自己加的", isMine: true) }
            .sorted { $0.name < $1.name }
    }

    /// 內建 + 使用者自己的。每次讀都重新掃描資料夾，
    /// 使用者丟了新檔案進去，打開設定就看得到，不必重開 App。
    nonisolated static var catalog: [AlertSound] { builtIn + userSounds() }

    nonisolated static let playableExtensions = ["aiff", "aif", "wav", "m4a", "caf", "mp3"]

    /// 音效檔可能在哪幾個地方。使用者自己的排最前面，同名時蓋過系統的。
    nonisolated static var searchPaths: [URL] {
        let coreAudio = URL(fileURLWithPath:
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds")
        return [
            userSoundsDirectory,
            URL(fileURLWithPath: "/System/Library/Sounds"),
            coreAudio.appendingPathComponent("system"),
            coreAudio.appendingPathComponent("finder"),
            coreAudio.appendingPathComponent("dock"),
        ]
    }

    nonisolated static func url(for name: String) -> URL? {
        for directory in searchPaths {
            for ext in playableExtensions {
                let candidate = directory.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    /// 預設挑 Submarine：14 個裡最低沉、最能穿透耳機裡正在播的音樂。
    nonisolated static let defaultSound = "Submarine"

    /// 用「檔案找得到嗎」而不是「在清單裡嗎」來驗證。
    /// 使用者自己加的音效不在內建清單裡，但一樣要能用。
    nonisolated static func isKnown(_ name: String) -> Bool {
        url(for: name) != nil
    }

    private(set) var isRinging = false
    /// 已經響了幾聲。探針靠它驗證次數與「停了之後真的不再增加」。
    private(set) var ringsPlayed = 0

    /// 安全上限。刻意不是 let：探針要能縮短它來測自停。
    ///
    /// 無上限的響鈴等於對著空房間尖叫，所以連「直到按掉」也吃這個上限。
    var maxRingSeconds: TimeInterval = 300

    /// 探針用：確認音量真的套到 NSSound 上了
    var currentVolume: Float? { sound?.volume }

    private var sound: NSSound?
    private var previewSound: NSSound?
    private var timer: Timer?
    private var startedAt: Date?
    /// 響 N 聲模式的目標次數；nil 表示「直到被叫停」
    private var limit: Int?

    private init() {}

    // MARK: 開始與停止

    func start(sound name: String, volume: Int, untilAck: Bool, count: Int, gap: TimeInterval) {
        // 響鈴不排隊：新的一段結束就直接蓋掉舊的提醒。
        // 提醒表達的是「現在的狀態」，不是一串待播清單——排隊只會讓使用者
        // 聽到早就過期的鈴聲。
        stop()

        guard let loaded = load(name) else {
            NSSound.beep()
            return
        }
        loaded.volume = Float(max(0, min(100, volume))) / 100
        sound = loaded

        isRinging = true
        ringsPlayed = 0
        startedAt = Date()
        limit = untilAck ? nil : max(1, count)

        ringOnce()
        if reachedLimit() {
            stop()
            return
        }

        let t = Timer.scheduledTimer(withTimeInterval: max(0.2, gap), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common 不是可有可無：少了它，選單打開或拖曳視窗時計時器會暫停，
        // 鈴聲剛好在使用者正在操作它的那一刻靜音。
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sound?.stop()
        isRinging = false
        startedAt = nil
        limit = nil
    }

    /// 設定頁試聽：只響一聲，不動 `isRinging`，走的是跟真實響鈴同一條路徑與音量。
    func preview(sound name: String, volume: Int) {
        previewSound?.stop()
        guard let loaded = load(name) else {
            NSSound.beep()
            return
        }
        loaded.volume = Float(max(0, min(100, volume))) / 100
        previewSound = loaded
        loaded.play()
    }

    // MARK: 內部

    private func tick() {
        guard isRinging else { return }

        if let started = startedAt, Date().timeIntervalSince(started) >= maxRingSeconds {
            stop()
            return
        }

        ringOnce()
        if reachedLimit() { stop() }
    }

    private func ringOnce() {
        guard let sound else { return }
        // 上一聲還沒播完就先停掉，不然 play() 對同一個實例不會重頭開始
        if sound.isPlaying { sound.stop() }
        sound.play()
        ringsPlayed += 1
    }

    private func reachedLimit() -> Bool {
        guard let limit else { return false }
        return ringsPlayed >= limit
    }

    private func load(_ name: String) -> NSSound? {
        // 用 URL 載入而不是 NSSound(named:)：後者會回傳系統註冊的共用實例，
        // 改它的 volume 或呼叫 play() 會跟其他使用者互相干擾，
        // 而「拿得到一個自己能停下來的實例」正是這個類別存在的理由。
        if let found = Self.url(for: name),
           let owned = NSSound(contentsOf: found, byReference: false) { return owned }
        return NSSound(named: NSSound.Name(name))
    }
}
