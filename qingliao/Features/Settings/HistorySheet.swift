import SwiftUI

// MARK: - v2.0.116 执行历史（自动化 + 场景，设置页入口）

struct HistorySheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var items: [HistoryItem] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                        Text(loaded ? "暂无执行记录" : "加载中…")
                            .font(.system(size: 16, weight: .semibold))
                        if loaded {
                            Text("自动化或场景执行后会在这里留痕")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(items) { h in
                        HStack(spacing: 12) {
                            Image(systemName: h.type == "自动化" ? "timer" : "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(h.type == "自动化" ? Color.orange : Color.purple,
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(h.type)「\(h.name)」")
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)
                                if !h.detail.isEmpty {
                                    Text(h.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Text(h.ts)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.quaternary)
                            }
                            Spacer()
                            Image(systemName: h.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(h.ok ? .green : .red)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("执行历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.large])
    }

    private func load() async {
        if let j = try? await auth.json("/api/history") {
            items = (j["history"] as? [[String: Any]] ?? []).map { HistoryItem($0) }
        }
        loaded = true
    }
}

struct HistoryItem: Identifiable {
    let id = UUID()
    let ts: String
    let type: String
    let name: String
    let ok: Bool
    let detail: String
    init(_ d: [String: Any]) {
        ts = d["ts"] as? String ?? ""
        type = d["type"] as? String ?? ""
        name = d["name"] as? String ?? ""
        ok = (d["ok"] as? Bool) ?? false
        detail = d["detail"] as? String ?? ""
    }
}
