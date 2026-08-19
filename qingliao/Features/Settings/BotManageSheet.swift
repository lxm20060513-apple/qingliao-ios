import SwiftUI

// MARK: - v3.0.7 Bot Mode：Bot 管理页（列表 / 新建 / 编辑 / 删除）
// 数据调 NAS /api/bots（AuthStore 统一网络层带 token；蜂窝/断网走现有分流）

struct BotManageSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BotStore.self) private var botStore
    @Environment(ChatStore.self) private var chat   // v3.0.7：删除选中 bot 时重置当前角色
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var editingBot: QingliaoBot?
    @State private var isNew = false
    @State private var confirmDelete: QingliaoBot?
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("Bot 管理")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 10)

            if botStore.isLoading && botStore.bots.isEmpty {
                Spacer()
                ProgressView().tint(.secondary)
                Spacer()
            } else if botStore.bots.isEmpty {
                // 空状态
                Spacer()
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.teal.opacity(0.25), Color.blue.opacity(0.15)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                        Image(systemName: "person.2.crop.square.stack.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.teal.opacity(0.7))
                    }
                    Text("还没有 Bot")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("创建专属人设的 AI 角色，各自独立会话")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(botStore.bots) { b in
                            botRow(b)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
            }

            if let err = botStore.errorText {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
            }

            // 新建按钮
            Button {
                editingBot = QingliaoBot(id: "", name: "", systemPrompt: "", model: "", provider: "", avatar: "")
                isNew = true
                showEdit = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("新建 Bot")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .task { await botStore.load(auth: auth, force: true) }
        .sheet(isPresented: $showEdit) {
            BotEditSheet(bot: editingBot ?? QingliaoBot(id: "", name: "", systemPrompt: "", model: "", provider: "", avatar: ""),
                         isNew: isNew)
                .presentationDetents([.large])
        }
        .alert("删除 Bot", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let b = confirmDelete {
                    confirmDelete = nil
                    deleting = true
                    Task {
                        let ok = await botStore.delete(id: b.id, auth: auth)
                        deleting = false
                        // 删的是当前聊天角色 → 落地为通用助手（BotStore 已重置选中）
                        if ok, chat.botId == b.id {
                            chat.botId = nil
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除「\(confirmDelete?.name ?? "")」。其历史会话保留，但不再按该 Bot 分组。")
        }
        .overlay {
            if deleting {
                ProgressView().tint(.secondary)
            }
        }
    }

    private func botRow(_ b: QingliaoBot) -> some View {
        HStack(spacing: 12) {
            // 头像（v3.0.7 beautify：sfs 符号 / emoji 统一渲染）
            b.avatarIcon(size: 18)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(colors: [Color.blue.opacity(0.18), Color.indigo.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(b.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(b.displayModel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "pencil.circle")
                .font(.system(size: 17))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            editingBot = b
            isNew = false
            showEdit = true
        }
        .contextMenu {
            Button {
                editingBot = b
                isNew = false
                showEdit = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDelete = b
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Bot 新建/编辑表单

struct BotEditSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BotStore.self) private var botStore
    @Environment(\.dismiss) private var dismiss

    let bot: QingliaoBot
    let isNew: Bool

    @State private var name = ""
    @State private var prompt = ""
    @State private var model = ""
    @State private var provider = ""
    @State private var avatar = ""
    @State private var saving = false
    @State private var errorText: String?

    init(bot: QingliaoBot, isNew: Bool) {
        self.bot = bot
        self.isNew = isNew
        _name = State(initialValue: bot.name)
        _prompt = State(initialValue: bot.systemPrompt)
        _model = State(initialValue: bot.model)
        _provider = State(initialValue: bot.provider)
        _avatar = State(initialValue: bot.avatar)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(isNew ? "新建 Bot" : "编辑 Bot")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    save()
                } label: {
                    if saving {
                        ProgressView().tint(.secondary)
                    } else {
                        Text("保存")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 12) {
                    fieldCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("名称 *").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("如：编程助手", text: $name)
                                .font(.system(size: 14))
                        }
                    }
                    fieldCard {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("人设 Prompt").font(.system(size: 11)).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(prompt.count)/500")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            TextEditor(text: $prompt)
                                .font(.system(size: 13))
                                .frame(minHeight: 110)
                                .scrollContentBackground(.hidden)
                                .onChange(of: prompt) { _, new in
                                    if new.count > 500 { prompt = String(new.prefix(500)) }
                                }
                            Text("留空使用默认人设「你是轻聊的 AI 助手…」")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    fieldCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("模型").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("留空用当前模型", text: $model)
                                .font(.system(size: 14))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    fieldCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("供应商 Provider").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("如：opencode / deepseek（留空用当前）", text: $provider)
                                .font(.system(size: 14))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    fieldCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("图标").font(.system(size: 11)).foregroundStyle(.secondary)
                            // v3.0.7 beautify：内置淡雅 SF Symbols 网格选择（点选即用；可再手动输入 emoji 微调）
                            // v3.0.8 CI fix：网格拆独立函数（原内联在 fieldCard 闭包内 type-check 超时）
                            iconGrid
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                TextField("或输入 emoji（如 🤖 🐱）", text: $avatar)
                                    .font(.system(size: 14))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    if let err = errorText {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    Text("提示：Bot 共享你的记忆，使用独立会话；每次对话默认带上其人设。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
    }

    private func fieldCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // v3.0.8 CI fix：内置图标网格拆独立属性（内联在 fieldCard 闭包内 type-check 超时）
    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(QingliaoBot.iconPresets) { p in
                Button {
                    avatar = p.id
                } label: {
                    Image(systemName: p.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(avatar == p.id ? Color.white : p.color)
                        .frame(width: 34, height: 34)
                        .background(
                            avatar == p.id
                                ? p.color
                                : p.color.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        errorText = nil
        let newBot = QingliaoBot(id: bot.id, name: trimmed,
                                 systemPrompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                 model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                                 provider: provider.trimmingCharacters(in: .whitespacesAndNewlines),
                                 avatar: avatar.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            let ok = await botStore.save(newBot, auth: auth)
            saving = false
            if ok {
                dismiss()
            } else {
                errorText = botStore.errorText ?? "保存失败"
            }
        }
    }
}