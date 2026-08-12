import SwiftUI

// MARK: - v2.0.72 Docker 管理（docker compose 一键部署：名称 + YAML + 部署/停止/删除）

struct DockerSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var yaml = ""
    @State private var containers: [DockerContainer] = []
    @State private var message: (ok: Bool, text: String)?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 部署区
                    VStack(alignment: .leading, spacing: 8) {
                        Text("新建部署").font(.system(size: 13, weight: .semibold))
                        TextField("Docker 项目名（如 myapp）", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14))
                        TextEditor(text: $yaml)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 160)
                            .padding(6)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("输入 docker-compose YAML，确认后点击「部署」生效（目录自动创建于 /volume1/docker/项目名/）")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Button {
                            Task { await deploy() }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text(busy ? "部署中…" : "部署")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty
                                     || yaml.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // 结果
                    if let m = message {
                        Text(m.text)
                            .font(.system(size: 12))
                            .foregroundStyle(m.ok ? .green : .red)
                            .textSelection(.enabled)
                    }

                    // 容器列表
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("已部署容器").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button {
                                Task { await load() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        if containers.isEmpty {
                            Text("暂无容器").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 8)
                        } else {
                            ForEach(containers) { c in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(c.status.contains("Up") ? Color.green : Color.red)
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).font(.system(size: 13, weight: .medium))
                                        Text(c.status).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    // 停止 / 删除（仅对 compose 管理的项目显示，防止误停系统容器）
                                    if c.isComposeProject {
                                        Button {
                                            Task { await action(c.name, "stop") }
                                        } label: {
                                            Text("停止").font(.system(size: 11))
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.15))
                                                .clipShape(Capsule())
                                                .foregroundStyle(.orange)
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            Task { await action(c.name, "rm") }
                                        } label: {
                                            Text("删除").font(.system(size: 11))
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color.red.opacity(0.15))
                                                .clipShape(Capsule())
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Docker 管理")
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
        if let j = try? await auth.json("/api/docker/ps") {
            let arr = j["containers"] as? [[String: Any]] ?? []
            containers = arr.compactMap { d in
                guard let n = d["name"] as? String else { return nil }
                return DockerContainer(name: n,
                                       status: d["status"] as? String ?? "",
                                       ports: d["ports"] as? String ?? "",
                                       isComposeProject: n.hasPrefix("qlcompose_"))
            }
        }
    }

    private func deploy() async {
        busy = true
        defer { busy = false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let j = try? await auth.json("/api/docker/deploy", method: "POST",
                                        body: ["name": n, "yaml": yaml]) {
            let ok = (j["ok"] as? Bool) ?? false
            message = (ok, j["message"] as? String ?? (ok ? "部署成功" : "部署失败"))
            if ok {
                name = ""
                yaml = ""
            }
        } else {
            message = (false, "请求失败，请检查连接")
        }
        await load()
    }

    private func action(_ n: String, _ act: String) async {
        if let j = try? await auth.json("/api/docker/\(act)", method: "POST", body: ["name": n]) {
            let ok = (j["ok"] as? Bool) ?? false
            message = (ok, j["message"] as? String ?? "")
        }
        await load()
    }
}

struct DockerContainer: Identifiable {
    let name: String
    let status: String
    let ports: String
    let isComposeProject: Bool
    var id: String { name }
}
