import SwiftUI

// MARK: - v2.0.74 Docker 管理（液态玻璃卡片化：部署卡 + 容器列表卡，易操作）

struct DockerSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var yaml = ""
    @State private var containers: [DockerContainer] = []
    @State private var message: (ok: Bool, text: String)?
    @State private var busy = false
    @FocusState private var focused: Bool
    @State private var confirmTarget: DockerContainer?
    // v2.0.86：镜像管理
    @State private var images: [DockerImage] = []
    @State private var confirmImage: DockerImage?

    /// YAML 常用模板（一键插入）
    private static let nginxTemplate = """
    services:
      app:
        image: nginx:latest
        container_name: app
        ports:
          - "8080:80"
        restart: unless-stopped
    """

    /// v2.0.86g：YAML 空态提示常量（拆分复杂字符串，规避 Swift 6 类型检查超时）
    private static let yamlHint = "services:\n  app:\n    image: nginx:latest\n    ports:\n      - \"8080:80\""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // ===== 新建部署卡 =====
                    VStack(alignment: .leading, spacing: 10) {
                        Label("新建部署", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)

                        // 项目名（实时预览目录）
                        TextField("项目名（如 myapp）", text: $name)
                            .font(.system(size: 14))
                            .focused($focused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                            )
                        if !name.isEmpty {
                            Text("目录：/volume1/docker/\(name)/")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        // YAML 编辑器
                        ZStack(alignment: .topTrailing) {
                            TextEditor(text: $yaml)
                                .font(.system(size: 12, design: .monospaced))
                                .focused($focused)
                                .frame(minHeight: 180)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                                )
                                // YAML 空态提示（v2.0.86g：内容提常量，减类型检查负载）
                                .overlay(alignment: .topLeading) {
                                    if yaml.isEmpty {
                                        Text(Self.yamlHint)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.tertiary.opacity(0.6))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                    }
                                }
                            // 模板按钮
                            if yaml.isEmpty {
                                Button {
                                    yaml = Self.nginxTemplate
                                } label: {
                                    Label("模板", systemImage: "text.badge.plus")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                            }
                        }

                        // 部署按钮（渐变蓝，确认后生效）
                        Button {
                            focused = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()   // v2.0.77 触感
                            Task { await deploy() }
                        } label: {
                            HStack(spacing: 8) {
                                if busy {
                                    ProgressView().tint(.white)
                                }
                                Text(busy ? "部署中…" : "部署")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [.blue, .indigo],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .foregroundStyle(.white)
                            .shadow(color: .blue.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty
                                     || yaml.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(busy || name.trimmingCharacters(in: .whitespaces).isEmpty
                                   || yaml.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )

                    // 结果
                    if let m = message {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: m.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(m.ok ? .green : .red)
                            Text(m.text)
                                .font(.system(size: 12))
                                .foregroundStyle(m.ok ? .green : .red)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((m.ok ? Color.green : Color.red).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }

                    // ===== 已部署容器卡 =====
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("已部署容器", systemImage: "shippingbox.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Text("\(containers.count) 个")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Button {
                                Task { await load() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }

                        if containers.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.tertiary)
                                Text("暂无容器，输入 YAML 点击部署")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        } else {
                            // v2.0.75：卡片网格（对标智能家居开关面板）：
                            // 单击卡片 = 停止容器；长按 = 删除确认
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(containers) { c in
                                    DockerContainerCard(container: c)
                                        .onTapGesture {
                                            // v2.0.76：卡片即开关——运行中单击停止，已停止单击启动
                                            // v2.0.77：触感反馈
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            let act = c.status.contains("Up") ? "stop" : "start"
                                            Task { await action(c.name, act) }
                                        }
                                        // v2.0.81：长按删除改 contextMenu（原 onLongPressGesture 与 onTapGesture
                                        // 手势冲突，快速点击偶发被吞；contextMenu 由系统协调长按+点击，互不干扰）
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                                confirmTarget = c
                                            } label: {
                                                Label("删除容器", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
                }

                // ===== v2.0.86 镜像管理（列表/删除，清理空间）=====
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("镜像管理", systemImage: "photo.stack")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.indigo)
                        Spacer()
                        Text("\(images.count) 个")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await loadImages() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.indigo)
                        }
                        .buttonStyle(.plain)
                    }
                    if images.isEmpty {
                        Text("暂无镜像")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        // v2.0.86c：镜像卡片（v2.0.86d：2x1 单列竖排，全宽卡）
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                            ForEach(images) { img in
                                DockerImageCard(image: img)
                                    .onTapGesture { confirmImage = img }
                            }
                        }
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
                .padding(14)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Docker 管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = false }
                }
            }
            .confirmationDialog("删除容器？", isPresented: .init(
                get: { confirmTarget != nil },
                set: { if !$0 { confirmTarget = nil } }
            ), presenting: confirmTarget) { c in
                Button("删除", role: .destructive) {
                    let target = c
                    confirmTarget = nil
                    Task { await action(target.name, "rm") }
                }
                Button("取消", role: .cancel) { confirmTarget = nil }
            } message: { c in
                Text(c.isComposeProject
                     ? "将移除容器「\(c.name)」（配置目录保留，可重新部署）"
                     : "⚠️「\(c.name)」不是 Docker 管理项目创建的容器，删除后不可恢复，请确认！")
            }
            // v2.0.86：镜像删除确认
            .confirmationDialog("删除镜像？", isPresented: .init(
                get: { confirmImage != nil },
                set: { if !$0 { confirmImage = nil } }
            ), presenting: confirmImage) { img in
                Button("删除", role: .destructive) {
                    let target = img
                    confirmImage = nil
                    Task { await rmImage(target.id) }
                }
                Button("取消", role: .cancel) { confirmImage = nil }
            } message: { img in
                Text("删除镜像「\(img.name)」？\n若仍有容器使用会删除失败")
            }
            .task { await load(); await loadImages() }
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
                                       isComposeProject: (d["is_compose"] as? Bool) ?? false)
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

