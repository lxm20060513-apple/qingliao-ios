import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文件管理页（浏览 NAS 文件 / 下载分享 / 上传）

struct FileEntry: Identifiable {
    let name: String
    let isDir: Bool
    let size: Double
    let mtime: TimeInterval
    var id: String { name }
}

struct FilesView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var cwd = ""
    @State private var entries: [FileEntry] = []
    @State private var pathStack: [String] = []
    @State private var loading = true
    @State private var showImporter = false
    @State private var toast = ""
    @State private var downloading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("文件管理")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 6)

            // 路径面包屑
            HStack(spacing: 6) {
                if !pathStack.isEmpty {
                    Button {
                        cwd = ""
                        pathStack = []
                        Task { await load() }
                    } label: {
                        Text("根目录")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(cwd.isEmpty ? "微信文件" : cwd)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            if loading {
                Spacer()
                ProgressView().tint(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { e in
                            fileRow(e)
                            Divider().padding(.leading, 44)
                        }
                        if entries.isEmpty {
                            Text("空目录")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 40)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
                }
                .refreshable { await load() }
            }

            // 上传按钮
            Button {
                showImporter = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("上传文件到当前目录")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .background(Color(uiColor: .systemBackground))
        .task { await load() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await upload(url) }
            }
        }
        .overlay(alignment: .top) {
            if !toast.isEmpty {
                Text(toast)
                    .font(.system(size: 12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
    }

    private func fileRow(_ e: FileEntry) -> some View {
        Button {
            if e.isDir {
                pathStack.append(cwd)
                cwd = (cwd.isEmpty ? "" : cwd + "/") + e.name
                Task { await load() }
            } else {
                Task { await download(e) }
            }
        } label: {
            HStack(spacing: 10) {
                Text(icon(for: e))
                    .font(.system(size: 18))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(e.isDir ? "目录" : "\(sizeText(e.size)) · \(timeText(e.mtime))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if e.isDir {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据

    private func load() async {
        loading = true
        defer { loading = false }
        let path = cwd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        do {
            let j = try await auth.json("/api/files/list?path=\(path)")
            cwd = j["cwd"] as? String ?? cwd
            let raw = (j["entries"] as? [Any]) ?? []
            entries = raw.compactMap { d in
                guard let d = d as? [String: Any], let name = d["name"] as? String else { return nil }
                return FileEntry(name: name, isDir: (d["is_dir"] as? Bool) ?? false,
                                 size: (d["size"] as? Double) ?? 0,
                                 mtime: (d["mtime"] as? Double) ?? 0)
            }
        } catch {
            toast = "加载失败"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = "" }
        }
    }

    private func download(_ e: FileEntry) async {
        downloading = true
        defer { downloading = false }
        let path = ((cwd.isEmpty ? "" : cwd + "/") + e.name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        do {
            let (data, code) = try await auth.downloadFile("/api/files/download?path=\(path)")
            guard code == 200 else {
                toast = "下载失败（服务器返回 \(code)）"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = "" }
                return
            }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("qingliao_files", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(e.name)
            try data.write(to: fileURL)
            toast = "已下载到 App 文件目录"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = "" }
        } catch {
            toast = "下载失败"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = "" }
        }
    }

    private func upload(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let fileData = try? Data(contentsOf: url) else {
            toast = "读取文件失败"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = "" }
            return
        }
        let fileName = url.lastPathComponent
        do {
            _ = try await auth.uploadMultipart("/api/files/upload", fileName: fileName, data: fileData)
            toast = "上传成功"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = "" }
            await load()
        } catch {
            toast = "上传失败"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = "" }
        }
    }

    private func icon(for e: FileEntry) -> String {
        if e.isDir { return "📁" }
        let ext = e.name.lowercased().split(separator: ".").last.map(String.init) ?? ""
        if ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext) { return "🖼️" }
        if ["pdf"].contains(ext) { return "📕" }
        if ["mp3", "wav", "m4a", "flac"].contains(ext) { return "🎵" }
        if ["mp4", "mov", "mkv"].contains(ext) { return "🎬" }
        if ["ipa", "zip", "tar", "gz"].contains(ext) { return "📦" }
        return "📄"
    }

    private func sizeText(_ s: Double) -> String {
        if s >= 1_048_576 { return String(format: "%.1fM", s / 1_048_576) }
        if s >= 1024 { return String(format: "%.0fK", s / 1024) }
        return "\(Int(s))B"
    }

    private func timeText(_ t: TimeInterval) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: Date(timeIntervalSince1970: t))
    }
}

// MARK: - 定时任务页

