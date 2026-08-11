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

/// 路由器板块：2x2 卡片（状态 / Clash 状态 / 启动 Clash / 关闭 Clash），刷新在标题旁
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

            // 2x2 卡片
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                // 卡1：路由器状态（在线/负载/温度）
                routerCard(title: "路由器", value: router.ok ? "在线" : (router.error.isEmpty ? "检测中" : "离线"),
                           sub: router.ok ? "负载 \(router.load) · \(router.temp)" : router.error,
                           color: router.ok ? .green : .red,
                           icon: "wifi", busy: router.busy) { onRefresh?() }
                // 卡2：Clash 状态（运行中/已停止）
                routerCard(title: "Clash", value: router.clashRunning ? "运行中" : "已停止",
                           sub: router.clashRunning ? "代理已生效" : "点击启动",
                           color: router.clashRunning ? .green : .gray,
                           icon: "bolt.fill", busy: router.busy) { onStart?() }
                // 卡3：启动 Clash（快捷指令）
                actionCard(title: "启动 Clash", icon: "play.fill", color: .green,
                           busy: router.busy, subtitle: "开启代理加速") { onStart?() }
                // 卡4：关闭 Clash（快捷指令）
                actionCard(title: "关闭 Clash", icon: "stop.fill", color: .red,
                           busy: router.busy, subtitle: "恢复直连") { onStop?() }
            }
        }
    }

    private func routerCard(title: String, value: String, sub: String, color: Color, icon: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func actionCard(title: String, icon: String, color: Color, busy: Bool, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    if busy { ProgressView().tint(color).scaleEffect(0.7) }
                    else {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(Color(color.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}
