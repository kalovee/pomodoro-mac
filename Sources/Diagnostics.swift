import Foundation

/// 把「App 為什麼結束」寫到 ~/Library/Logs/番茄鐘.log。
/// 沒有 crash log 的閃退通常是有人呼叫了 terminate，記下呼叫堆疊才查得出來是誰。
enum Diagnostics {
    static let path = NSString(string: "~/Library/Logs/番茄鐘.log").expandingTildeInPath

    static func log(_ message: String, stack: Bool = false) {
        var line = "[\(stamp())] \(message)\n"
        if stack {
            line += Thread.callStackSymbols.prefix(25)
                .map { "    " + $0 }
                .joined(separator: "\n") + "\n"
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    static func installHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            Diagnostics.log("💥 未捕捉例外 \(exception.name.rawValue): \(exception.reason ?? "")")
            Diagnostics.log("    " + exception.callStackSymbols.prefix(25).joined(separator: "\n    "))
        }
        for sig in [SIGSEGV, SIGABRT, SIGILL, SIGBUS, SIGFPE] {
            signal(sig) { s in
                Diagnostics.log("💥 收到訊號 \(s)")
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
