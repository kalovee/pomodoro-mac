import AppKit
import SwiftUI
import Combine

/// 視窗由這裡自己管，不用 SwiftUI 的 WindowGroup。
///
/// 原因：浮動小工具需要的是 NSPanel。用 WindowGroup 的話，
/// 視窗一旦被文字輸入搶成 key window，系統會把 App 拉回它原本的 Space，
/// 而且 SwiftUI 會重設我們設過的視窗屬性——只能在畫面更新時補回去，
/// 使用者一停止打字就沒機會補，視窗就「卡」在主桌面了。
///
/// NSPanel 的 .nonactivatingPanel 讓人可以操作視窗而不會啟動 App、不會換 Space；
/// 自己持有視窗也代表尺寸完全由我們決定，不用再跟 hosting view 搶。
/// NSPanel 預設按 Esc 會關閉視窗（cancelOperation）。
/// 對常駐的桌面小工具來說，那等於整個 App 消失——因為最後一個視窗關掉就會結束。
/// 這裡把 Esc 改成只取消文字欄位的焦點。
final class FloatingPanel: NSPanel {
    /// 縮小模式整個圓盤都是 SwiftUI 內容，不是 AppKit 眼中的「視窗背景」，
    /// 因此 isMovableByWindowBackground 會收不到拖曳。在面板層追蹤鼠標，
    /// 只有真正移動時才改視窗位置；單純點一下仍交給 SwiftUI 按鈕處理。
    var compactDragEnabled = false
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    /// 這次按下之後有沒有真的拖動過。小於門檻的晃動仍算點擊。
    private var didDrag = false
    private let dragThreshold: CGFloat = 3
    /// 游標的螢幕座標。平常就是 NSEvent.mouseLocation；
    /// 留成可替換的，是因為探針送的合成事件不會移動真正的游標，不替換就測不到拖曳。
    var screenMouseLocation: () -> NSPoint = { NSEvent.mouseLocation }

    /// 視窗自己有焦點時的按鍵。回傳 true 表示已處理。
    var onKey: ((NSEvent) -> Bool)?
    /// Esc：優先用來停掉提醒，其次才是取消文字欄位的焦點。
    var onCancel: (() -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        makeFirstResponder(nil)
    }

    override func keyDown(with event: NSEvent) {
        // 正在打字就整個讓開，不然空白鍵打不出空格、R 和 S 也輸入不了
        if firstResponder is NSTextView {
            super.keyDown(with: event)
            return
        }
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        guard compactDragEnabled else {
            super.sendEvent(event)
            return
        }

        switch event.type {
        case .leftMouseDown:
            dragStartMouse = screenMouseLocation()
            dragStartOrigin = frame.origin
            didDrag = false
            super.sendEvent(event)

        case .leftMouseDragged:
            guard let startMouse = dragStartMouse,
                  let startOrigin = dragStartOrigin else {
                super.sendEvent(event)
                return
            }
            let now = screenMouseLocation()
            let dx = now.x - startMouse.x, dy = now.y - startMouse.y
            // 小於門檻的晃動不算拖曳，維持它是一次點擊
            guard didDrag || hypot(dx, dy) >= dragThreshold else { return }
            didDrag = true
            setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))

