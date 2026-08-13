import SwiftUI

// MARK: - v2.0.87 AI 记忆管理（记住用户偏好 → 对话自动参考）

struct MemoryView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String] = []
    @State private var newText = ""
    @State private var message: (ok: Bool, text: String)?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 添加区
                HStack(spacing: 8) {
                    TextField("如：我经常用 5G 网络 / 回答要简洁", text: $newText)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        add()
                    } label: {
                        Text("记住")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.accentColor,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                .padding(12)

                if let m = message {
                    Text(m.text)
                        .font(.system(size: 11))
                        .foregroundStyle(m.ok ? Color.green : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                }

                // 列表
                ScrollView {
                    VStack(spacing: 8) {
                        if entries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.tertiary)
                                Text("还没有记忆条目")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text("聊天时说「记住…」会自动保存，或手动添加")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 60)
                        } else {
                            ForEach(entries, id: \.self) { e in
                                HStack(spacing: 10) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.accentColor)
                                    Text(e)
                                        .font(.system(size: 13))
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button {
                                        Task { await remove(e) }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            }
            .navigationTitle("AI 记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        if let j = try? await auth.json("/api/memory/list") {
            entries = j["entries"] as? [String] ?? []
        }
    }

    private func add() {
        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            if let j = try? await auth.json("/api/memory/add", method: "POST", body: ["text": t]) {
                let ok = (j["ok"] as? Bool) ?? false
                message = (ok, j["message"] as? String ?? (ok ? "已记住" : "保存失败"))
                entries = j["entries"] as? [String] ?? entries
                if ok { newText = "" }
            } else {
                message = (false, "请求失败")
            }
        }
    }

    private func remove(_ text: String) async {
        if let j = try? await auth.json("/api/memory/delete", method: "POST", body: ["text": text]) {
            entries = j["entries"] as? [String] ?? entries
        }
    }
}
