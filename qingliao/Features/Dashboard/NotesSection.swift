import SwiftUI

// MARK: - v3.0.8 看板便签区（本地/云端看板共用）
// 样式对齐 DeviceCard：secondarySystemGroupedBackground + 0.8pt 描边 + 圆角16。
// 新增：右上 + 按钮 → 输入弹窗；删除：卡片右上 x（点击二次确认弹 alert）。

struct NotesSection: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NoteStore.self) private var notes

    @State private var showAdd = false
    @State private var input = ""
    @State private var adding = false
    @State private var confirmDelete: NoteItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("便签")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.top, 6)
                Spacer()
                Button {
                    showAdd = true
                } label: {
                    Label("新增", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 6)
            }

            if notes.isLoading && notes.notes.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("加载中…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            } else if notes.notes.isEmpty {
                // 空态（对齐智能建议空态卡风格）
                Button {
                    showAdd = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "note.text.badge.plus")
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                        Text("暂无便签，点此新增")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(notes.notes) { n in
                        noteRow(n)
                    }
                }
            }

            if let err = notes.errorText {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .task { await notes.load(auth: auth) }
        .sheet(isPresented: $showAdd) {
            addSheet
                .presentationDetents([.height(180)])
        }
        .alert("删除便签", isPresented: Binding(get: { confirmDelete != nil },
                                                set: { if !$0 { confirmDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let n = confirmDelete {
                    confirmDelete = nil
                    Task { _ = await notes.delete(id: n.id, auth: auth) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除这条便签，无法恢复。")
        }
    }

    /// 便签行：文本 + 右上删除（对齐 DeviceCard 信息布局）
    private func noteRow(_ n: NoteItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                confirmDelete = n
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 新增便签输入弹窗（顶部取消/保存，多行输入）
    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("新增便签")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("取消") { showAdd = false }
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                Button {
                    saveNew()
                } label: {
                    if adding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .disabled(adding || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextField("写点什么…", text: $input, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
        .presentationBackground(.regularMaterial)
    }

    private func saveNew() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        adding = true
        Task {
            let ok = await notes.add(trimmed, auth: auth)
            adding = false
            if ok {
                input = ""
                showAdd = false
            }
        }
    }
}