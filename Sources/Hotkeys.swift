import AppKit
import Carbon.HIToolbox

/// 全域熱鍵：焦點在任何 App 上都有效。
///
/// 用 Carbon 的 `RegisterEventHotKey` 而不是 `CGEventTap`——前者**不需要任何權限**
/// （實測 status == noErr），後者要輔助使用授權。對一個計時器來說，
/// 為了熱鍵去要求錄製鍵盤的權限代價太高。
///
/// 組合鍵一律帶 ⌃⌥。純空白鍵不能當全域熱鍵：那會把整個系統的空白鍵吃掉。
/// 視窗自己有焦點時的純按鍵在 `FloatingPanel.keyDown` 處理。
@MainActor
final class Hotkeys {
    enum Action: UInt32, CaseIterable {
        case toggle = 1
        case reset = 2
        case skip = 3

        var keyCode: UInt32 {
            switch self {
            case .toggle: return UInt32(kVK_Space)
            case .reset:  return UInt32(kVK_ANSI_R)
            case .skip:   return UInt32(kVK_ANSI_S)
            }
        }

        var label: String {
            switch self {
            case .toggle: return "⌃⌥空白鍵"
            case .reset:  return "⌃⌥R"
            case .skip:   return "⌃⌥S"
            }
        }

        var what: String {
            switch self {
            case .toggle: return "開始／暫停"
            case .reset:  return "重設這一段"
            case .skip:   return "跳過這一段"
            }
        }
    }

    static let shared = Hotkeys()

    var onAction: ((Action) -> Void)?
    private(set) var isEnabled = false
    /// 探針用：真的被系統接受的熱鍵數量
    private(set) var registeredCount = 0

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private init() {}

    func setEnabled(_ on: Bool) {
        on ? enable() : disable()
    }

    private func enable() {
        guard !isEnabled else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetEventDispatcherTarget(), Self.callback,
                                  1, &spec, context, &handler) == noErr else { return }

        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(action.keyCode,
                                             UInt32(controlKey | optionKey),
                                             id, GetEventDispatcherTarget(), 0, &ref)
            // 別的 App 先佔走同一組鍵的話會失敗。失敗就跳過，不要整組放棄。
            if status == noErr, let ref { refs.append(ref) }
        }
        registeredCount = refs.count
        isEnabled = true
    }

    private func disable() {
        guard isEnabled else { return }
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        registeredCount = 0
        isEnabled = false
    }

    // MARK: C 回呼

    private nonisolated static let signature = OSType(0x504f4d4f)   // 'POMO'

    /// 必須是不捕獲任何東西的閉包，才能當 C 函式指標。
    /// 自己的實例透過 userData 傳進來。
    private nonisolated static let callback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        var id = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr, let action = Action(rawValue: id.id) else { return noErr }

        let box = Unmanaged<Hotkeys>.fromOpaque(userData)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                box.takeUnretainedValue().onAction?(action)
            }
        }
        return noErr
    }
}
