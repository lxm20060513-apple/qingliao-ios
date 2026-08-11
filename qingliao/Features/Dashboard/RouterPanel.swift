import SwiftUI

// MARK: - 路由器面板（状态 + Clash 快捷指令，风格对齐 NAS 卡）

struct RouterStatus {
    var ok = false
    var hostname = "--"
    var load = "--"
    var uptime = "--"
    var memTotal = 0.0
    var memFree = 0.0
    var temp = "--"
    var clashRunning = false
    var error = ""
    var busy = false

    var memUsedText: String {
        String(format: "%.1fG / %.1fG", memTotal - memFree, memTotal)
    }
    var memPct: Double {
        memTotal > 0 ? (memTotal - memFree) / memTotal : 0
    }

    static func parse(_ j: [String: Any]) -> RouterStatus {
        var r = RouterStatus()
        r.ok = (j["ok"] as? Bool) ?? false
        r.hostname = j["hostname"] as? String ?? "--"
        r.load = j["load"] as? String ?? "--"
        r.uptime = j["uptime"] as? String ?? "--"
        r.memTotal = j["mem_total_gb"] as? Double ?? 0
        r.memFree = j["mem_free_gb"] as? Double ?? 0
        r.temp = j["temp"] as? String ?? "--"
        r.clashRunning = (j["clash_running"] as? Bool) ?? false
        r.error = j["error"] as? String ?? ""
        return r
    }

    static func merge(_ old: RouterStatus, with j: [String: Any]) -> RouterStatus {
        var r = old
        if let ok = j["ok"] as? Bool { r.ok = ok }
        if let cr = j["clash_running"] as? Bool { r.clashRunning = cr }
        if let e = j["error"] as? String, !e.isEmpty { r.error = e }
        return r
    }
}

/// 路由器板块：状态卡（主机/负载/内存/温度/Clash）+ 快捷指令（启动/关闭 Clash）
struct RouterPanel: View {
    let router: RouterStatus
    var onStart: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color.teal, Color.cyan],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "wifi")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("路由器")
                                .font(.system(size: 13, weight: .semibold))
                            Text(router.hostname)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(router.ok ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                        }
                        Text(router.ok ? "负载 \(router.load) · 温度 \(router.temp)" : (router.error.isEmpty ? "连接中..." : "离线：\(router.error)"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                // 指标行（对齐 NAS MeterCard 风格）
                HStack(spacing: 8) {
                    miniMetric("内存", router.memUsedText, router.memPct, .green)
                    miniMetric("Clash", router.clashRunning ? "运行中" : "已停止",
                               router.clashRunning ? 1.0 : 0.0,
                               router.clashRunning ? .green : .gray)
                    miniMetric("运行", router.uptime, 0, .blue)
                }
                // 快捷指令（启动/关闭 Clash + 刷新）
                HStack(spacing: 8) {
                    Button {
                        onStart?()
                    } label: {
                        HStack(spacing: 5) {
                            if router.busy { ProgressView().tint(.white).scaleEffect(0.7) }
                            else { Image(systemName: "play.fill").font(.system(size: 11)) }
                            Text("启动 Clash")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(router.busy)

                    Button {
                        onStop?()
                    } label: {
                        HStack(spacing: 5) {
                            if router.busy { ProgressView().tint(.white).scaleEffect(0.7) }
                            else { Image(systemName: "stop.fill").font(.system(size: 11)) }
                            Text("关闭 Clash")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(router.busy)

                    Button {
                        onRefresh?()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 42, height: 36)
                            .background(Color.accentColor.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(router.busy)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private func miniMetric(_ name: String, _ value: String, _ ratio: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(ratio >= 0.9 ? Color.red : (ratio >= 0.7 ? Color.orange : Color.green))
                    .frame(width: 6, height: 6)
            }
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
