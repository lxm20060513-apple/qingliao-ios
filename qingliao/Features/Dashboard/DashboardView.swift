import SwiftUI

// MARK: - 看板页（智能家居 2x3 可控制 + NAS 2x3 + 磁盘弹出式）

enum DashboardSheet: String, Identifiable {
    case lights, climate, service, disks, docker
    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth

    @State private var nas = NASStatus()
    @State private var haEntities: [HAEntity] = []
    @State private var router = RouterStatus()
    @State private var scrollPos = ScrollPosition()
    @State private var loaded = false
    @State private var activeSheet: DashboardSheet?
    // v2.0.72：Docker 容器数量（看板卡片状态）
    @State private var dockerContainerCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // v2.0.87u：右上角天气（小图标 + 温度）
            PageHeader(title: "看板", subtitle: "智能家居 · NAS 状态",
                       trailing: AnyView(WeatherBadge(temp: weatherTemp, code: weatherCode, city: weatherCity)))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("智能家居")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        DeviceCard(name: "开关", icon: "lightbulb.fill", value: haLights, sub: "\(lightsOn) 盏开启 · 点击控制", status: lightsOn > 0 ? .on : .off)
                            .onTapGesture { activeSheet = .lights }
                        DeviceCard(name: "空调", icon: "air.conditioner.horizontal", value: haClimate, sub: "\(climateOn) 台运行中 · 点击控制", status: climateOn > 0 ? .on : .off)
                            .onTapGesture { activeSheet = .climate }
                        DeviceCard(name: "门锁", icon: "lock.fill", value: haLockBattery, sub: "智能门锁", status: .on)
                        DeviceCard(name: "猫眼", icon: "video.fill", value: haDoorbellBattery, sub: haDoorbellOnline ? "在线" : "离线", status: haDoorbellOnline ? .on : .off)
                        DeviceCard(name: "安防", icon: "shield.fill", value: haAlarm, sub: haAlarmArmed ? "已布防" : "未布防", status: haAlarmArmed ? .on : .warn)
                        DeviceCard(name: "温度", icon: "thermometer", value: haTemp, sub: "室内温度", status: .on)
                    }

                    sectionTitle("NAS 面板")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        MeterCard(name: "CPU", icon: "cpu.fill", value: String(format: "%.1f%%", nas.cpu), sub: nil, ratio: nas.cpu / 100.0, color: .blue)
                        MeterCard(name: "内存", icon: "memorychip.fill", value: nas.memUsedText, sub: "/ \(nas.memTotalText)", ratio: nas.memPct, color: .green)
                        MeterCard(name: "磁盘", icon: "internaldrive.fill", value: String(format: "%.0f%%", nas.maxDiskPct), sub: "\(nas.disks.count) 个分区 · 点击查看", ratio: nas.maxDiskPct / 100.0, color: .orange)
                            .onTapGesture { activeSheet = .disks }
                        ServiceCard(name: "轻聊后端", icon: "server.rack", running: nas.qingliaoAlive, detail: nas.qingliaoMemText)
                            .onTapGesture { activeSheet = .service }
                        ServiceCard(name: "Hermes 网关", icon: "sparkles", running: nas.hermesAlive, detail: nas.hermesMemText)
                        // v2.0.72：Docker 管理卡片（点击弹部署弹窗）
                        ServiceCard(name: "Docker", icon: "shippingbox.fill", running: dockerContainerCount > 0,
                                    detail: dockerContainerCount > 0 ? "\(dockerContainerCount) 个容器 · 点击管理" : "暂无容器 · 点击部署")
                            .onTapGesture { activeSheet = .docker }
                        ServiceCard(name: "运行时间", icon: "clock.fill", running: true, detail: nas.uptime)
                        // v2.0.86：硬件温度（CPU / NVMe）
                        ServiceCard(name: "温度", icon: "thermometer", running: true, detail: hwDetail)
                    }

                    sectionTitle("路由器")
                    RouterPanel(router: router,
                                onStart: { clashAction("start") },
                                onStop: { clashAction("stop") },
                                onRefresh: { Task { await loadRouter() } })
                        .onAppear { Task { await loadRouter() } }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
            .scrollPosition($scrollPos)
            // v2.0.86h：Dock 滑动隐藏已删除（从未生效，手动开关替代）
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
                case .docker:
                    DockerSheet()
                        .presentationDetents([.medium, .large])
                }
            }
        }
        .task {
            if !loaded {
                await refresh()
                loaded = true
            }
            // v2.0.72：Docker 容器数量（卡片状态）
            await loadDockerCount()
            // v2.0.86：硬件温度（CPU / NVMe）
            await loadHw()
            // v2.0.87am：天气（右上角徽章；手动城市名）
            await loadWeatherWithCity()
            // 30s 自动刷新（v2.0.87c：10→30s，省电省流量，看板数据变化不敏感）
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await refresh()
                await loadHw()
            }
        }
    }

    // MARK: - 数据

    // v2.0.86：硬件温度状态
    @State private var hwCpu: Double?
    @State private var hwSsd: Double?
    // v2.0.87u：天气
    @State private var weatherTemp: Double?
    @State private var weatherCode: Int?
    @State private var weatherCity = UserDefaults.standard.string(forKey: "qingliao_weather_city") ?? ""   // v2.0.87am：手动城市

    private var hwDetail: String {
        let c = hwCpu.map { String(format: "CPU %.0f°C", $0) } ?? "CPU --"
        let s = hwSsd.map { String(format: "SSD %.0f°C", $0) } ?? "SSD --"
        return "\(c) · \(s)"
    }

    private func loadHw() async {
        if let j = try? await auth.json("/api/hw/status") {
            hwCpu = j["cpu_temp"] as? Double
            hwSsd = j["ssd_temp"] as? Double
        }
    }

    // v2.0.87u：天气加载（后端缓存 30 分钟）
    private func loadWeather() async {
        if let j = try? await auth.json("/api/weather") {
            weatherTemp = j["temp"] as? Double
            weatherCode = j["code"] as? Int
        }
    }

    // v2.0.87am：手动城市名 → 天气（未设置城市不显示徽章）
    private func loadWeatherWithCity() async {
        weatherCity = UserDefaults.standard.string(forKey: "qingliao_weather_city") ?? ""
        guard !weatherCity.isEmpty else {
            weatherTemp = nil
            weatherCode = nil
            return
        }
        let enc = weatherCity.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? weatherCity
        if let j = try? await auth.json("/api/weather?city=\(enc)") {
            weatherTemp = j["temp"] as? Double
            weatherCode = j["code"] as? Int
            if let c = j["city"] as? String, !c.isEmpty { weatherCity = c }
        }
    }

    private func loadRouter() async {
        if let j = try? await auth.json("/api/router/status") {
            router = RouterStatus.parse(j)
        }
    }

    /// 快捷指令：启动/关闭 Clash
    private func clashAction(_ action: String) {
        router.busy = true
        Task {
            defer { router.busy = false }
            if let j = try? await auth.json("/api/router/clash/\(action)", method: "POST", body: nil) {
                // v2.0.92：操作成功清空错误显示（失败原因由后端按"服务已启动"输出判断）
                if (j["ok"] as? Bool) == true {
                    router.error = ""
                }
                router = RouterStatus.merge(router, with: j)
            }
            await loadRouter()
        }
    }

    private func refresh() async {
        // 顺序请求（async let 返回值非 Sendable，Swift 6 严格并发下编译失败）
        if let n = try? await auth.json("/api/nas/status") {
            nas = NASStatus.parse(n)
        }
        if let h = try? await auth.jsonArray("/api/ha/states") {
            haEntities = h.compactMap { HAEntity.parse($0 as? [String: Any] ?? [:]) }
        }
        // v2.0.35：10s 轮询补上路由器（原来只在 onAppear 加载一次 →
        // 路由器重启后状态永远停在红点/离线，不会自动恢复）
        await loadRouter()
    }

    // MARK: - v2.0.72 Docker 容器数量

    private func loadDockerCount() async {
        if let j = try? await auth.json("/api/docker/ps") {
            dockerContainerCount = (j["containers"] as? [[String: Any]] ?? []).count
        }
    }

    // MARK: - HA 派生（与 PWA 相同挑选规则）

    private var lights: [HAEntity] {
        // 过滤指示灯（NAS 查询指示灯等不参与灯列表，改由 switch 开关实体控制）
        haEntities.filter {
            $0.entityID.hasPrefix("light.") && !$0.state.contains("unavailable")
                && !$0.entityID.contains("indicator_light")
        }
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
    @State private var running: Bool?   // 真实运行状态
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
                    Circle()
                        .fill(running == true ? Color.green : (running == false ? Color.red : Color.gray))
                        .frame(width: 7, height: 7)
                    Text(running == true ? "运行中" : (running == false ? "已停止" : "检测中"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(running == true ? Color.green : (running == false ? Color.red : Color.secondary))
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))  // v2.0.87h：弹窗玻璃下扁平化
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .task {
                // 真实运行状态
                if let n = try? await auth.json("/api/nas/status") {
                    let st = NASStatus.parse(n)
                    running = st.qingliaoAlive
                }
            }

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
                .background(Color(uiColor: .secondarySystemGroupedBackground))  // v2.0.87h：弹窗玻璃下扁平化
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
        // v2.0.87l：弹窗玻璃罩效果不佳（用户反馈）→ 全部回退普通背景
        .background(Color(uiColor: .systemBackground))
        .task { await load() }
    }

    // MARK: - 灯卡（PWA HomeKit 复刻：渐变图标容器 + 圆形小开关）

    private func lightCard(_ e: HAEntity) -> some View {
        let isOn = e.state == "on"
        // 拆成 AnyShapeStyle 单一类型（三元 LinearGradient vs Color 会让编译器类型检查超时）
        let iconBG: AnyShapeStyle = isOn
            ? AnyShapeStyle(LinearGradient(colors: [Color.yellow.opacity(0.30), Color.orange.opacity(0.18)],
                                           startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(Color(uiColor: .systemGray6))
        return Button {
            toggle(e)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // 图标容器：点亮=黄色渐变光晕 / 熄灭=灰底
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(iconBG)
                        Image(systemName: "sun.max.fill")
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
            // v2.0.87h：弹窗液态玻璃下卡片扁平化（去白圆角底，仅极轻底区分）
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
            )
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
        // 关闭模式统一置顶（所有空调卡片一致）
        let orderedModes = ["off"] + modes.filter { $0 != "off" }
        let isOn = e.state != "off" && e.state != "unavailable"

        return VStack(alignment: .leading, spacing: 10) {
            // 顶部：图标 + 名称/状态 + 电源（关闭按钮统一在最右）
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
                // 电源圆钮（统一贴最右）
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

            // 温度：目标大字 + 室温 + 步进
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", target))
                        .font(.system(size: 32, weight: .bold))
                    Text("°")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
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
                ForEach(orderedModes, id: \.self) { m in
                    Button {
                        setMode(e, mode: m)
                    } label: {
                        // v2.0.87k：判定 lowercased（HA 部分实体返回 "Off" 大写导致选中态不匹配）
                        let active = e.state.lowercased() == m
                        Text(modeName(m))
                            .font(.system(size: 11, weight: active ? .bold : .medium))
                            .foregroundStyle(active ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(active ? Color.accentColor : Color(uiColor: .systemGray5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(active ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            // v2.0.87j：弹窗玻璃下扁平化（渐变末端白底 → 轻透明）
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
        // switch 域实体（NAS 插座/消毒柜追加进灯列表）用 switch 服务域
        let d = e.entityID.hasPrefix("switch.") ? "switch" : domain
        callService(domain: d, service: "toggle", entityID: e.entityID, extra: nil)
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
            var list = all.filter {
                $0.entityID.hasPrefix(domain + ".") && !$0.state.contains("unavailable")
            }
            if domain == "light" {
                // 灯列表过滤指示灯（NAS 查询指示灯等不参与），追加 NAS 插座/消毒柜 switch 实体（可控制）
                list = list.filter { !$0.entityID.contains("indicator_light") }
                let extraSwitches = all.filter {
                    ["switch.chuangmi_cn_237985068_m3_on_p_2_1",
                     "switch.lumi_cn_lumi_158d00039bca0b_v1_on_p_2_1"].contains($0.entityID)
                }
                list.append(contentsOf: extraSwitches)
            }
            entities = list
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
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
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
    let icon: String   // v2.0.85e 图标
    let value: String
    let sub: String
    let status: DeviceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status == .on ? Color.accentColor : Color.secondary)
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))  // v2.0.87h：弹窗玻璃下扁平化
        // 浅色下卡片与白底融合 → 统一加细边框（深浅色通用：深色白边/浅色黑边）
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
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
    let icon: String   // v2.0.85c 图标
    let value: String
    let sub: String?
    let ratio: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                // 真实状态点：按使用率阈值（<75% 绿 / 75-90% 橙 / >90% 红）
                Circle()
                    .fill(ratio > 0.9 ? Color.red : (ratio > 0.75 ? Color.orange : Color.green))
                    .frame(width: 8, height: 8)
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
        // v2.0.83：NAS 面板卡片等高（与 ServiceCard 同高，进度条自适应剩余空间）
        // v2.0.86b：卡片统一再矮一点
        .frame(height: 88, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground))  // v2.0.87h：弹窗玻璃下扁平化
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ServiceCard: View {
    let name: String
    let icon: String   // v2.0.85c 图标
    let running: Bool
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(running ? Color.green : Color.red)
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
        // v2.0.83：NAS 面板卡片等高（与 MeterCard 同高）
        // v2.0.86b：卡片统一再矮一点
        .frame(height: 88, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - v2.0.87u 天气徽章（右上角小图标 + 温度）

struct WeatherBadge: View {
    let temp: Double?
    let code: Int?
    var city = ""   // v2.0.87ag：具体地点

    /// WMO 天气码 → SF Symbol 图标
    private var icon: String {
        guard let c = code else { return "cloud.fill" }
        switch c {
        case 0: return "sun.max.fill"
        case 1: return "sun.min.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    private var iconColor: Color {
        guard let c = code else { return .secondary }
        switch c {
        case 0, 1: return .orange
        case 2: return .yellow
        case 3: return .secondary
        case 45, 48: return .gray
        case 51...82: return .blue
        case 71...77: return .cyan
        case 95...99: return .purple
        default: return .secondary
        }
    }

    var body: some View {
        // v2.0.87x：胶囊下方标注"当前定位"（v2.0.87ab：去掉胶囊内定位图标，更简洁）
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                if let t = temp {
                    Text(String(format: "%.0f°", t))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text("--°")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.6))
            // v2.0.87aj：只显示城市名（去掉"当前定位"前缀）
            if !city.isEmpty {
                Text(city)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
