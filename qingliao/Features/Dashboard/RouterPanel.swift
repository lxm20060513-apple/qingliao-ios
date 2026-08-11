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

/// 路由器板块：NAS 同款卡片风格（MeterCard/ServiceCard）+ Clash 开关
struct RouterPanel: View {
    let router: RouterStatus
    var onStart: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            // 标题行：路由器名 + 刷新按钮（在标题旁）
            HStack(spacing: 6) {
                Text("📡 路由器")
                    .font(.system(size: 13, weight: .semibold))
                Text(router.hostname)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(router.ok ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Spacer()
                Button {
                    onRefresh?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(router.busy)
            }

            // 2x2 指标卡（同 NAS 面板 MeterCard/ServiceCard 风格）
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                MeterCard(name: "CPU", value: router.load,
                          sub: "负载", ratio: loadRatio, color: .blue)
                MeterCard(name: "内存", value: router.memUsedText,
                          sub: "/ \(String(format: "%.1fG", router.memTotal))", ratio: router.memPct, color: .green)
                ServiceCard(name: "运行时间", running: true, detail: router.uptime)
                ServiceCard(name: "Clash", running: router.clashRunning,
                            detail: router.clashRunning ? "代理已生效" : "已停止")
            }

            // Clash 开关（快捷指令）
            HStack(spacing: 8) {
                Button {
                    onStart?()
                } label: {
                    HStack(spacing: 5) {
                        if router.busy { ProgressView().tint(.white).scaleEffect(0.7) }
                        else { Image(systemName: "play.fill").font(.system(size: 11)) }
                        Text("启动 Clash")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(router.busy)
            }
        }
    }

    /// 负载 → 进度比例（OpenWrt 常见 4 核：load/4 封顶 1）
    private var loadRatio: Double {
        let v = Double(router.load.components(separatedBy: " ").first ?? "0") ?? 0
        return min(v / 4.0, 1.0)
    }
}
