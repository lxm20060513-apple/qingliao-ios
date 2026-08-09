import SwiftUI

// MARK: - 看板页（智能家居 2x3 可控制 + NAS 2x3 + 全部磁盘列表）

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth

    @State private var nas = NASStatus()
    @State private var haEntities: [HAEntity] = []
    @State private var loaded = false
    @State private var showLightsSheet = false
    @State private var showClimateSheet = false
    @State private var busyEntity: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "看板", subtitle: "智能家居 · NAS 状态")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("智能家居")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        DeviceCard(name: "客厅灯", value: haLights, sub: "\(lightsOn) 盏开启 · 点击控制", status: lightsOn > 0 ? .on : .off)
                            .onTapGesture { showLightsSheet = true }
                        DeviceCard(name: "空调", value: haClimate, sub: "\(climateOn) 台运行中 · 点击控制", status: climateOn > 0 ? .on : .off)
                            .onTapGesture { showClimateSheet = true }
                        DeviceCard(name: "门锁", value: haLockBattery, sub: "智能门锁", status: .on)
                        DeviceCard(name: "猫眼", value: haDoorbellBattery, sub: haDoorbellOnline ? "在线" : "离线", status: haDoorbellOnline ? .on : .off)
                        DeviceCard(name: "安防", value: haAlarm, sub: haAlarmArmed ? "已布防" : "未布防", status: haAlarmArmed ? .on : .warn)
                        DeviceCard(name: "温度", value: haTemp, sub: "室内温度", status: .on)
                    }

                    sectionTitle("NAS 面板")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        MeterCard(name: "CPU", value: String(format: "%.1f%%", nas.cpu), sub: nil, ratio: nas.cpu / 100.0, color: .blue)
                        MeterCard(name: "内存", value: nas.memUsedText, sub: "/ \(nas.memTotalText)", ratio: nas.memPct, color: .green)
                        MeterCard(name: "磁盘", value: String(format: "%.0f%%", nas.maxDiskPct), sub: "\(nas.disks.count) 个分区", ratio: nas.maxDiskPct / 100.0, color: .orange)
                        ServiceCard(name: "轻聊后端", running: nas.qingliaoAlive, detail: nas.qingliaoMemText)
                        ServiceCard(name: "Hermes 网关", running: nas.hermesAlive, detail: nas.hermesMemText)
                        ServiceCard(name: "运行时间", running: true, detail: nas.uptime)
                    }

                    if !nas.disks.isEmpty {
                        sectionTitle("全部磁盘")
                        VStack(spacing: 0) {
                            ForEach(nas.disks) { d in
                                DiskRow(disk: d)
                            }
                        }
                        .glassListCard()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
            .refreshable {
                await refresh()
            }
            .sheet(isPresented: $showLightsSheet) {
                HADeviceSheet(title: "客厅灯", domain: "light", entities: lights, busyEntity: busyEntity) { e in
                    await toggle(e, domain: "light")
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showClimateSheet) {
                HADeviceSheet(title: "空调", domain: "climate", entities: climates, busyEntity: busyEntity) { e in
                    await toggle(e, domain: "climate")
                }
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            if !loaded {
                await refresh()
                loaded = true
            }
            // 10s 自动刷新
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await refresh()
            }
        }
    }

    // MARK: - 数据

    private func refresh() async {
        // 顺序请求（async let 返回值非 Sendable，Swift 6 严格并发下编译失败）
        if let n = try? await auth.json("/api/nas/status") {
            nas = NASStatus.parse(n)
        }
        if let h = try? await auth.jsonArray("/api/ha/states") {
            haEntities = h.compactMap { HAEntity.parse($0 as? [String: Any] ?? [:]) }
        }
    }

    /// HA 服务调用（PWA 同款：POST /api/ha/services/{domain}/toggle）
    private func toggle(_ e: HAEntity, domain: String) async {
        guard busyEntity == nil else { return }
        busyEntity = e.entityID
        defer { busyEntity = nil }
        do {
            _ = try await auth.request("/api/ha/services/\(domain)/toggle", method: "POST",
                                       body: ["entity_id": e.entityID])
            await refresh()
        } catch {
            // 控制失败静默（下次刷新自动纠正状态）
        }
    }

    // MARK: - HA 派生（与 PWA 相同挑选规则）

    private var lights: [HAEntity] {
        haEntities.filter { $0.entityID.hasPrefix("light.") && !$0.state.contains("unavailable") }
    }
    private var lightsOn: Int { lights.filter { $0.state != "off" }.count }
    private var haLights: String { "\(lightsOn)/\(lights.count) 盏" }

    private var climates: [HAEntity] {
        haEntities.filter { $0.entityID.hasPrefix("climate.") && !["unavailable", "offline", "unknown"].contains($0.state) }
    }
    private var climateOn: Int { climates.filter { $0.state != "off" }.count }
    private var haClimate: String { "\(climateOn)/\(climates.count) 台" }

    private var lockBattery: HAEntity? {
        haEntities.first { $0.entityID.contains("bacn01") && $0.entityID.contains("battery_level") }
    }
    private var haLockBattery: String {
        guard let e = lockBattery, let v = Double(e.state) else { return "--" }
        return "\(Int(v.rounded()))%"
    }

    private var doorbellBattery: HAEntity? {
        haEntities.first { $0.entityID.contains("chuangmi") && $0.entityID.contains("battery_level") }
    }
    private var haDoorbellBattery: String {
        guard let e = doorbellBattery, let v = Double(e.state) else { return "--" }
        return "\(Int(v.rounded()))%"
    }
    private var haDoorbellOnline: Bool {
        !(doorbellBattery?.state.contains("unavailable") ?? true)
    }

    private var alarm: HAEntity? {
        haEntities.first { $0.entityID.contains("alarmstatus") }
    }
    private var haAlarm: String { alarm?.state ?? "--" }
    private var haAlarmArmed: Bool {
        guard let st = alarm?.state else { return false }
        return ["布防", "armed", "armed_home", "armed_away", "on"].contains(st)
    }

    private var tempSensor: HAEntity? {
        // 优先室内温度计，其次任意 temperature sensor
        if let e = haEntities.first(where: { $0.entityID.contains("indoor_temperature") }) { return e }
        return haEntities.first {
            $0.entityID.hasPrefix("sensor.") && $0.entityID.contains("temperature")
                && !$0.state.contains("unavailable") && Double($0.state) != nil
        }
    }
    private var haTemp: String {
        guard let e = tempSensor, let v = Double(e.state) else { return "--" }
        return String(format: "%.1f°", v)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 15, weight: .bold))
            .padding(.top, 6)
    }
}

