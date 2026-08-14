import SwiftUI

// MARK: - 液态玻璃主题组件（iOS 26+ 原生 glassEffect 真液态玻璃）
// v2.0.87e：按 Apple 官方 Liquid Glass 规范——glassEffect 提供光泽/折射/边缘高光，
// 替换旧的 material+描边模拟（用户反馈不是真液态玻璃）

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            // 原生液态玻璃（iOS 26+，部署目标已 26）
            .glassEffect()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 液态玻璃自带边缘光泽，仅保留极轻描边增强边界
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 5)
    }
}

// v2.0.87g：设置页密集列表卡改回毛玻璃（glassEffect 在密集卡上透出背景光斑显脏，
// 单卡场景（看板 GlassCard）保留 glassEffect；列表用低调 material 保证文字可读）
// v2.0.87ac：浅色下去 thinMaterial 灰蒙板 → 白底 0.85（用户反馈灰色蒙板）
struct GlassListCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(
                scheme == .dark
                    ? AnyShapeStyle(.ultraThinMaterial)
                    : AnyShapeStyle(Color.white.opacity(0.85)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
    func glassListCard() -> some View {
        modifier(GlassListCard())
    }
}

// MARK: - 页面通用头部

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    // 真实状态点：默认不显示（装饰性绿点已废弃），需要状态指示的页面显式传入
    var showStatus: Bool = false
    var statusColor: Color = .green

    /// 显式 init：避免复杂调用处 memberwise init 推断导致类型检查超时
    init(title: String, subtitle: String? = nil, trailing: AnyView? = nil,
         showStatus: Bool = false, statusColor: Color = .green) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.showStatus = showStatus
        self.statusColor = statusColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                if let trailing { trailing }
            }
            if let subtitle {
                HStack(spacing: 5) {
                    if showStatus {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - v2.0.87bb 新版 Siri 边框发光特效（AI 回答时屏幕边缘渐变光晕）

struct SiriGlowOverlay: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t * 45).truncatingRemainder(dividingBy: 360)   // v2.0.87bg：光效频率加快(22→45)
            // v2.0.87bc：UIScreen 全尺寸（覆盖状态栏顶部，GeometryReader 在 safe area 内取不到全屏）
            let w = UIScreen.main.bounds.width
            let h = UIScreen.main.bounds.height
            // v2.0.87bf：恢复全屏四边光晕（dock 半透明玻璃透出底部光晕；dock 在发光上层不被盖）
            Rectangle()
                .fill(
                    AngularGradient(
                        colors: [.blue.opacity(0.30), .indigo.opacity(0.26),
                                 .pink.opacity(0.26), .red.opacity(0.18), .blue.opacity(0.30)],
                        center: .center, angle: .degrees(angle)
                    )
                )
                .mask(
                    Path { p in
                        let e: CGFloat = 44
                        // 外框（全屏）
                        p.addRect(CGRect(x: 0, y: 0, width: w, height: h))
                        // 内框挖空（四边均匀光带）
                        p.addRect(CGRect(x: e, y: e, width: w - 2 * e, height: h - 2 * e))
                    }
                    .fill(style: FillStyle(eoFill: true))
                )
                .blur(radius: 10)
                .frame(width: w, height: h)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
