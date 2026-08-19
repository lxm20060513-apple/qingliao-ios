import SwiftUI

// MARK: - v3.0.8 便签存储地址设置（仅本地模式）
// 填 NAS 绝对路径（如 /volume1/docker/hermes/微信文件/轻聊app/note），便签存到该目录 notes.json；
// 留空 = 服务器默认目录（/data）。云端模式便签存 App 本地，此设置不出现。

struct NotesAddressSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("便签存储地址")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("完成") {
                    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 校验：空 或 绝对路径
                    if !trimmed.isEmpty && !trimmed.hasPrefix("/") {
                        showError = true
                        return
                    }
                    NoteStore.shared.customDir = trimmed
                    dismiss()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            }
            TextField("如：/volume1/docker/hermes/微信文件/轻聊app/note", text: $address)
                .font(.system(size: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("便签以 notes.json 保存在该目录，支持在 NAS 文件管理器直接查看。\n留空 = 服务器默认目录（/data/notes.json）。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
            if showError {
                Text("请输入 NAS 绝对路径（以 / 开头），或留空使用默认目录")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .presentationBackground(.regularMaterial)
        .onAppear {
            address = NoteStore.shared.customDir
        }
    }
}