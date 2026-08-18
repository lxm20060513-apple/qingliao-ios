import SwiftUI

// MARK: - v3.0 云端模式看板：只保留天气（直连 Open-Meteo，无需服务器）+ 其余待开发占位

struct CloudDashboardView: View {
    @State private var temp: Double?
    @State private var code: Int?
    @State private var city = UserDefaults.standard.string(forKey: "qingliao_weather_city") ?? ""
    @State private var loading = true
    @State private var errorText: String?
    @State private var showCitySheet = false
    @State private var cityInput = ""

    private let weatherURL = "https://api.open-meteo.com/v1/forecast"
    private let geocodeURL = "https://geocoding-api.open-meteo.com/v1/search"

    var body: some View {
        VStack(spacing: 0) {
            // v3.0.1：天气与本地 AI 同位置——右上角 WeatherBadge（小图标+温度+城市），点击换城市
            PageHeader(title: "看板",
                       subtitle: "云端模式",
                       trailing: AnyView(
                           Button {
                               showCitySheet = true
                           } label: {
                               WeatherBadge(temp: temp, code: code, city: city)
                           }
                           .buttonStyle(.plain)
                       ))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // 待开发占位（v3.0.1：天气已上移到右上角徽章，与本地 AI 看板一致；内容区暂无卡片）
                    VStack(spacing: 12) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                        Text("更多功能待开发")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("云端模式当前提供天气与 AI 聊天，\n更多能力将在后续版本加入")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .task { await loadWeather() }
        .sheet(isPresented: $showCitySheet) {
            VStack(spacing: 16) {
                Text("设置天气城市")
                    .font(.system(size: 17, weight: .bold))
                    .padding(.top, 24)
                TextField("城市名（如：北京）", text: $cityInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)
                Button("保存") {
                    let c = cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !c.isEmpty {
                        city = c
                        UserDefaults.standard.set(c, forKey: "qingliao_weather_city")
                        Task { await loadWeather() }
                    }
                    showCitySheet = false
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)
                Spacer()
            }
            .presentationDetents([.height(220)])
        }
    }

    /// 直连 Open-Meteo：城市 → 地理编码 → 当前天气
    private func loadWeather() async {
        loading = true
        errorText = nil
        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else {
            loading = false
            errorText = "请在右上角设置天气城市"
            return
        }
        do {
            // 1) 地理编码
            let enc = c.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c
            guard let gURL = URL(string: "\(geocodeURL)?name=\(enc)&count=1&language=zh") else {
                loading = false; errorText = "城市名无效"; return
            }
            let (gData, _) = try await URLSession.shared.data(from: gURL)
            guard let gObj = try? JSONSerialization.jsonObject(with: gData) as? [String: Any],
                  let results = gObj["results"] as? [[String: Any]],
                  let first = results.first,
                  let lat = first["latitude"] as? Double,
                  let lon = first["longitude"] as? Double else {
                loading = false; errorText = "未找到城市「\(c)」"; return
            }
            // 2) 当前天气
            guard let wURL = URL(string: "\(weatherURL)?latitude=\(lat)&longitude=\(lon)&current_weather=true") else {
                loading = false; errorText = "天气服务地址无效"; return
            }
            let (wData, _) = try await URLSession.shared.data(from: wURL)
            guard let wObj = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
                  let cur = wObj["current_weather"] as? [String: Any] else {
                loading = false; errorText = "天气数据解析失败"; return
            }
            temp = cur["temperature"] as? Double
            code = cur["weathercode"] as? Int
            // 城市名用地理解析结果（中文名更友好）
            if let name = first["name"] as? String {
                let adm = (first["admin1"] as? String) ?? ""
                city = adm.isEmpty ? name : "\(name) · \(adm)"
            }
            loading = false
        } catch {
            loading = false
            errorText = "无法连接天气服务"
        }
    }
}

// MARK: - WeatherBadge 图标/颜色静态方法（云端看板复用；原实例属性为 private 不可访问）

extension WeatherBadge {
    static func icon(for c: Int?) -> String {
        guard let c else { return "cloud.fill" }
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

    static func color(for c: Int?) -> Color {
        guard let c else { return .secondary }
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
}
