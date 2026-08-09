import SwiftUI

// MARK: - 看板页（智能家居 2x3 可控制 + NAS 2x3 + 全部磁盘列表）

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth

    @State private var nas = NASStatus()
    @State private var haEntities: [HAEntity] = []
    @State private var loaded = false
    @State private var showLightsSheet = false
    @State private var showClimateSheet = false

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
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(nas.disks) { d in
                                DiskTile(disk: d)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
            .refreshable {
                await refresh()
            }
            .sheet(isPresented: $showLightsSheet) {
                HADeviceSheet(title: "客厅灯", domain: "light")
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showClimateSheet) {
                HADeviceSheet(title: "空调", domain: "climate")
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

// MARK: - HA 设备控制 sheet（HomeKit 风格：灯=卡片网格 / 空调=模式控制卡）

struct HADeviceSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let title: String
    let domain: String

    @State private var entities: [HAEntity] = []
    @State private var loading = true
    @State private var busyID: String?

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

            if loading {
                Spacer()
                ProgressView().tint(.secondary)
                Spacer()
            } else if entities.isEmpty {
                Spacer()
                Text("暂无可用设备")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else if domain == "light" {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(entities) { e in
                            lightCard(e)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            } else {
                // 空调：模式控制卡
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(entities) { e in
                            climateCard(e)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: - 灯卡（HomeKit 网格：点亮=黄色光晕）

    private func lightCard(_ e: HAEntity) -> some View {
        let isOn = e.state == "on"
        return Button {
            toggle(e)
        } label: {
            VStack(spacing: 8) {
                if busyID == e.entityID {
                    ProgressView().tint(.secondary)
                        .frame(height: 30)
                } else {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(isOn ? Color.yellow : Color.gray.opacity(0.7))
                        .shadow(color: isOn ? Color.yellow.opacity(0.55) : .clear, radius: 9)
                }
                Text(displayName(e))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(isOn ? "已开启" : "已关闭")
                    .font(.system(size: 10))
                    .foregroundStyle(isOn ? .yellow : .tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.yellow.opacity(0.13) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? Color.yellow.opacity(0.3) : .clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空调卡（当前温度大字 + 模式按钮 + 温度步进）

    private func climateCard(_ e: HAEntity) -> some View {
        let attrs = e.attributes
        let cur = (attrs["current_temperature"] as? Double) ?? 0
        let target = (attrs["temperature"] as? Double) ?? 24
        let step = (attrs["target_temp_step"] as? Double) ?? 1
        let modes = (attrs["hvac_modes"] as? [String]) ?? ["off", "auto", "cool", "dry", "heat", "fan_only"]
        let isOn = e.state != "off" && e.state != "unavailable"

        return VStack(alignment: .leading, spacing: 12) {
            // 顶部：名称 + 状态
            HStack {
                Text(displayName(e))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(isOn ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            // 当前温度 + 目标温度步进
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("室内温度")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", cur))
                            .font(.system(size: 40, weight: .bold))
                        Text("°")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(spacing: 6) {
                    Button {
                        setTemp(e, value: target + step)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Color(uiColor: .systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Text(String(format: "%.1f°", target))
                        .font(.system(size: 16, weight: .semibold))
                    Button {
                        setTemp(e, value: target - step)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Color(uiColor: .systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // 模式按钮行
            HStack(spacing: 8) {
                ForEach(modes, id: \.self) { m in
                    Button {
                        setMode(e, mode: m)
                    } label: {
                        Text(modeName(m))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(e.state == m ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(e.state == m ? Color.accentColor : Color(uiColor: .systemGray5))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isOn ? Color.blue.opacity(0.25) : .clear, lineWidth: 0.8)
        )
    }

    /// 模式显示名
    private func modeName(_ m: String) -> String {
        switch m {
        case "off": "关闭"
        case "auto": "自动"
        case "cool": "制冷"
        case "heat": "制热"
        case "dry": "除湿"
        case "fan_only": "送风"
        default: m
        }
    }

    // MARK: - 服务调用（Task 内只捕获 Sendable 值）

    private func toggle(_ e: HAEntity) {
        callService(domain: domain, service: "toggle", entityID: e.entityID, extra: nil)
    }

    private func setMode(_ e: HAEntity, mode: String) {
        callService(domain: "climate", service: "set_hvac_mode", entityID: e.entityID,
                    extra: ["hvac_mode": mode])
    }

    private func setTemp(_ e: HAEntity, value: Double) {
        callService(domain: "climate", service: "set_temperature", entityID: e.entityID,
                    extra: ["temperature": value])
    }

    private func callService(domain: String, service: String, entityID: String, extra: [String: Any]?) {
        guard busyID == nil else { return }
        busyID = entityID
        let id = entityID
        let path = "/api/ha/services/\(domain)/\(service)"
        var body: [String: Any] = ["entity_id": id]
        if let extra { body.merge(extra) { _, new in new } }
        Task {
            defer { busyID = nil }
            do {
                _ = try await auth.request(path, method: "POST", body: body)
            } catch {
                // 控制失败静默
            }
            await load()
        }
    }

    private func load() async {
        if let arr = try? await auth.jsonArray("/api/ha/states") {
            let all = arr.compactMap { HAEntity.parse($0 as? [String: Any] ?? [:]) }
            entities = all.filter {
                $0.entityID.hasPrefix(domain + ".") && !$0.state.contains("unavailable")
            }
        }
        loading = false
    }

    /// 设备显示名：friendly_name 太长时取第一段
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
}

// MARK: - 磁盘磁贴（与 DeviceCard/MeterCard 同款 HomeKit 卡片风格）

struct DiskTile: View {
    let disk: NASDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(shortName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", disk.pct))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(disk.pct > 90 ? .red : (disk.pct > 75 ? .orange : .primary))
            }
            Text(String(format: "%.0f%%", disk.pct))
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 6)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .systemGray5))
                    Capsule()
                        .fill(disk.pct > 90 ? Color.red : (disk.pct > 75 ? Color.orange : Color.green))
                        .frame(width: geo.size.width * min(max(disk.pct / 100.0, 0), 1))
                }
            }
            .frame(height: 4)
            .padding(.top, 7)
            Text("\(disk.usedText) / \(disk.totalText)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// 挂载点短名（/dev/mapper/... → volume1）
    private var shortName: String {
        let parts = disk.mnt.split(separator: "/").filter { !$0.isEmpty }
        return parts.last.map(String.init) ?? disk.mnt
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