// MARK: - HA 设备控制 sheet（列表 + Toggle → 调服务）

struct HADeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let domain: String
    let entities: [HAEntity]
    let busyEntity: String?
    var onToggle: (HAEntity) async -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)

            if entities.isEmpty {
                Spacer()
                Text("暂无可用设备")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entities) { e in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(stateColor(e.state))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(e))
                                        .font(.system(size: 14, weight: .medium))
                                        .lineLimit(1)
                                    Text(e.state == "off" ? "已关闭" : (e.state == "on" ? "已开启" : e.state))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if busyEntity == e.entityID {
                                    ProgressView().tint(.secondary)
                                } else {
                                    Toggle("", isOn: Binding(
                                        get: { e.state != "off" },
                                        set: { _ in Task { await onToggle(e) } }
                                    ))
                                    .labelsHidden()
                                    .tint(.green)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
    }

    /// 设备显示名：friendly_name 太长时取前两段
    private func displayName(_ e: HAEntity) -> String {
        var name = e.friendlyName
        if name.isEmpty {
            name = e.entityID
        } else {
            // 小米设备 friendly_name 常含重复（"客厅灯  客厅灯 开关"）→ 去重保留第一段
            let parts = name.split(separator: " ").filter { !$0.isEmpty }
            if parts.count >= 2 && parts[0] == parts[1] {
                name = String(parts[0])
            }
        }
        return name
    }

    private func stateColor(_ st: String) -> Color {
        st == "off" || st.contains("unavailable") ? .gray : .green
    }
}

// MARK: - 磁盘行（PWA 同款：mnt + pct + 进度条 + used/total）

struct DiskRow: View {
    let disk: NASDisk

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(disk.mnt)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", disk.pct))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(disk.pct > 90 ? .red : (disk.pct > 75 ? .orange : .primary))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .systemGray5))
                    Capsule()
                        .fill(disk.pct > 90 ? Color.red : (disk.pct > 75 ? Color.orange : Color.green))
                        .frame(width: geo.size.width * min(max(disk.pct / 100.0, 0), 1))
                }
            }
            .frame(height: 4)
            Text("\(disk.usedText) / \(disk.totalText)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

enum DeviceStatus { case on, off, warn }

struct DeviceCard: View {
    let name: String
    let value: String
    let sub: String
    let status: DeviceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 6)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var color: Color {
        switch status {
        case .on: .green
        case .off: .gray
        case .warn: .orange
        }
    }
}

struct MeterCard: View {
    let name: String
    let value: String
    let sub: String?
    let ratio: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            Text(value).font(.system(size: 18, weight: .bold)).padding(.top, 6)
            if let sub {
                Text(sub).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .systemGray5))
                    Capsule().fill(color).frame(width: geo.size.width * min(max(ratio, 0), 1))
                }
            }
            .frame(height: 4)
            .padding(.top, 7)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ServiceCard: View {
    let name: String
    let running: Bool
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(running ? Color.green : Color.red).frame(width: 8, height: 8)
            }
            Text(running ? "运行中" : "已停止")
                .font(.system(size: 14, weight: .bold))
                .padding(.top, 6)
            Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 1)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
