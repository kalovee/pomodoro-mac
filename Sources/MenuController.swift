import AppKit

/// 選單列。抽出來自成一個類別，一來 main.swift 只負責啟動流程，
/// 二來測試程式才建得出同一份選單來驗證。
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let panel: PanelController
    private var timingMenu: NSMenu?
    private var toggleItem: NSMenuItem?

    init(panel: PanelController) {
        self.panel = panel
        super.init()
    }

    func install() {
        NSApp.mainMenu = build()
    }

    func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(appItem())
        main.addItem(timingItem())
        main.addItem(editItem())
        return main
    }

    // MARK: 番茄鐘

    private func appItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "番茄鐘")
        menu.addItem(withTitle: "關於番茄鐘",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "隱藏番茄鐘",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束番茄鐘",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        return item
    }

    // MARK: 計時（時間組合）

    private func timingItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "計時")
        menu.delegate = self

        toggleItem = NSMenuItem(title: "開始", action: #selector(toggleTimer(_:)), keyEquivalent: "\r")
        toggleItem?.keyEquivalentModifierMask = [.command]
        toggleItem?.target = self
        menu.addItem(toggleItem!)

        let reset = NSMenuItem(title: "重設這一段", action: #selector(resetPhase(_:)), keyEquivalent: "r")
        reset.target = self
        menu.addItem(reset)

        let skip = NSMenuItem(title: "跳過這一段", action: #selector(skipPhase(_:)), keyEquivalent: "s")
        skip.keyEquivalentModifierMask = [.command, .shift]
        skip.target = self
        menu.addItem(skip)

        menu.addItem(.separator())

        for (i, preset) in Preset.all.enumerated() {
            let entry = NSMenuItem(title: "\(preset.label)　\(preset.note)",
                                   action: #selector(applyPreset(_:)),
                                   keyEquivalent: "\(i + 1)")
            entry.tag = i
            entry.target = self
            menu.addItem(entry)
        }
        item.submenu = menu
        timingMenu = menu
        return item
    }

    @objc func toggleTimer(_ sender: NSMenuItem) { panel.model.toggle() }
    @objc func resetPhase(_ sender: NSMenuItem) { panel.model.reset() }
    @objc func skipPhase(_ sender: NSMenuItem) { panel.model.skip() }

    @objc func applyPreset(_ sender: NSMenuItem) {
        guard Preset.all.indices.contains(sender.tag) else { return }
        panel.prefs.apply(Preset.all[sender.tag])
        panel.model.syncDurationIfIdle()
    }

    /// 選單打開時標記目前用的是哪一組，並更新開始／暫停的字。
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === timingMenu else { return }
        toggleItem?.title = panel.model.running ? "暫停" : "開始"

        let active = panel.prefs.activePreset
        // 只看時間組合那幾項。用 action 判斷而不是 tag——
        // 控制項的 tag 預設是 0，會跟第一組預設撞在一起。
        for entry in menu.items where entry.action == #selector(applyPreset(_:)) {
            guard Preset.all.indices.contains(entry.tag) else { continue }
            entry.state = (active == Preset.all[entry.tag]) ? .on : .off
        }
    }

    // MARK: 編輯（文字欄位需要，不然不能剪下貼上）

    private func editItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "編輯")
        menu.addItem(withTitle: "復原", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪下", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "複製", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "貼上", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = menu
        return item
    }
}
