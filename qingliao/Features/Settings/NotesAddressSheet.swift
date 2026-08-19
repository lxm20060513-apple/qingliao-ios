import SwiftUI

// MARK: - v3.0.8 便签存储地址设置（仅本地模式）
// 留空 = 使用当前服务器（默认）；可填完整 base URL（如 http://192.168.31.40:16668）。
// 云端模式便签存 App 本地，此设置不出现（SettingsView 已按模式隐藏入口）。

struct NotesAddressSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("便签存储地址")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("完成") {
                    NoteStore.shared.customBase = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            }
            TextField("留空 = 当前服务器（\(auth.serverURL)）", text: $address)
                .font(.system(size: 13))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("便签保存在 NAS 本地（/data/notes.json）。留空使用当前服务器地址；\n也可填完整地址指向其他服务器。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
        }
        .padding(16)
        .presentationBackground(.regularMaterial)
        .onAppear {
            address = NoteStore.shared.customBase
        }
    }
}