import Foundation
import UIKit

// MARK: - v2.0.43 崩溃上报：本地捕获 → 下次启动 POST 到 NAS /api/logs/crash
// NSException + 常见 signal 捕获，信息写本地文件，启动时异步上传（不阻塞）

enum CrashReporter {
    private static let pendingURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("crash_pending.json")
    private static let sigs: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]

    /// App 启动时安装（必须在 main 早期调用）
    static func install() {
        NSSetUncaughtExceptionHandler { ex in
            let stack = ex.callStackSymbols.prefix(40).joined(separator: "\n")
            write(type: "NSException", detail: "\(ex.name.rawValue): \(ex.reason ?? "")\n\(stack)")
        }
        for s in sigs {
            signal(s, { sig in
                write(type: "Signal(\(sig))", detail: "")
                exit(sig)
            })
        }
    }

    /// 启动时若有未上报崩溃 → 异步 POST，成功删除本地文件
    @MainActor
    static func flushPending(auth: AuthStore) async {
        guard FileManager.default.fileExists(atPath: pendingURL.path) else { return }
        guard let data = try? Data(contentsOf: pendingURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            try? FileManager.default.removeItem(at: pendingURL)
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
            try? FileManager.default.removeItem(at: pendingURL)
        }
    }

    /// 写崩溃信息到本地文件（POSIX 直写，signal handler 安全）
    private static func write(type: String, detail: String) {
        let entry: [String: String] = [
            "type": type,
            "detail": String(detail.prefix(4000)),
            "ts": "\(Int(Date().timeIntervalSince1970))",
            "app": "qingliao-ios",
            "version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let json = String(data: data, encoding: .utf8) else { return }
        // signal handler 上下文：只用 POSIX open/write（Foundation 不保证安全）
        let fd = open(pendingURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        _ = json.withCString { ptr in
            Darwin.write(fd, ptr, strlen(ptr))
        }
        close(fd)
    }
}
