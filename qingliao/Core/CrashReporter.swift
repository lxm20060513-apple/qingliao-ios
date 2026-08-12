import Foundation
import UIKit

// MARK: - v2.0.43 崩溃上报：本地捕获 → 下次启动 POST 到 NAS /api/logs/crash
// 注意：signal/NSException handler 是 C 函数指针，闭包不能捕获上下文，
// 因此 handler 全部用顶层函数 + 固定路径 POSIX 直写。

/// 崩溃文件路径（全局函数，handler 与 flushPending 共用，避免捕获）
/// v2.0.44：用 getenv("HOME")（async-signal-safe）替代 NSSearchPathForDirectoriesInDomains
/// （后者非 signal-safe，崩溃 handler 里调用可能死锁卡死导致文件写不成）
func qlCrashFilePath() -> String {
    if let home = getenv("HOME") {
        return String(cString: home) + "/Documents/crash_pending.json"
    }
    return NSTemporaryDirectory() + "crash_pending.json"
}

/// POSIX 直写崩溃信息（v2.0.47：路径用 C 数组 strcpy/strcat 拼接，全程无 Swift 分配，
/// 纯 async-signal-safe——String(cString:) 等 Swift 字符串构造会分配内存，handler 里可能死锁）
func qlWriteCrashFile(type: String, detail: String) {
    let escaped = detail
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .prefix(3000)
    let entry = "{\"type\":\"\(type)\",\"detail\":\"\(escaped)\",\"ts\":\(Int(Date().timeIntervalSince1970))}\n"
    let home = getenv("HOME")
    let suffix = "/Documents/crash_pending.json"
    var path = [CChar](repeating: 0, count: 1024)
    if let h = home {
        _ = strcpy(&path, h)
    } else {
        _ = strcpy(&path, "/tmp")
    }
    _ = strcat(&path, suffix)
    let fd = open(&path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard fd >= 0 else { return }
    entry.withCString { ptr in
        Darwin.write(fd, ptr, strlen(ptr))
    }
    close(fd)
}

/// signal handler（顶层函数，无捕获）
func qlCrashSignalHandler(_ sig: Int32) {
    qlWriteCrashFile(type: "Signal(\(sig))", detail: "")
    exit(sig)
}

/// NSException handler（顶层函数，无捕获）
func qlCrashExceptionHandler(_ ex: NSException) {
    let stack = ex.callStackSymbols.prefix(30).joined(separator: "\n")
    qlWriteCrashFile(type: "NSException", detail: "\(ex.name.rawValue): \(ex.reason ?? "")\n\(stack)")
}

enum CrashReporter {
    private static let sigs: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]

    /// App 启动时安装（必须在 main 早期调用）
    static func install() {
        NSSetUncaughtExceptionHandler(qlCrashExceptionHandler)
        for s in sigs {
            signal(s, qlCrashSignalHandler)
        }
    }

    /// 启动时若有未上报崩溃 → 异步 POST，成功删除本地文件
    @MainActor
    static func flushPending(auth: AuthStore) async {
        let path = qlCrashFilePath()
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        var body: [String: Any] = obj
        body["app"] = "qingliao-ios"
        body["platform"] = "iOS"
        body["os"] = UIDevice.current.systemVersion
        body["device"] = UIDevice.current.model
        if let info = Bundle.main.infoDictionary {
            body["version"] = (info["CFBundleShortVersionString"] as? String) ?? ""
        }
        let ok = (try? await auth.json("/api/logs/crash", method: "POST", body: body))?["ok"] as? Bool ?? false
        if ok {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
