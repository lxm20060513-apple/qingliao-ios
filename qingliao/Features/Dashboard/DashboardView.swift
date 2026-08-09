import SwiftUI

// MARK: - 看板页（智能家居 2x3 可控制 + NAS 2x3 + 磁盘弹出式）

enum DashboardSheet: String, Identifiable {
    case lights, climate, service, disks
    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth

    @State private var nas = NASStatus()
    @State private var haEntities: [HAEntity] = []
    @State private var loaded = false
    @State private var activeSheet: DashboardSheet?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "看板", subtitle: "智能家居 · NAS 状态")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("智能家居")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        DeviceCard(name: "开关", value: haLights, sub: "\(lightsOn) 盏开启 · 点击控制", status: lightsOn > 0 ? .on : .off)
                            .onTapGesture { activeSheet = .lights }
                        DeviceCard(name: "空调", value: haClimate, sub: "\(climateOn) 台运行中 · 点击控制", status: climateOn > 0 ? .on : .off)
                            .onTapGesture { activeSheet = .climate }
                        DeviceCard(name: "门锁", value: haLockBattery, sub: "智能门锁", status: .on)
                        DeviceCard(name: "猫眼", value: haDoorbellBattery, sub: haDoorbellOnline ? "在线" : "离线", status: haDoorbellOnline ? .on : .off)
                        DeviceCard(name: "安防", value: haAlarm, sub: haAlarmArmed ? "已布防" : "未布防", status: haAlarmArmed ? .on : .warn)
                        DeviceCard(name: "温度", value: haTemp, sub: "室内温度", status: .on)
                    }

                    sectionTitle("NAS 面板")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        MeterCard(name: "CPU", value: String(format: "%.1f%%", nas.cpu), sub: nil, ratio: nas.cpu / 100.0, color: .blue)
                        MeterCard(name: "内存", value: nas.memUsedText, sub: "/ \(nas.memTotalText)", ratio: nas.memPct, color: .green)
                        MeterCard(name: "磁盘", value: String(format: "%.0f%%", nas.maxDiskPct), sub: "\(nas.disks.count) 个分区 · 点击查看", ratio: nas.maxDiskPct / 100.0, color: .orange)
                            .onTapGesture { activeSheet = .disks }
                        ServiceCard(name: "轻聊后端", running: nas.qingliaoAlive, detail: nas.qingliaoMemText)
                            .onTapGesture { activeSheet = .service }
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
            .sheet(item: $activeSheet) { s in
                switch s {
                case .lights:
                    HADeviceSheet(title: "客厅灯", domain: "light")
                        .presentationDetents([.medium, .large])
                case .climate:
                    HADeviceSheet(title: "空调", domain: "climate")
                        .presentationDetents([.medium, .large])
                case .service:
                    ServiceControlSheet()
                        .presentationDetents([.medium])
                case .disks:
                    DisksSheet(disks: nas.disks)
                        .presentationDetents([.medium, .large])
                }
            }
        }
        .task {
            if !loaded {
                await refresh()
                loaded = true
            }
            // 10s 自动刷新
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
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

// MARK: - 服务控制 sheet（HomeKit 卡片式：信息卡 + 重试卡 + 停止卡）

struct ServiceControlSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var info = "管理轻聊后端服务"
    @State private var showStopConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("轻聊后端")
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
            .padding(.bottom, 12)

            // 服务信息卡
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.15))
                    Image(systemName: "server.rack")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("轻聊后端服务")
                        .font(.system(size: 14, weight: .semibold))
                    Text(info)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("运行中")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)

            // 重试卡
            Button {
                restart()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.accentColor)
                        if busy {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("重试服务")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("重启轻聊后端进程")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // 停止卡
            Button {
                showStopConfirm = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.15))
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("停止服务")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("停止后轻聊将不可用")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color.red.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .confirmationDialog("停止后轻聊将完全不可用，需在 NAS 上手动启动", isPresented: $showStopConfirm, titleVisibility: .visible) {
                Button("停止服务", role: .destructive) {
                    stopService()
                }
                Button("取消", role: .cancel) {}
            }

            Spacer()
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
    }

    private func restart() {
        guard !busy else { return }
        busy = true
        info = "正在重启服务..."
        Task {
            defer { busy = false }
            do {
                _ = try await auth.request("/api/nas/service/restart", method: "POST",
                                           body: ["service": "qingliao"])
                info = "重试指令已发送，服务即将重启"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !Task.isCancelled { dismiss() }
                }
            } catch {
                info = "发送失败，请检查连接"
            }
        }
    }

    private func stopService() {
        guard !busy else { return }
        busy = true
        info = "正在停止服务..."
        Task {
            defer { busy = false }
            do {
                _ = try await auth.request("/api/nas/service/stop", method: "POST",
                                           body: ["service": "qingliao"])
                info = "停止指令已发送"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !Task.isCancelled { dismiss() }
                }
            } catch {
                info = "发送失败，请检查连接"
            }
        }
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

    // MARK: - 灯卡（PWA HomeKit 复刻：渐变图标容器 + 圆形小开关）

    private func lightCard(_ e: HAEntity) -> some View {
        let isOn = e.state == "on"
        return Button {
            toggle(e)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // 图标容器：点亮=黄色渐变光晕 / 熄灭=灰底
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isOn
                                  ? LinearGradient(colors: [Color.yellow.opacity(0.30), Color.orange.opacity(0.18)],
                                                   startPoint: .top, endPoint: .bottom)
                                  : Color(uiColor: .systemGray6))
                        Image(systemName: "lightbulb.max.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(isOn ? Color.yellow : Color.gray.opacity(0.5))
                            .shadow(color: isOn ? Color.yellow.opacity(0.8) : .clear, radius: 8)
                    }
                    .frame(width: 46, height: 46)
                    Spacer()
                    // 圆形小开关（PWA .ha-toggle 同款）
                    ZStack {
                        Circle()
                            .fill(isOn ? Color.accentColor : Color(uiColor: .systemGray5))
                        if busyID == e.entityID {
                            ProgressView().tint(.white).scaleEffect(0.65)
                        } else {
                            Image(systemName: "power")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isOn ? .white : Color.secondary)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .shadow(color: isOn ? Color.accentColor.opacity(0.45) : .clear, radius: 4)
                }
                Text(displayName(e))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(isOn ? "已开启" : "已关闭")
                    .font(.system(size: 10.5))
                    .fontWeight(isOn ? .semibold : .regular)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .padding(12)
            .frame(minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isOn ? Color.blue.opacity(0.13) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: isOn ? Color.accentColor.opacity(0.22) : Color.black.opacity(0.15), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空调卡（PWA climate-card 复刻：跨行渐变卡 + 电源圆钮 + 模式胶囊）

    private func climateCard(_ e: HAEntity) -> some View {
        let attrs = e.attributes
        let cur = (attrs["current_temperature"] as? Double) ?? 0
        let target = (attrs["temperature"] as? Double) ?? 24
        let step = (attrs["target_temp_step"] as? Double) ?? 1
        let modes = (attrs["hvac_modes"] as? [String]) ?? ["off", "auto", "cool", "dry", "heat", "fan_only"]
        let isOn = e.state != "off" && e.state != "unavailable"

        return VStack(alignment: .leading, spacing: 10) {
            // 顶部：图标 + 名称/状态 + 温度 + 电源
            HStack(spacing: 10) {
                Image(systemName: "snowflake")
                    .font(.system(size: 24))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(e))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(isOn ? modeName(e.state) : "已关闭")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", target))
                        .font(.system(size: 28, weight: .bold))
                    Text("°")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                // 电源圆钮（PWA .ha-climate-power 同款）
                Button {
                    toggle(e)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isOn ? Color.accentColor : Color(uiColor: .systemGray5))
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isOn ? .white : Color.secondary)
                    }
                    .frame(width: 32, height: 32)
                    .shadow(color: isOn ? Color.accentColor.opacity(0.5) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
            }

            // 温度步进 + 当前室温
            HStack(spacing: 12) {
                Text("室温 \(String(format: "%.0f", cur))°")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    setTemp(e, value: target - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color(uiColor: .systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    setTemp(e, value: target + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color(uiColor: .systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // 模式按钮行
            HStack(spacing: 8) {
                ForEach(modes, id: \.self) { m in
                    Button {
                        setMode(e, mode: m)
                    } label: {
                        Text(modeName(m))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(e.state == m ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
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
        .background(
            LinearGradient(colors: [isOn ? Color.blue.opacity(0.20) : Color.blue.opacity(0.08), Color(uiColor: .secondarySystemGroupedBackground)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isOn ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: isOn ? Color.accentColor.opacity(0.15) : .clear, radius: 10, y: 3)
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

// MARK: - 磁盘弹窗（点看板"磁盘"卡弹出，2 列卡片）

struct DisksSheet: View {
    @Environment(\.dismiss) private var dismiss
    let disks: [NASDisk]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("全部磁盘")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text("\(disks.count) 个分区")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(disks) { d in
                        DiskTile(disk: d)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
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