// MARK: - v2.0.75 容器卡片（对标智能家居 DeviceCard：名称+状态点+运行状态+端口）

struct DockerContainerCard: View {
    let container: DockerContainer

    private var running: Bool { container.status.contains("Up") }
    private var color: Color { running ? .green : .red }

    /// v2.0.81：端口简化并入提示行（取第一个映射），所有卡片固定 3 行等高
    private var portSuffix: String {
        let tip = running ? "单击停止 · 长按删除" : "单击启动 · 长按删除"
        guard !container.ports.isEmpty else { return tip }
        let p = container.ports.components(separatedBy: ", ").first ?? container.ports
        return "\(tip) · \(p)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(container.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
            Text(running ? "运行中" : "已停止")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 6)
            Text(portSuffix)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .padding(12)
        .frame(height: 96, alignment: .top)   // v2.0.81：固定高度 → 所有卡片等高统一
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // 单击停止 / 长按删除 提示
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - v2.0.86 镜像

struct DockerImage: Identifiable {
    let name: String
    let id: String
    let size: String
    var idStr: String { id }
}

extension DockerSheet {
    func loadImages() async {
        if let j = try? await auth.json("/api/docker/images") {
            let arr = j["images"] as? [[String: Any]] ?? []
            images = arr.compactMap { d in
                guard let n = d["name"] as? String, let i = d["id"] as? String else { return nil }
                return DockerImage(name: n, id: i, size: d["size"] as? String ?? "")
            }
        }
    }

    func rmImage(_ imageID: String) async {
        if let j = try? await auth.json("/api/docker/image/rm", method: "POST",
                                        body: ["id": imageID]) {
            message = ((j["ok"] as? Bool) ?? false, j["message"] as? String ?? "")
        } else {
            message = (false, "请求失败")
        }
        await loadImages()
    }
}

// MARK: - v2.0.86c 镜像卡片（1x2 网格，对标容器卡样式；单击=删除确认）

private struct DockerImageCard: View {
    let image: DockerImage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.indigo)
                Text(image.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.85))
            }
            Text("\(image.id) · \(image.size)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.top, 6)
        }
        .padding(12)
        // v2.0.86e：去掉固定高度，与智能家居 DeviceCard（门锁卡）同风格自适应等高
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
