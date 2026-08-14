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
            let angle = (t * 22).truncatingRemainder(dividingBy: 360)   // v2.0.87bj：频率回第一版(22)
            // v2.0.87bl：GeometryReader 取容器尺寸 + 顶部补偿状态栏；只 ignoresSafeArea(.top)
            //（底部 dock 的 safe area 保持不动 → 根治 dock 偏位）
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height + geo.safeAreaInsets.top
                // v2.0.87bm：呼吸效果（透明度 sin 周期变化，0.25↔0.55）
                let breathe = 0.25 + 0.15 * (sin(t * 2.2) + 1) / 2
                Rectangle()
                    .fill(
                        AngularGradient(
                            colors: [.blue.opacity(0.30 * breathe), .indigo.opacity(0.26 * breathe),
                                     .pink.opacity(0.26 * breathe), .red.opacity(0.18 * breathe), .blue.opacity(0.30 * breathe)],
                            center: .center
                        )
                    )
                    .mask(
                        Path { p in
                            // v2.0.87bm：光带收窄到边框边缘（44→22pt，不挤进内容区）
                            let e: CGFloat = 22
                            p.addRect(CGRect(x: 0, y: 0, width: w, height: h))
                            p.addRect(CGRect(x: e, y: e, width: w - 2 * e, height: h - 2 * e))
                        }
                        .fill(style: FillStyle(eoFill: true))
                    )
                    .blur(radius: 8)
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}
