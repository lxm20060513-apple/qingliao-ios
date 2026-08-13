import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - v2.0.81 知识库管理（文档上传/列表/删除；聊天输入 @知识库 自动检索注入）

struct KBView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var docs: [[String: Any]] = []
    @State private var showImporter = false
    @State private var message: (ok: Bool, text: String)?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("上传文档（txt / md / PDF）")
                                .foregroundStyle(.primary)
                        }
                    }
                    Text("聊天时输入「@知识库 你的问题」，AI 会自动检索这些文档回答")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("文档（\(docs.count) 个）") {
                    if docs.isEmpty {
                        Text("暂无文档")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(docs, id: \.self) { d in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d["name"] as? String ?? "")
                                    .font(.system(size: 14, weight: .medium))
                                Text(docMeta(d))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await deleteDoc(d["name"] as? String ?? "") }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let m = message {
                    Section {
                        Text(m.text)
                            .font(.system(size: 12))
                            .foregroundStyle(m.ok ? .green : .red)
                    }
                }
            }
            .navigationTitle("知识库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await load() }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.plainText, .pdf,
                                                UTType(filenameExtension: "md") ?? .data,
                                                UTType(filenameExtension: "txt") ?? .data],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task { await uploadFiles(urls) }
                case .failure:
                    break
                }
            }
        }
    }

    private func load() async {
        if let j = try? await auth.json("/api/kb/list") {
            docs = j["docs"] as? [[String: Any]] ?? []
        }
    }

    /// v2.0.81：文档 meta 文案（拆分字符串插值，避免 Swift 6 类型检查超时）
    private func docMeta(_ d: [String: Any]) -> String {
        let chunks = (d["chunks"] as? Int) ?? 0
        let size = (d["size"] as? Int) ?? 0
        return "\(chunks) 个片段 · \(size) 字节"
    }

    private func uploadFiles(_ urls: [URL]) async {
        busy = true
        defer { busy = false }
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()
            var content = ""
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if ext == "pdf" {
                // PDF 用 PDFKit 提取文本（与发送 PDF 同款）
                content = extractPDFText(from: url) ?? ""
            } else {
                content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            guard !content.isEmpty else {
                message = (false, "\(name)：无法读取内容（扫描件 PDF 无文字层）")
                continue
            }
            if let j = try? await auth.json("/api/kb/upload", method: "POST",
                                            body: ["name": name, "content": content]) {
                let ok = (j["ok"] as? Bool) ?? false
                message = (ok, (j["message"] as? String) ?? (ok ? "已保存" : "上传失败"))
            } else {
                message = (false, "\(name)：请求失败")
            }
        }
        await load()
    }

    private func deleteDoc(_ name: String) async {
        if let j = try? await auth.json("/api/kb/delete", method: "POST", body: ["name": name]) {
            message = ((j["ok"] as? Bool) ?? false, j["message"] as? String ?? "")
        }
        await load()
    }

    /// PDFKit 提取文本（文本型 PDF 才有内容）
    private func extractPDFText(from url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var out = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                out += s + "\n"
            }
        }
        return out.isEmpty ? nil : out
    }
}