        case .leftMouseUp:
            defer {
                dragStartMouse = nil
                dragStartOrigin = nil
                didDrag = false
            }
            // 拖過的話，不能把放開事件原樣交給 SwiftUI。
            // 視窗是跟著游標一起移動的，放開時游標在視窗內的座標跟按下時幾乎一樣，
            // SwiftUI 會看成「原地按下、原地放開」＝一次點擊——提醒中拖一下就被誤確認，
            // 從懸停按鈕上開始拖也會誤按。把放開點改到視窗外面，SwiftUI 就會當成
            // 「按下後拖出去」而取消，不觸發任何點擊。
            if didDrag,
               let cancelled = NSEvent.mouseEvent(
                    with: .leftMouseUp,
                    location: NSPoint(x: -10_000, y: -10_000),
                    modifierFlags: event.modifierFlags,
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    eventNumber: event.eventNumber,
                    clickCount: event.clickCount,
                    pressure: event.pressure) {
                super.sendEvent(cancelled)
                return
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    // 無邊框的 panel 預設不能成為 key window，但打字需要
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController: NSObject {
    let prefs: Prefs
    let model: PomodoroModel
    let panel: FloatingPanel

    private var bag = Set<AnyCancellable>()
    /// 休息遮罩。由這裡持有，生命週期跟著面板走。
    private var overlay: OverlayController?

    /// 探針用：目前掛著的遮罩視窗
    var overlayPanels: [NSWindow] { overlay?.visiblePanels ?? [] }

    override init() {
        let prefs = Prefs()
        self.prefs = prefs
        self.model = PomodoroModel(prefs: prefs)

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.full),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        super.init()

        let hosting = NSHostingView(rootView:
            ContentView()
                .environmentObject(model)
                .environmentObject(prefs))
        // 關鍵：不讓 hosting view 反過來決定視窗尺寸，
        // 否則它會把視窗撐成「內容 + 標題列」，縮放結尾就會彈一下。
        hosting.sizingOptions = []
        panel.contentView = hosting

        panel.hidesOnDeactivate = false      // NSPanel 預設會在 App 失焦時隱藏
        panel.becomesKeyOnlyIfNeeded = true  // 只有要打字時才搶 key，點按鈕不會
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        overlay = OverlayController(model: model, prefs: prefs)
        wireKeys()

        observePrefs()
        observeWindow()

        applyFloat(onTop: prefs.alwaysOnTop, hideDock: prefs.hideDock)
        applyMode(prefs.compact, animated: false)
        restoreOrigin()
        panel.orderFront(nil)
        // 啟動時 SwiftUI 還沒畫任何東西，第一次算出的陰影是空的
        invalidateShadowSoon()
    }

    // MARK: 熱鍵

    private func wireKeys() {
        // 視窗自己有焦點時：不用按修飾鍵
        panel.onKey = { [weak self] event in
            guard let self else { return false }
            let bare = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .isDisjoint(with: [.command, .option, .control, .shift])
            guard bare else { return false }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case " ": self.model.toggle(); return true
            case "r": self.model.reset(); return true
            case "s": self.model.skip(); return true
            default:  return false
            }
        }

        panel.onCancel = { [weak self] in
            guard let self, self.model.alerting else { return false }
            self.model.acknowledge()
            return true
        }

        // 全域熱鍵：焦點在別的 App 上也有效
        Hotkeys.shared.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggle: self.model.toggle()
            case .reset:  self.model.reset()
            case .skip:   self.model.skip()
            }
        }
        Hotkeys.shared.setEnabled(prefs.globalHotkeys)

        prefs.$globalHotkeys.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { Hotkeys.shared.setEnabled($0) }
            .store(in: &bag)
    }

    // MARK: 尺寸與外觀

    private func applyMode(_ compact: Bool, animated: Bool) {
        // 縮小模式換成無邊框：有標題列的視窗會自己畫一層底（圓角方塊 + 模糊），
        // 就算把背景設成透明，那層底還是會在圓盤後面透出來。
        let style: NSWindow.StyleMask = compact
            ? [.borderless, .nonactivatingPanel]
            : [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
        if panel.styleMask != style {
            panel.styleMask = style
        }

        if !compact {
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.titlebarSeparatorStyle = .automatic
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                panel.standardWindowButton(button)?.isHidden = false
            }
        }

        if !compact { panel.alphaValue = 1 }
        panel.isOpaque = !compact
        panel.backgroundColor = compact ? .clear : Theme.groundNS
        // 縮小模式也用系統陰影。視窗伺服器依內容的透明度輪廓算陰影、畫在視窗外面，
        // 不會被視窗邊界切掉，而且自動跟著錶盤的形狀走。
        panel.hasShadow = true
        // 縮小時由 FloatingPanel 自己拖曳，避免和系統背景拖曳同時移動兩次。
        panel.compactDragEnabled = compact
        // 換 styleMask 會重設這幾個屬性，補回來
        panel.isMovable = true
        panel.isMovableByWindowBackground = !compact
        reassert()

        let size = compact ? prefs.dialStyle.compactSize : Metrics.full
        let now = panel.frame
        // 以目前的中心為軸心收放，使用者把視窗拖到哪就在哪縮放
        let target = NSRect(x: (now.midX - size.width / 2).rounded(),
                            y: (now.midY - size.height / 2).rounded(),
                            width: size.width,
                            height: size.height)

        guard animated else {
            panel.setFrame(target, display: true)
            panel.invalidateShadow()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Metrics.morph
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.16, 1.0)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.invalidateShadow()
                self.saveOrigin()
                self.invalidateShadowSoon()
            }
        })
    }

    // MARK: 浮動層級

    private func applyFloat(onTop: Bool, hideDock: Bool) {
        // 注意順序：isFloatingPanel 會把 level 強制設成 .floating（第 3 層），
        // 所以必須先設它，再指定我們要的層級，不然會被蓋掉。
        panel.isFloatingPanel = onTop

        if onTop {
            // 要蓋在「別的 App 的全螢幕」上，光是 .floating（第 3 層）不夠，
            // 得拉到狀態列層級，再加上「加入所有 Space」和「可在全螢幕旁出現」。
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        } else {
            panel.level = .normal
            panel.collectionBehavior = []
        }

        let policy: NSApplication.ActivationPolicy = (onTop && hideDock) ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// 重新宣告一次浮動設定。系統在切換 Space、視窗變成 key、App 被啟動時
    /// 有機會把這些屬性洗掉，所以這幾個時間點都補一次。
    private func reassert() {
        applyFloat(onTop: prefs.alwaysOnTop, hideDock: prefs.hideDock)
    }

    // MARK: 訂閱

    private func observePrefs() {
        // 一定要 receive(on:) 非同步派送。
        //
        // @Published 是在值「寫入之前」發佈的。如果直接在訂閱裡改視窗尺寸，
        // 會在舊值還沒被換掉時就觸發一次 SwiftUI 重繪——SwiftUI 用舊值畫完，
        // 通知也被消耗掉了，等新值真正寫入時就不會再重繪。
        // 結果是視窗已經縮小、畫面卻還是完整模式，永遠慢一拍。
        // 縮小模式下切風格，視窗要變成那個風格的形狀
        prefs.$dialStyle.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.prefs.compact else { return }
                self.applyMode(true, animated: true)
            }
            .store(in: &bag)

        prefs.$compact.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] compact in
                self?.applyMode(compact, animated: true)
            }
            .store(in: &bag)

        Publishers.Merge(prefs.$alwaysOnTop.dropFirst().map { _ in () },
                         prefs.$hideDock.dropFirst().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                // 非同步派送後屬性已經寫入，直接讀目前的值就好
                self.applyFloat(onTop: self.prefs.alwaysOnTop, hideDock: self.prefs.hideDock)
            }
            .store(in: &bag)
    }

    private func observeWindow() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reassert() }
            }
        }
        center.addObserver(forName: NSWindow.didMoveNotification,
                           object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOrigin() }
        }
        center.addObserver(forName: .dialFadeChanged, object: nil, queue: .main) { [weak self] note in
            let faded = (note.object as? Bool) ?? false
            MainActor.assumeIsolated {
                guard let self, self.prefs.compact else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    self.panel.animator().alphaValue = faded ? 0.42 : 1
                }
            }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassert() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassert() }
        }
    }

    // MARK: 位置記憶

    fileprivate func logClose() {
        Diagnostics.log("視窗收到關閉請求（已攔下，改為結束 App）")
    }

    /// 系統陰影是照「當下畫面」算的。模式或風格切換時，SwiftUI 的淡入淡出和視窗動畫不同步，
    /// 立刻重算可能抓到半透明的舊畫面，陰影就會多出一塊。晚一點再算一次。
    private func invalidateShadowSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.morph + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }
    }

    private func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "panelOrigin")
    }

    private func restoreOrigin() {
        guard let saved = UserDefaults.standard.string(forKey: "panelOrigin") else {
            panel.center()
            return
        }
        panel.setFrameOrigin(NSPointFromString(saved))
        // 螢幕接上／拔掉後存的位置可能已經在畫面外
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) {
            _ = screen
        } else {
            panel.center()
        }
    }
}


extension PanelController: NSWindowDelegate {
    /// 關閉視窗等於結束 App，但要走明確的路徑，
    /// 而不是靠「最後一個視窗關閉」那個會誤判的機制。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        logClose()
        NSApp.terminate(nil)
        return false
    }
}
