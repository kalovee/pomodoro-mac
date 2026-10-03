import AppKit
import SwiftUI

@main
struct ProgressAndSizeTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await run()
            exit(0)
        }
        app.run()
    }

    @MainActor static func run() async {
        let suite = "local.pomodoro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "globalHotkeys")
        defaults.set(false, forKey: "soundOn")
        defaults.set(false, forKey: "notifyOn")
        defaults.set(OverlayMode.off.rawValue, forKey: "overlayMode")
        defaults.set(false, forKey: "idleFade")
        let prefs = Prefs(defaults: defaults)
        var checks = 0
        func check(_ ok: Bool, _ label: String) {
            guard ok else { fatalError("FAIL: \(label)") }
            checks += 1
            print("PASS: \(label)")
            fflush(stdout)
        }
        // Hosted Intel machines may render a newly expanded SwiftUI tree more slowly.
        // Wait for the actual state, bounded to three seconds, not a guessed sleep.
        func settle(_ condition: () -> Bool) async {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        let model = PomodoroModel(prefs: prefs)
        check(model.pendingRecovery == nil, "fresh install has no recovery prompt")
        model.task = "國際關係閱讀"
        model.start()
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        model.pause()
        let left = model.remaining
        check(left < 1500 && left > 1497, "countdown checkpoint tracks actual elapsed time")
        try? await Task.sleep(nanoseconds: 500_000_000)
        let restored = PomodoroModel(prefs: prefs)
        check(restored.pendingRecovery?.task == model.task, "task survives relaunch")
        restored.recoverProgress(startImmediately: false)
        check(abs(restored.remaining - left) < 0.02 && !restored.running,
              "restore paused freezes closed-app time")
        check(restored.history.isEmpty, "recovery adds no completed sessions")
        restored.start()
        check(restored.running, "restored countdown can continue")
        restored.pause()

        let restarted = PomodoroModel(prefs: prefs)
        restarted.discardRecovery()
        check(restarted.pendingRecovery == nil && defaults.data(forKey: "unfinishedProgress.v1") == nil,
              "start fresh removes old checkpoint")

        func seed(_ saved: ProgressSnapshot) {
            defaults.set(try! JSONEncoder().encode(saved), forKey: "unfinishedProgress.v1")
        }
        seed(ProgressSnapshot(mode: .pomodoro, phase: .shortBreak, round: 2,
                              remaining: 123.25, elapsed: 0, task: "休息", savedAt: .distantPast))
        let breakModel = PomodoroModel(prefs: prefs)
        breakModel.recoverProgress(startImmediately: false)
        check(breakModel.phase == .shortBreak && breakModel.roundInCycle == 2 && breakModel.remaining == 123.25,
              "break phase and cycle round survive relaunch")
        seed(ProgressSnapshot(mode: .countdown, phase: .work, round: 0,
                              remaining: 45, elapsed: 0, task: "單次倒數", savedAt: .distantPast))
        let countdown = PomodoroModel(prefs: prefs)
        countdown.recoverProgress(startImmediately: true)
        check(countdown.mode == .countdown && countdown.running && countdown.remaining == 45,
              "single countdown resumes independently")
        countdown.pause()
        seed(ProgressSnapshot(mode: .stopwatch, phase: .work, round: 0,
                              remaining: 3600, elapsed: 234.5, task: "碼錶", savedAt: .distantPast))
        let stopwatch = PomodoroModel(prefs: prefs)
        stopwatch.recoverProgress(startImmediately: false)
        check(stopwatch.mode == .stopwatch && stopwatch.elapsed == 234.5, "stopwatch restores accumulated time")
        stopwatch.start()
        try? await Task.sleep(nanoseconds: 400_000_000)
        stopwatch.pause()
        check(stopwatch.elapsed > 234.8 && stopwatch.elapsed < 235.2, "stopwatch resumes from saved base")
        defaults.set(Data("invalid".utf8), forKey: "unfinishedProgress.v1")
        let invalid = PomodoroModel(prefs: prefs)
        check(invalid.pendingRecovery == nil, "invalid checkpoint safely ignored")

        defaults.removeObject(forKey: "unfinishedProgress.v1")
        prefs.timerMode = .pomodoro
        prefs.alwaysOnTop = true
        prefs.hideDock = true
        prefs.compact = true
        let controller = PanelController(prefs: prefs)
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrameOrigin(NSPoint(x: 300, y: 300))
        func capture(_ window: NSWindow, _ name: String) {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/pomodoro-\(name).png"))
            }
        }
        for style in DialStyle.allCases {
            for size in CompactSize.allCases {
                prefs.dialStyle = style
                prefs.compactSize = size
                try? await Task.sleep(nanoseconds: 420_000_000)
                let deadline = Date().addingTimeInterval(3)
                while controller.panel.frame.size != prefs.compactWindowSize && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                check(controller.panel.frame.size == prefs.compactWindowSize,
                      "\(style.rawValue) / \(size.rawValue) panel fits scaled content (actual \(controller.panel.frame.size), expected \(prefs.compactWindowSize), minimum \(controller.panel.minSize))")
                check(controller.panel.level == .statusBar && controller.panel.compactDragEnabled,
                      "\(style.rawValue) / \(size.rawValue) retains floating and drag")
                if style == .classic || (style == .flip && size == .small)
                    || (style == .hourglass && size == .large) {
                    capture(controller.panel, "\(style.rawValue)-\(size.rawValue)")
                }
            }
        }
        let p = controller.panel
        var mouse = NSPoint(x: 500, y: 500)
        p.screenMouseLocation = { mouse }
        func event(_ kind: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: NSPoint(x: 40, y: 40), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: p.windowNumber, context: nil,
                               eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let origin = p.frame.origin
        p.sendEvent(event(.leftMouseDown))
        mouse = NSPoint(x: 560, y: 520)
        p.sendEvent(event(.leftMouseDragged))
        p.sendEvent(event(.leftMouseUp))
        check(abs(p.frame.origin.x - origin.x - 60) < 1 && abs(p.frame.origin.y - origin.y - 20) < 1,
              "scaled compact panel drag follows mouse without resetting")
        check(!controller.model.running, "drag does not trigger start button")
        prefs.compact = false
        await settle { p.frame.size == Metrics.full && !p.compactDragEnabled }
        check(p.frame.size == Metrics.full && !p.compactDragEnabled,
              "full mode retains original dimensions (actual \(p.frame.size), expected \(Metrics.full), drag \(p.compactDragEnabled))")

        // Exercise the actual startup sheet and choose Restore Paused.
        seed(ProgressSnapshot(mode: .pomodoro, phase: .work, round: 1,
                              remaining: 567, elapsed: 0, task: "重開測試", savedAt: Date()))
        prefs.compact = true
        let recoveryPanel = PanelController(prefs: prefs)
        defer { recoveryPanel.panel.orderOut(nil) }
        await settle { recoveryPanel.panel.attachedSheet != nil && recoveryPanel.panel.frame.size == Metrics.full }
        check(recoveryPanel.panel.attachedSheet != nil, "startup presents recovery sheet")
        check(recoveryPanel.panel.frame.size == Metrics.full,
              "compact startup expands temporarily so recovery controls fit")
        if let sheet = recoveryPanel.panel.attachedSheet {
            capture(sheet, "recovery")
            recoveryPanel.panel.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        }
        await settle { recoveryPanel.model.pendingRecovery == nil && recoveryPanel.panel.frame.size == prefs.compactWindowSize }
        check(recoveryPanel.model.pendingRecovery == nil && recoveryPanel.model.remaining == 567
              && recoveryPanel.model.task == "重開測試" && !recoveryPanel.model.running,
              "startup sheet restores paused progress correctly")
        check(recoveryPanel.panel.frame.size == prefs.compactWindowSize && prefs.compact,
              "recovery returns to saved compact size")
        print("\(checks) checks passed. Production preferences and history untouched.")
    }
}
