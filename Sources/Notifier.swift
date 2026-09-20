import AppKit
import UserNotifications

/// 時間到的系統通知。
///
/// 發聲已經移到 `Alarm`：響鈴需要狀態、要能停、要能調音量，
/// 而這個類別是無狀態的「跟系統講一聲」，混在一起會變成一個類別兩種生命週期。
///
/// 通知權限若拿不到（例如沒簽章或使用者拒絕），改用 osascript 送一則通知當備援。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var authorized = false
    private var asked = false

    func requestAuthorization() {
        guard !asked else { return }
        asked = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func fire(finished: Phase, next: Phase, task: String, notify: Bool) {
        let title: String
        let body: String
        switch finished {
        case .work:
            title = "🍅 專注結束"
            body = task.isEmpty
                ? "休息一下，接下來是\(next.title)。"
                : "「\(task)」完成一輪，接下來是\(next.title)。"
        case .shortBreak, .longBreak:
            title = "☕️ \(finished.title)結束"
            body = "回來工作吧，下一段是\(next.title)。"
        }

        if notify { post(title: title, body: body) }
    }

    private func post(title: String, body: String) {
        guard authorized else { return fallback(title: title, body: body) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 使用者讀書時多半開著專心模式，那會整個吞掉一般通知。
        content.interruptionLevel = .timeSensitive
        // content.sound 刻意留 nil：響鈴由 Alarm 負責，兩邊都出聲會互相踩。
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if error != nil { self.fallback(title: title, body: body) }
        }
    }

    /// 備援：透過 osascript 發通知，不需要通知權限。
    private func fallback(title: String, body: String) {
        let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "\\\"") }
        let script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    /// App 在前景時也要顯示通知橫幅
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }
}