struct CronTask: Identifiable {
    let id: String
    let name: String
    let cron: String
    let prompt: String
}

struct TasksView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var tasks: [CronTask] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("定时任务")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text("\(tasks.count) 个")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    showNewTask = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)

            if loading {
                Spacer()
                ProgressView().tint(.secondary)
                Spacer()
            } else if tasks.isEmpty {
                Spacer()
                Text("暂无定时任务")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tasks) { t in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.indigo.opacity(0.15))
                                    Image(systemName: "clock.badge.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.indigo)
                                }
                                .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Text(t.cron)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                // 立即运行
                                Button {
                                    runTask(t)
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            // 长按删除
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteTask(t)
                                } label: {
                                    Label("删除任务", systemImage: "trash")
                                }
                            }
                            Divider().padding(.leading, 62)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
                .refreshable { await load() }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task { await load() }
        .sheet(isPresented: $showNewTask) {
            NewTaskSheet()
                .presentationDetents([.medium])
        }
    }

    @State private var showNewTask = false

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let arr = try await auth.jsonArray("/api/cron/tasks")
            tasks = arr.compactMap { d in
                guard let d = d as? [String: Any], let id = d["id"] as? String else { return nil }
                return CronTask(id: id, name: d["name"] as? String ?? "未命名",
                                cron: d["cron"] as? String ?? "",
                                prompt: d["prompt"] as? String ?? "")
            }
        } catch {
            tasks = []
        }
    }

    /// 立即运行任务（POST /api/cron/tasks/{id}/run）
    private func runTask(_ t: CronTask) {
        Task {
            _ = try? await auth.request("/api/cron/tasks/\(t.id)/run", method: "POST", body: nil)
            await load()
        }
    }

    /// 删除任务（DELETE /api/cron/tasks/{id}）
    private func deleteTask(_ t: CronTask) {
        Task {
            _ = try? await auth.request("/api/cron/tasks/\(t.id)", method: "DELETE", body: nil)
            await load()
        }
    }
}

// MARK: - 日志页

struct LogsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var logs: [String] = []
    @State private var loading = true
    @State private var exportText = ""
    @State private var showExporter = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("日志")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    UIPasteboard.general.string = logs.joined(separator: "\n")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    exportText = logs.joined(separator: "\n")
                    showExporter = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)

            if loading {
                Spacer()
                ProgressView().tint(.secondary)
                Spacer()
            } else if logs.isEmpty {
                Spacer()
                Text("暂无日志")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task { await load() }
        .fileExporter(isPresented: $showExporter,
                      document: LogDocument(text: exportText),
                      contentType: .plainText,
                      defaultFilename: "qingliao-logs") { _ in }
    }

    /// 日志导出文档
    struct LogDocument: FileDocument {
        var text: String
        static var readableContentTypes: [UTType] { [.plainText] }
        init(text: String) { self.text = text }
        init(configuration: ReadConfiguration) throws {
            text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
        }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: Data(text.utf8))
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let j = try await auth.json("/api/logs/sys")
            if let arr = j["logs"] as? [String] {
                logs = arr
            } else if let arr = j["logs"] as? [[String: Any]] {
                logs = arr.compactMap { $0["msg"] as? String ?? $0["message"] as? String ?? $0["line"] as? String }
            }
        } catch {
            logs = []
        }
    }
}

// MARK: - 新建定时任务

struct NewTaskSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var cron = "0 9 * * *"
    @State private var prompt = ""
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("新建定时任务")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            TextField("任务名称（如：每日早报）", text: $name)
                .font(.system(size: 14))
                .textFieldStyle(.roundedBorder)
            TextField("Cron 表达式（如 0 9 * * *）", text: $cron)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $prompt)
                .font(.system(size: 13))
                .frame(height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("任务提示词（发给 AI 的执行指令）")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(8)
                    }
                }
            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundStyle(.red)
            }
            Button {
                save()
            } label: {
                HStack {
                    Spacer()
                    if saving { ProgressView().tint(.white) } else { Text("保存任务") }
                    Spacer()
                }
                .padding(.vertical, 11)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(.white)
                .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(saving || name.isEmpty || cron.isEmpty || prompt.isEmpty)
            Spacer()
        }
        .padding(18)
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            defer { saving = false }
            do {
                let j = try await auth.json("/api/cron/tasks", method: "POST", body: [
                    "name": name, "cron": cron, "prompt": prompt
                ])
                if (j["ok"] as? Bool) == true {
                    dismiss()
                } else {
                    errorText = (j["error"] as? String) ?? "保存失败"
                }
            } catch {
                errorText = "请求失败：\(error.localizedDescription)"
            }
        }
    }
}
