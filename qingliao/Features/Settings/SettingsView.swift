import SwiftUI

// MARK: - 设置页（iOS 设置风格分组列表）

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "设置")
            ScrollView {
                VStack(spacing: 0) {
                    // 账号
                    SectionHeader("账号")
                    VStack(spacing: 0) {
                        SettingRow(icon: "person.crop.circle.fill", iconColor: .blue, title: auth.username, value: "已登录", chevron: true)
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "key.horizontal.fill", iconColor: .gray, title: "修改密码", chevron: true)
                    }
                    .glassListCard()

                    // 连接
                    SectionHeader("连接")
                    VStack(spacing: 0) {
                        SettingRow(icon: "globe.asia.australia.fill", iconColor: .green, title: "服务器地址", value: shortServer, chevron: true)
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "cpu.fill", iconColor: .orange, title: "默认模型", value: "v4-flash", chevron: true)
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "network", iconColor: .blue, title: "测试连接", chevron: true)
                    }
                    .glassListCard()

                    // 功能
                    SectionHeader("功能")
                    VStack(spacing: 0) {
                        SettingRow(icon: "folder.fill", iconColor: .indigo, title: "文件管理", chevron: true)
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "clock.badge.fill", iconColor: .red, title: "定时任务", chevron: true)
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "doc.text.fill", iconColor: .orange, title: "日志", chevron: true)
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "clock.arrow.circlepath", iconColor: .cyan, title: "历史会话", chevron: true)
                    }
                    .glassListCard()

                    // 其他
                    SectionHeader("其他")
                    VStack(spacing: 0) {
                        SettingRow(icon: "info.circle.fill", iconColor: .gray, title: "关于轻聊", value: "2.0", chevron: true)
                        Divider().padding(.leading, 52)
                        Button {
                            auth.logout()
                        } label: {
                            HStack {
                                Spacer()
                                Text("退出登录")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .glassListCard()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
        }
    }

    private var shortServer: String {
        auth.serverURL
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 5)
    }
}

struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil
    var chevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(Rectangle())
    }
}
