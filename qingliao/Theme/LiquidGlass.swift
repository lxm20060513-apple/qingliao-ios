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

struct GlassListCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect()
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
