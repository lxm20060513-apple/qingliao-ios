import SwiftUI

// MARK: - v2.0.83c 连接设置二级页（服务器地址 / 测试连接 / 会话存储位置——从主设置页收进二级）
// v2.0.83f：List 白底改毛玻璃卡片风格（与主设置页 glassListCard 一致）

struct ConnSettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var showServerSheet = false
    @State private var showSessionLocSheet = false
    @State private var sessionLoc = ""
    @State private var testResult: String?
    @State private var testing = false

    private var shortServer: String {
        auth.serverURL
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
    }

    private var sessionLocShort: String {
        let parts = sessionLoc.split(separator: "/").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "…/" + parts.suffix(2).joined(separator: "/")
        }
        return sessionLoc.isEmpty ? "默认" : sessionLoc
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("服务器")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    VStack(spacing: 0) {
                        SettingRow(icon: "globe.asia.australia.fill", iconColor: .green,
                                   title: "服务器地址", value: shortServer, chevron: true)
                            .onTapGesture { showServerSheet = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "network", iconColor: .blue,
                                   title: "测试连接", value: testing ? "检测中..." : nil,
                                   chevron: !testing)
                            .onTapGesture { testConnection() }
                        if let r = testResult {
                            Text(r)
                                .font(.system(size: 11))
                                .foregroundStyle(r.hasPrefix("✅") ? Color.green : Color.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)
                                .padding(.top, 2)
                        }
                    }
                    .glassListCard()

                    Text("存储")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        SettingRow(icon: "tray.full.fill", iconColor: .teal,
                                   title: "会话存储位置", value: sessionLocShort, chevron: true)
                            .onTapGesture { showSessionLocSheet = true }
                    }
                    .glassListCard()
                    Text("会话记录保存在 NAS 指定目录，Web 与 App 共用同一份")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
                .padding(14)
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("连接设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showServerSheet) {
                ServerSheet()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSessionLocSheet) {
                SessionLocSheet(currentPath: sessionLoc)
                    .presentationDetents([.medium])
            }
            .task {
                // 拉取服务器端会话存储位置
                if let j = try? await auth.json("/api/sessions/location") {
                    sessionLoc = j["path"] as? String ?? ""
                }
            }
        }
    }

    private func testConnection() {
        guard !testing else { return }
        testing = true
        Task {
            defer { testing = false }
            do {
                let j = try await auth.json("/api/auth/status")
                let ok = (j["ok"] as? Bool) ?? false
                testResult = ok ? "✅ 连接正常，服务器：\(shortServer)" : "⚠️ 服务器响应异常"
            } catch {
                testResult = "❌ 无法连接：\(shortServer)"
            }
        }
    }
}
