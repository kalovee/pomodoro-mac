import AppKit

/// 進入點。沒有用 SwiftUI 的 App／WindowGroup——視窗是 NSPanel，
/// 由 PanelController 自己建立與管理（原因寫在 PanelController 開頭）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var menu: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.installHandlers()
        Diagnostics.log("啟動")
        Notifier.shared.requestAuthorization()

        let controller = PanelController()
        self.controller = controller
        // 選單要在面板之後建，因為選單動作要對著它
        let menu = MenuController(panel: controller)
        menu.install()
        self.menu = menu
    }

    /// 一定要是 false。
    ///
    /// AppKit 在判斷「最後一個視窗」時不把 NSPanel 算進去，所以只要有任何視窗關閉
    /// （例如關掉設定或紀錄的 sheet），它就會認為一個視窗都不剩而結束整個 App——
    /// 使用者看到的就是毫無徵兆的閃退，而且因為是正常結束，不會留下 crash log。
    /// 結束只走一條路：使用者按紅色關閉鈕或選單的「結束番茄鐘」。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.log("結束 App，呼叫來源：", stack: true)
    }

    /// 點 Dock 圖示時把視窗叫回來
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller?.panel.orderFront(nil)
        return true
    }
}

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    // 讓 delegate 活到 App 結束
    objc_setAssociatedObject(app, "pomodoroDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.regular)
}
app.run()
