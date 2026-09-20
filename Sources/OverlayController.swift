import AppKit
import SwiftUI
import Combine

/// 遮罩視窗。
///
/// `canBecomeKey` 一定要是 false：搶了 key window 會把使用者從別的 App 的
/// 全螢幕 Space 拽走，那正是 `PanelController` 整個設計在避免的事。
/// 代價是 Esc 到不了這裡——所以改成點任意處關閉。
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 休息時蓋住整個螢幕。
///
/// 這是這個 App 裡最危險的東西：一個覆蓋所有螢幕、吃掉點擊、又沒有 Dock 圖示
/// 可以求助的視窗。如果它拆不掉，使用者只剩下強制結束一條路。
/// 底下每一個看起來像多此一舉的防護都是為了這件事。
@MainActor
final class OverlayController {
    private let model: PomodoroModel
    private let prefs: Prefs

    private var panels: [OverlayPanel] = []
    private var bag = Set<AnyCancellable>()
    private var failsafe: Timer?

    /// 這次的遮罩要不要撐過整個休息。休息遮罩要撐；「回來專注」的提示按掉就好。
    private var holdsThroughPhase = false
    /// 遮罩是為了哪一段升起的。
    ///
    /// 沒有這個會有競態：complete() 同時改變 alerting 和 phase，兩個訂閱都非同步派送。
    /// phase 那邊如果晚一步跑，就會看到「遮罩已升起且要撐過整段」而把剛升起的遮罩
    /// 立刻收掉。記住當初那一段，只有真的離開才收。
    private var maskedPhase: Phase?
    /// 使用者手動關掉了這一次，別再自動跳回來
    private var suppressed = false

    /// 探針用
    var visiblePanels: [NSWindow] { panels }

    init(model: PomodoroModel, prefs: Prefs) {
        self.model = model
        self.prefs = prefs

        // 一定要 receive(on:)。除了既有的重繪順序問題，@Published 是在 willSet
        // 發佈的，同步讀 alertFinished 會拿到舊值，遮罩就會顯示錯誤的階段。
        model.$alerting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &bag)

        model.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.phaseChanged() }
            .store(in: &bag)

        prefs.$overlayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &bag)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIfShowing() }
        }
    }

    // MARK: 決定要不要顯示

    private func evaluate() {
        guard !suppressed else { return }

        switch prefs.overlayMode {
        case .off:
            hide()
        case .breakStart:
            if model.alerting && model.alertFinished == .work { raise(holding: true) }
        case .every:
            if model.alerting {
                raise(holding: model.alertFinished == .work)
            }
        }
    }

    private func phaseChanged() {
        suppressed = false
        guard holdsThroughPhase, !panels.isEmpty else { return }
        // 只有真的離開當初那一段才收——休息結束了
        if model.phase != maskedPhase { hide() }
    }

    // MARK: 顯示與拆除

    private func raise(holding: Bool) {
        holdsThroughPhase = holding
        maskedPhase = model.phase
        if panels.isEmpty { build() }
        armFailsafe()
    }

    private func build() {
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered,
                                     defer: false)
            // frame 用 screen.frame 而不是 visibleFrame——留著選單列的遮罩不算遮罩
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                        .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            // delegate 必須留 nil。PanelController 是 NSWindowDelegate，
            // 它的 windowShouldClose 直接呼叫 NSApp.terminate——遮罩若沾到那個
            // delegate，關遮罩就會關掉整個 App。
            panel.delegate = nil

            panel.contentView = NSHostingView(rootView:
                OverlayView(onDismiss: { [weak self] in self?.dismissByUser() },
                            onAcknowledge: { [weak self] in self?.model.acknowledge() },
                            onSkip: { [weak self] in self?.model.skip() })
                    .environmentObject(model)
                    .environmentObject(prefs))

            // orderFrontRegardless 而不是 makeKeyAndOrderFront：不搶焦點
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    private func rebuildIfShowing() {
        guard !panels.isEmpty else { return }
        hide()
        build()
    }

    private func dismissByUser() {
        suppressed = true
        hide()
    }

    private func hide() {
        failsafe?.invalidate()
        failsafe = nil
        for panel in panels {
            // orderOut 而不是 close()：close 會走 delegate 路徑，
            // 而這個 App 的視窗 delegate 會終止整個程式。
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        holdsThroughPhase = false
        maskedPhase = nil
    }

    /// 獨立於其他程式碼的硬逾時。就算狀態機壞掉，遮罩也一定會自己消失。
    private func armFailsafe() {
        failsafe?.invalidate()
        let seconds: TimeInterval = holdsThroughPhase
            ? TimeInterval(prefs.minutes(for: model.phase) * 60 + 120)
            : 300
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        RunLoop.main.add(t, forMode: .common)
        failsafe = t
    }
}

// MARK: - 畫面

private struct OverlayView: View {
    @EnvironmentObject var model: PomodoroModel
    @EnvironmentObject var prefs: Prefs

    let onDismiss: () -> Void
    let onAcknowledge: () -> Void
    let onSkip: () -> Void

    private var tint: Color { Theme.accent(model.phase) }

    var body: some View {
        ZStack {
            Theme.ground.opacity(0.82)

            VStack(spacing: 18) {
                Text(model.phase.isBreak ? "休息時間" : "回來專注")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(tint)

                Text(model.clock)
                    .font(.system(size: 92, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)

                if !model.task.isEmpty {
                    Text("剛才在做：\(model.task)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.muted)
                }

                HStack(spacing: 10) {
                    Button(model.running ? "知道了" : "開始休息") { onAcknowledge() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 38)
                        .background(Capsule().fill(tint))

                    Button("跳過休息") { onSkip() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(Capsule().fill(Theme.fill))
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 6)

                Text("點任意處關閉這層遮罩")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted.opacity(0.8))
                    .padding(.top, 2)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }
}
