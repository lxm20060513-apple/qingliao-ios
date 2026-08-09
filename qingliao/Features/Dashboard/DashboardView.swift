import SwiftUI

// MARK: - 看板页（智能家居 2x3 + NAS 面板 2x3，真实数据）

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth

    @State private var nas = NASStatus()
    @State private var haEntities: [HAEntity] = []
    @State private var loaded = false
    @State private var haOK = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "看板", subtitle: "智能家居 · NAS 状态")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("智能家居")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        DeviceCard(name: "客厅灯", value: haLights, sub: "\(haLightsOn) 盏开启", status: haLightsOn > 0 ? .on : .off)
                        DeviceCard(name: "空调", value: haClimate, sub: "\(haClimateOn) 台运行中", status: haClimateOn > 0 ? .on : .off)
                        DeviceCard(name: "门锁", value: haLockBattery, sub: "智能门锁", status: .on)
                        DeviceCard(name: "猫眼", value: haDoorbellBattery, sub: haDoorbellOnline ? "在线" : "离线", status: haDoorbellOnline ? .on : .off)
                        DeviceCard(name: "安防", value: haAlarm, sub: haAlarmArmed ? "已布防" : "未布防", status: haAlarmArmed ? .on : .warn)
                        DeviceCard(name: "温度", value: haTemp, sub: "室内温度", status: .on)
                    }

                    sectionTitle("NAS 面板")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        MeterCard(name: "CPU", value: String(format: "%.1f%%", nas.cpu), sub: nil, ratio: nas.cpu / 100.0, color: .blue)
                        MeterCard(name: "内存", value: nas.memUsedText, sub: "/ \(nas.memTotalText)", ratio: nas.memPct, color: .green)
                        MeterCard(name: "磁盘", value: String(format: "%.0f%%", nas.mainDiskPct), sub: nil, ratio: nas.mainDiskPct / 100.0, color: .orange)
                        ServiceCard(name: "轻聊后端", running: nas.qingliaoAlive, detail: nas.qingliaoMemText)
                        ServiceCard(name: "Hermes 网关", running: nas.hermesAlive, detail: nas.hermesMemText)
                        ServiceCard(name: "运行时间", running: true, detail: nas.uptime)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
            .refreshable {
                await refresh()
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
        async let nasJ = auth.json("/api/nas/status")
        async let haArr = try? auth.jsonArray("/api/ha/states")
        do {
            let (n, h) = try await (nasJ, haArr)
            nas = NASStatus.parse(n)
            if let arr = h {
                haEntities = arr.compactMap { HAEntity.parse($0 as? [String: Any] ?? [:]) }
                haOK = true
            }
        } catch {
            // 单次失败保留旧数据
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
