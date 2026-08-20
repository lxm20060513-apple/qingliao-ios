import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import AVFoundation
import Speech
import UIKit
import UserNotifications

// MARK: - v2.0.65 发送完成通知（Dock 轻跳）

extension Notification.Name {
    static let qingliaoSent = Notification.Name("qingliao_sent")
    // v2.0.102c：切回看板刷新通知（TabView 切 tab 在 iOS 27 不触发子页 onAppear 的兜底）
    static let qingliaoDashboardRefresh = Notification.Name("qingliao_dashboard_refresh")
    // v2.0.133f：离开看板通知——看板 30s 轮询在隐藏页也跑，切页时抢帧；隐藏时暂停轮询
    static let qingliaoDashboardLeave = Notification.Name("qingliao_dashboard_leave")
}

// MARK: - v2.0.60 通知点击直达会话（AppDelegate 捕获通知点击 → 存 sessionId）

// v2.0.64：@preconcurrency 抑制 Swift 6 的 delegate 跨 MainActor Sendable 检查
final class QingliaoAppDelegate: NSObject, UIApplicationDelegate,
                                 @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // v2.0.110：后台刷新（方案2推送）——iOS 定期唤醒 App，检查流式任务是否完成 →
    // 完成则发本地通知（侧载无 entitlement 也能用；唤醒间隔由系统决定，非实时）
    func application(_ application: UIApplication,
                     performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let server = UserDefaults.standard.string(forKey: "qingliao_server") ?? ""
        let token = UserDefaults.standard.string(forKey: "qingliao_token") ?? ""
        guard let d = UserDefaults.standard.dictionary(forKey: "qingliao_stream_pending"),
              let taskId = d["taskId"] as? String, !taskId.isEmpty,
              !server.isEmpty, !token.isEmpty else {
            completionHandler(.noData)
            return
        }
        var base = server
        if !base.hasPrefix("http") { base = "https://" + base }
        guard let url = URL(string: base + "/api/stream/" + taskId) else {
            completionHandler(.failed)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completionHandler(.failed)
                return
            }
            let status = j["status"] as? String ?? ""
            if status == "done" || status == "error" {
                // 回复完成 → 本地通知 + 清理持久化任务
                let sid = d["sessionId"] as? String
                NotificationHelper.notify(title: "轻聊", body: "AI 回复完成，点击查看", sessionId: sid)
                UserDefaults.standard.removeObject(forKey: "qingliao_stream_pending")
                completionHandler(.newData)
            } else {
                completionHandler(.noData)   // 未完成，等下次系统唤醒再查
            }
        }.resume()
    }

    // v2.0.63：用 completionHandler 版（async 版在 Swift 6 下 non-Sendable 参数报错）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let sid = response.notification.request.content.userInfo["qingliao_session"] as? String {
            UserDefaults.standard.set(sid, forKey: "qingliao_open_session")
        }
        completionHandler()
    }
}

// MARK: - v2.0.50 滚动位置检测（替代 .scrollPosition，DockVisibility 用）
// .scrollPosition 在 TabView 隐藏页内容清空时是已知崩溃点（SIGTRAP），
// 换 GeometryReader + PreferenceKey：滚动时上报内容区 minY，取负后语义同 scrollPos.y

/// v2.0.88：排队待发消息（AI 回答中发送，当前回答结束后自动逐条发送）
private struct PendingSend {
    let text: String
    let imageData: String?
}

// MARK: - v3.0.18 云端工具调用 UI 数据

/// v3.0.18：工具循环 escaping 闭包内的文本累积器（Swift 6 并发：闭包不能改捕获的局部 var）
@MainActor
final class CloudTextAccumulator {
    var text = ""
}

/// v3.0.18：工具确认弹窗状态门（@Observable @MainActor——pending 变化驱动 confirmationDialog 出现；60s 超时 @Sendable 闭包只捕获它）
@MainActor
@Observable
final class ToolConfirmGate {
    var pending: PendingToolConfirm?
    var onConfirm: ((Bool) -> Void)?
}

/// 工具执行结果卡片（显示在消息区，AI 气泡上方）
struct ToolCardItem: Identifiable {
    let id = UUID()
    let title: String
    let ok: Bool
}

/// 工具卡片视图（绿勾/红叉 + 标题）
struct ToolCardView: View {
    let item: ToolCardItem
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(item.ok ? .green : .red)
            Text(item.title)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }
}

struct ChatView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream
    @Environment(KeyboardObserver.self) private var kb
    @Environment(BotStore.self) private var botStore   // v3.0.7：Bot Mode

    @State private var inputText = ""
    @FocusState private var inputFocus: Bool
    @State private var sentOK = false
    @State private var serverOnline: Bool?   // 服务器连接状态（真实绿点）
    // v2.0.36：引用回复 / 图片查看器 / 导出
    @State private var quotedMessage: ChatMessage?
    @State private var viewerPayload: ImageViewPayload?
    @State private var showMoreMenu = false
    @State private var showExporter = false
    @State private var exportText = ""
    @State private var clearing = false          // v2.0.40 清空会话两步走标志
    // v2.0.43：快捷指令 / 搜索定位高亮
    @State private var showQuickPrompts = false
    @State private var highlightMessageID: String?
    // v2.0.46：隐藏 Dock 栏开关（开启时输入框贴底）
    @AppStorage("qingliao_hide_dock") private var hideDock = false
    // v2.0.59：上下文过长提示 / 失败重试
    @State private var showLongContextAlert = false
    @State private var pendingSend: (text: String, imageData: String?)?
    @State private var showModelSheet = false   // 模型快速切换
    @State private var showBotManage = false   // v3.0.7：Bot 管理入口（选择器内跳转）
    @State private var showAttachmentMenu = false
    // v2.0.96：Hermes 捷径面板（官方斜杠命令）
    @State private var showHermesShortcut = false
    // 大爆炸（BigBang）文本炸开
    @State private var bigBangPayload: BigBangPayload?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCameraPicker = false   // v2.0.38 拍照输入
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingImageData: String?
    // v2.0.96：语音转文字（长按发送按钮；v2.0.96c 改服务器 ASR——录音上传转写，侧载全兼容）
    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var voiceMode = false
    @State private var transcribing = false   // v2.0.100：语音转文字转换中（动画）
    @State private var transcribeToken = 0   // v2.0.101：转写代次（停止/新转写递增，旧 Task 结果作废）
    @State private var voiceAuthFailed = false
    // v3.0.19：语音指令闭环——长按智能球 = 语音指令（ASR 后自动发送执行 + TTS 播报），
    // 输入框语音按钮保持原"语音转文字"（voiceCommandMode=false 时走原路径）
    @State private var voiceCommandMode = false
    // v3.0.19：待播报会话（语音指令触发，回复完成后 TTS 播报摘要）
    // 生命周期：uploadAndTranscribe 置位 → sendCore 消费（标记 🎤 + 转 pendingVoiceSpeak）→ 清空
    @State private var pendingVoiceSpeakSid: String?
    // v3.0.19：一次性播报意图（sendCore 置 true，完成回调消费后清空；失败/停止路径自然不播）
    @State private var pendingVoiceSpeak = false
    @State private var sendingLock = false   // v2.0.102：发送锁（防双击双流竞态）
    @State private var fileSendBlocked = false   // v2.0.102：流式中发文件提示
    @State private var voiceTooShort = false   // v2.0.102：录音太短提示
    // v2.0.88：AI 回答中发送的消息队列（回答结束后自动逐条发送）
    @State private var pendingQueue: [PendingSend] = []
    // v2.0.132：智能球点击全屏粒子爆发（满屏散开特效层）
    @State private var showFullBurst = false
    // v3.0.18：云端工具调用——执行卡片 + 写操作确认弹窗（gate 类持有，超时闭包只捕获它）
    @State private var toolCards: [ToolCardItem] = []
    @State private var toolGate = ToolConfirmGate()

    // 模型/提供商可从模型管理面板选择（UserDefaults 持久化）
    // v2.0.48：改 @AppStorage——computed property 无观察机制，
    // 设置页切换模型后聊天页头部不刷新（模型实际生效但显示旧名）
    @AppStorage("qingliao_model") private var modelName = "deepseek-v4-flash"
    @AppStorage("qingliao_provider") private var provider = "opencode"

    /// 头部状态文案/颜色（独立计算属性，避免 body 内嵌套三元）
    private var headerSubtitle: String {
        serverOnline == nil ? "检测中" : (serverOnline == true ? "在线" : "离线")
    }
    private var headerColor: Color {
        serverOnline == true ? .green : (serverOnline == false ? .red : .gray)
    }

    // MARK: - v3.0.7 Bot 选择器

    /// 实际生效的 bot id：Bot 已删除（列表无此 id）→ 回落空（nil = 通用助手），
    /// 保证发送不带 bot 字段时后端恢复 KB 注入 + agent 分流（人设本身也没了）
    private var effectiveBot: String? {
        guard let id = chat.botId, botStore.bot(id) != nil else { return nil }
        return id
    }

    /// 输入栏上方角色切换条：当前角色胶囊 + 菜单（通用助手 / 各 Bot / 管理入口）
    /// v3.0.7 beautify：改为 header 右下紧凑胶囊（本地模式才显示）
    private var botSelectorBar: some View {
        let current = botStore.bot(chat.botId)
        return Menu {
                Button {
                    switchBot(to: nil)
                } label: {
                    // v3.0.11 fix：图标与胶囊内当前角色图标一致（v3.0.9 通用助手已改科幻图标）
                    Label(chat.botId == nil ? "✓ 通用助手" : "通用助手",
                          systemImage: "circle.hexagongrid.fill")
                }
                if !botStore.bots.isEmpty {
                    Divider()
                    ForEach(botStore.bots) { b in
                        Button {
                            switchBot(to: b.id)
                        } label: {
                            // v3.0.11 fix：菜单内头像跟随 Bot 设定的图标（原硬编码
                            // person.crop.circle.badge.checkmark，用户设定图标不显示）
                            Label {
                                Text(chat.botId == b.id ? "✓ \(b.name)" : b.name)
                            } icon: {
                                b.avatarIcon(size: 14)
                                    .frame(width: 20, height: 20)
                            }
                        }
                    }
                }
            Divider()
            Button {
                showBotManage = true
            } label: {
                Label("管理 Bot…", systemImage: "gearshape")
            }
        } label: {
            HStack(spacing: 5) {
                // v3.0.7 beautify：统一头像渲染（sfs 符号 / emoji）
                // v3.0.8 CI fix：some View 不能 ?? 拼接 Text，改用 @ViewBuilder Group
                // v3.0.8 beautify：通用助手用扁平头像符号（替代 emoji 🤖）
                Group {
                    if let c = current {
                        c.avatarIcon(size: 13)
                    } else {
                        // v3.0.9：通用助手科幻图标（六边形网格 = AI 感知网络）
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(current?.name ?? "通用助手")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // v3.0.7 beautify：毛玻璃胶囊 + 浅描边（定稿 UI：玻璃小元素 + 0.8pt 描边）
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    /// 切换聊天角色：先保存当前会话（快照捕获防清空竞态）→ 停流 → 换独立新会话 → 清输入态
    /// v3.0.7 fix：切换放 Task 内延迟到保存完成，且切前校验 botId 未再变（防快速连点 A→B→C 乱序）
    /// v3.0.11 fix（bot 串话根治）：先清排队队列、再停流——原顺序（先停流）会让 onFinished 的
    /// sendQueued 在队列清空前触发，用旧 bot 的会话/人设跨会话起新流 → 回答出现在新 bot 聊天里。
    /// 顺序与停止按钮（onStop）一致：clearPendingQueue → stream.stop。
    private func switchBot(to id: String?) {
        guard chat.botId != id else { return }
        let fromID = chat.botId
        let snapshotID = chat.sessionId
        let snapshotMessages = chat.messages
        let snapshotTitle = chat.title
        // v3.0.11：必须先清队列再停流（顺序反了 = 跨会话幽灵流）
        clearPendingQueue()
        if stream.isStreaming { stream.stop(auth: auth) }
        Task {
            if !snapshotMessages.isEmpty {
                await chat.saveToServer(auth: auth, sessionId: snapshotID,
                                        messages: snapshotMessages, title: snapshotTitle)
            }
            // 保存期间用户又切了其它角色 → 丢弃本次过期切换（最终以最后一次为准）
            guard chat.botId == fromID else { return }
            chat.switchBot(id: id)
        }
        inputText = ""
        pendingImage = nil
        pendingImageData = nil
        quotedMessage = nil
    }

    // MARK: - v3.0.7 fix：输入栏上方三个小条拆独立 property（body 瘦身，防 type-check 超时）

    /// 图片预览条（选图后显示）
    @ViewBuilder
    private var pendingImageBar: some View {
        if let img = pendingImage {
            HStack(spacing: 10) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("图片已选择，发送后 AI 可识别")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    pendingImage = nil
                    pendingImageData = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
    }

    /// 内联附件面板（类微信 + 面板：点击回形针展开）
    /// v2.0.96b：发牌弹出效果（每个按钮依次从底部弹出 + 回弹）
    @ViewBuilder
    private var attachmentMenuBar: some View {
        if showAttachmentMenu {
            HStack(spacing: 26) {
                menuButton("photo.on.rectangle", "图片", Color.blue, idx: 0) { showPhotoPicker = true }
                menuButton("doc.fill", "文件", Color.indigo, idx: 1) { showFileImporter = true }
                // v2.0.43：快捷指令（常用 prompt 模板）
                menuButton("bolt.fill", "指令", Color.orange, idx: 2) { showQuickPrompts = true }
                // v3.0.6 fix：Hermes 捷径仅本地 AI 显示（云端无，遵循「本地有/云端无」）
                if !CloudConfig.shared.isCloudMode {
                    menuButton("sparkles", "Hermes 捷径", Color.purple, idx: 3) { showHermesShortcut = true }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// 引用回复条（发送后自动清除）
    @ViewBuilder
    private var quotedReplyBar: some View {
        if let q = quotedMessage {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                Text(String(q.content.prefix(60)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    quotedMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    var body: some View {
        // v2.0.140：禁用系统键盘避让——ChatInputBar 已手动按 kb.topY 精确计算 bottom padding，
        // 系统默认避让叠加会双重上抬 → 输入框与键盘间留空隙（用户红线标注）。
        // 只保留手动控制，输入框精确贴键盘。
        VStack(spacing: 0) {
            PageHeader(title: "聊天",
                       subtitle: headerSubtitle,
                       trailing: AnyView(
                           // v3.0.7 beautify：Bot 角色胶囊移到 header（本地模式）；右侧跟更多菜单
                           HStack(spacing: 10) {
                               if !CloudConfig.shared.isCloudMode {
                                   botSelectorBar
                               }
                               Button {
                                   showMoreMenu = true
                               } label: {
                                   Image(systemName: "ellipsis.circle")
                                       .font(.system(size: 17, weight: .semibold))
                                       .foregroundStyle(Color.accentColor)
                               }
                               .buttonStyle(.plain)
                           }
                       ),
                       showStatus: true,
                       statusColor: headerColor)
            .confirmationDialog("聊天操作", isPresented: $showMoreMenu, titleVisibility: .visible) {
                Button("导出会话记录") {
                    exportText = chat.exportText()
                    showExporter = true
                }
                // v2.0.92：会话分享卡片（渲染精美图片 → 系统分享/微信）
                Button("分享会话卡片") {
                    shareSessionCard()
                }
                // v2.0.43：上下文信息 + 一键压缩
                Button("上下文：约 \(chat.contextInfo.tokens) tokens · \(chat.contextInfo.count) 条") {}
                Button("压缩上下文（保留最近 20 条）") {
                    if chat.compressContext() {
                        Task { await chat.saveToServer(auth: auth) }
                    }
                }
                // v2.0.116：AI 总结会话（走正常流式，AI 回复要点总结）
                Button("AI 总结会话") {
                    summarizeSession()
                }
                Button("清空本会话消息", role: .destructive) {
                    // v2.0.40：两步走清空——先切欢迎页分支（列表立即卸载，数据未动），
                    // 下一帧再清数据。列表销毁与数据清空完全错开，杜绝同帧崩溃。
                    clearing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(nil) { chat.clearMessages() }
                        clearing = false
                    }
                    Task { await chat.saveToServer(auth: auth) }
                }
                Button("取消", role: .cancel) {}
            }
            if sentOK {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("已送达 · 消息已发出")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .transition(.opacity)
            }
            messageList
            // v2.0.96：语音转文字模式——点消息区空白退出（透明拦截层，不盖输入框）
            if voiceMode {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { exitVoiceMode() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            // 图片预览条（选图后显示）
            pendingImageBar
            // 内联附件面板（类微信 + 面板：点击回形针展开）
            // v2.0.96b：发牌弹出效果（每个按钮依次从底部弹出 + 回弹）
            attachmentMenuBar
            // v2.0.36：引用回复条（发送后自动清除）
            quotedReplyBar
            // v3.0.7 beautify：Bot 选择器已移到 header（本地模式），此处不再单独占一行
            ChatInputBar(text: $inputText,
                         focused: $inputFocus,
                         streaming: stream.isStreaming,
                         onSend: { send() },
                         onStop: {
                             // v2.0.88：点停止 = 取消当前回答 + 清空排队消息（不再自动发）
                             clearPendingQueue()
                             stream.stop(auth: auth)
                         },
                         onPickAttachment: {
                             withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                 showAttachmentMenu.toggle()
                             }
                         },
                         onCamera: { showCameraPicker = true },
                        // v2.0.96：语音转文字（长按发送按钮）
                        voiceMode: voiceMode,
                        onVoiceModeToggle: { toggleVoiceMode(keyboardWasUp: kb.isVisible) },   // v2.0.109b：长按发送键保持键盘状态
                        transcribing: transcribing,   // v2.0.100：转换中动画
                        onCancelTranscribe: { stopTranscribe() },   // v2.0.101：停止转写
                        // v3.0.19：长按输入框 = 原语音转文字；长按智能球 = 语音指令（走 startVoiceCommand）
                        onLongPressInput: { keyboardWasUp in toggleVoiceMode(keyboardWasUp: keyboardWasUp) },
                        onBallLongPress: { startVoiceCommand() },
                        // v3.0.4：云端模式无后端 ASR → 关闭全部语音入口
                        voiceEnabled: !CloudConfig.shared.isCloudMode,
                        // v2.0.132：点击智能球 → 全屏粒子爆发（v2.0.133b：粒子寿命延至 1.2s 放烟花闪烁，特效层同步延长）
                        // v2.0.137：粒子寿命上限提至 1.45s，特效层同步延长到 1.55s
                        onFullBurst: {
                            showFullBurst = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                                showFullBurst = false
                            }
                        })   // v2.0.106/107：长按输入框进语音模式
                        // v2.0.129：球态输入框 —— 绑定会话 id，切会话重建复位（展开态在切会话后回球态）
                        .id(chat.sessionId)
                        // v2.0.135：消费输入栏区域的点击，防冒泡到消息区 ZStack 根手势误收键盘
                        // （TextField/按钮自身优先消费，此手势只兜底输入栏空白处）
                        .onTapGesture {}
                         // v2.0.37：键盘弹出时输入框贴键盘顶部（绝对坐标换算，0 空隙）；
            // v2.0.46：隐藏 Dock 栏开关开启时输入框贴底（不留 Dock 避让），否则留 86pt 避让贴底 Dock
            // v2.0.133e：动画时长/曲线跟随键盘系统动画（观察器已记录），完全同步无跳变
            .padding(.bottom, kb.isVisible
                     ? max(0, UIScreen.main.bounds.height - kb.topY)
                     : (hideDock ? 0 : 86))
        }
        // v2.0.140：禁用系统键盘避让——ChatInputBar 已手动按 kb.topY 精确算 bottom padding，
        // 系统默认避让叠加会双重上抬 → 输入框与键盘间留空隙（用户红线标注：让红线长度=0）
        // 注：.keyboardAvoidance(.disabled) 并非 SwiftUI 公开 API（CI 编译报 no member），
        // 用官方键盘避让 opt-out：.ignoresSafeArea(.keyboard)
        .ignoresSafeArea(.keyboard)
        .animation(.easeOut(duration: kb.animationDuration), value: kb.height)
        // v2.0.96：语音授权/转写失败提示（服务器 ASR：麦克风权限或转写无结果）
        .alert("语音转文字不可用", isPresented: $voiceAuthFailed) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("请检查麦克风权限（设置 → 轻聊 → 麦克风），或稍后重试。")
        }
        // v2.0.102：录音太短提示
        .alert("录音太短", isPresented: $voiceTooShort) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("说话时间太短，请按住说话至少 1 秒再松手。")
        }
        // v2.0.102：AI 回答中发文件提示
        .alert("AI 回答中", isPresented: $fileSendBlocked) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("AI 正在回答，稍等片刻再发送文件。")
        }
        // v3.0.18：云端工具写操作确认（日历/提醒/计时器）
        .confirmationDialog("确认执行？", isPresented: Binding(
            get: { toolGate.pending != nil },
            set: { if !$0 { toolGate.onConfirm?(false) } }
        ), titleVisibility: .visible) {
            Button("执行") { toolGate.onConfirm?(true) }
            Button("取消", role: .cancel) { toolGate.onConfirm?(false) }
        } message: {
            Text(toolGate.pending?.summary ?? "")
        }
        // v2.0.61：杀后台流式恢复（幂等——无持久化任务时静默返回）
        .task {
            await stream.restoreIfNeeded(auth: auth) { success, err in
                if success {
                    chat.upsertAssistant(stream.content, agent: stream.isAgent)
                } else {
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(err)" : stream.content + "\n\n⚠️ \(err)", agent: stream.isAgent)
                }
                Task { await chat.saveToServer(auth: auth) }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        // v2.0.38：拍照输入（拍完进图片预览条，确认后发送）
        .sheet(isPresented: $showCameraPicker) {
            CameraPicker { img in
                pendingImage = img
                pendingImageData = compressImage(img)
            }
        }
        // v2.0.43：快捷指令面板（点击填充输入框）
        .sheet(isPresented: $showQuickPrompts) {
            QuickPromptSheet(onPick: { prompt in
                inputText = prompt
                showAttachmentMenu = false
            }, includeKB: !CloudConfig.shared.isCloudMode)   // v3.0.6：知识库仅本地
            .presentationDetents([.medium, .large])
        }
        // v2.0.96：Hermes 捷径面板（官方斜杠命令，点击填充输入框）
        .sheet(isPresented: $showHermesShortcut) {
            HermesShortcutSheet { cmd in
                inputText = cmd
                showAttachmentMenu = false
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                sendFile(url)
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    pendingImage = img
                    pendingImageData = compressImage(img)
                }
                photoItem = nil
            }
        }
        // v2.0.132：智能球点击 → 全屏粒子爆发（满屏散开，纯视觉不挡交互）
        .overlay {
            if showFullBurst {
                FullScreenBurst()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showFullBurst)
    }

    // MARK: - 消息列表

    // v2.0.111：欢迎页独立于 ScrollView——不再受滚动容器背景/裁剪影响，logo 永远完整显示
    private var welcomeView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .indigo, .purple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                    .shadow(color: .indigo.opacity(0.25), radius: 12, y: 4)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
            Text("你好，我是轻聊")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("输入消息与 AI 对话")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    /// v3.0.15：流式输出气泡——拆独立计算属性（防 messageList 巨型 body type-check 超时）
    @ViewBuilder
    private var streamingBubble: some View {
        MessageBubble(
            message: ChatMessage(role: "assistant", content: stream.content, timestamp: nil, agent: stream.isAgent),
            onAIImageTap: { url in openAIImage(url) },   // v2.0.128：流式中 AI 图片可点（参数须在 streamingAvatar 前）
            streamingAvatar: true,   // v3.0.15：AI 输出中头像 = 粒子球
            streamingText: true   // v3.0.17：流式长文用 SwiftUI Text 渲染（根治 UITextView 锁窄缩小）
        )
        .id("streaming")
    }

    private var messageList: some View {
        ZStack {
            // v2.0.40：clearing 期间直接显示欢迎页（列表已卸载，数据稍后清空）
            if (chat.messages.isEmpty || clearing) && !stream.isStreaming {
                welcomeView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 120)
                    .id("welcome")
            } else {
            ScrollViewReader { proxy in
            ScrollView {
                // v2.0.40：LazyVStack → VStack（懒加载在批量移除时有复用状态残留，
                // 普通 VStack 全量渲染，移除只是简单数组变化，彻底绕开崩溃）
                // v2.0.132：VStack → LazyVStack——清空/新建已走两步走（先切欢迎页卸载
                // 列表再清数据），批量移除崩溃路径不复存在；长聊天记录仅渲染可见气泡，
                // 修复长文本滑动/左右切页卡顿
                LazyVStack(spacing: 10) {
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { idx, msg in
                            // v2.0.60：跨天 → 日期分隔线（微信式：昨天/M月d日）
                            if idx > 0,
                               let prevTs = chat.messages[idx - 1].timestamp,
                               let curTs = msg.timestamp,
                               !Calendar.current.isDate(Date(timeIntervalSince1970: curTs / 1000),
                                                       inSameDayAs: Date(timeIntervalSince1970: prevTs / 1000)) {
                                dateDivider(curTs)
                            }
                            // 相邻消息间隔 >5 分钟：插入居中时间分隔（微信式）
                            if idx > 0,
                               let prevTs = chat.messages[idx - 1].timestamp,
                               let curTs = msg.timestamp,
                               curTs - prevTs > 300_000 {
                                timeDivider(curTs)
                            }
                            MessageBubble(message: msg,
                                          isHighlighted: msg.id == highlightMessageID) {
                                regenerate(at: msg.id)
                            } onBigBang: {
                                bigBangPayload = BigBangPayload(text: msg.content)
                            } onQuote: {
                                // v2.0.36：引用回复（点击回复时输入框聚焦）
                                quotedMessage = msg
                                inputFocus = true
                            } onDelete: {
                                // v2.0.36：单条删除（按索引精确删除，防同内容 hash id 误删）
                                deleteMessage(msg)
                            } onShare: {
                                shareMessage(msg)
                            } onImageTap: {
                                // v2.0.62：相册式查看（收集全部图片消息翻页）
                                openImageViewer(for: msg)
                            } onRetry: {
                                // v2.0.59：失败消息重试
                                retryMessage(msg)
                            } onWithdraw: {
                                // v2.0.92：消息撤回（10 秒内）
                                withdrawMessage(msg)
                            } onAIImageTap: { url in
                                // v2.0.128：AI 消息内图片 → 打开大图查看器（单张）
                                openAIImage(url)
                            }
                            .id(msg.id)
                            // 气泡出现动效：淡入 + 轻微上移（灵动）
                            // v2.0.38：去掉 .animation(value: messages.count)——
                            // 批量清空（清空会话/新建会话）时全 cell 同时移除的 spring 动画曾导致闪退
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                                    removal: .opacity))
                        }
                        // v3.0.18：云端工具执行卡片（显示在流式气泡上方）
                        if !toolCards.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(toolCards) { card in
                                    ToolCardView(item: card)
                                }
                            }
                            .padding(.horizontal, 44)   // 左侧留出 AI 头像位
                            .transition(.opacity)
                        }
                        if stream.isStreaming {
                            if stream.content.isEmpty {
                                // 思考中动画（三点跳动，气泡加大版）
                                // v3.0.15：恢复 v3.0.12 之前的原始三点动画（思考球 orbits 粒子已移除，改由输出头像承担粒子球）
                                // v3.0.18：思考期头像也改为粒子球（38pt，用户要求全程粒子球头像）
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        OrbCanvasView(mode: .orbits, size: 38,
                                                      opts: OrbOpts(orbitN: 8, ghostN: 26, ghostR: 2.8, ghostA: 0.9,
                                                                    particles: 4, partR: 3.4, partRDepth: 2.6,
                                                                    rsPow: 0.6, rMin: 0.9),
                                                      dotColors: [
                                                        Color(red: 0.55, green: 0.72, blue: 1.0),
                                                        Color(red: 0.65, green: 0.55, blue: 1.0),
                                                        Color(red: 1.0, green: 0.60, blue: 0.85),
                                                        .white
                                                      ])
                                            .allowsHitTesting(false)
                                    }
                                    .frame(width: 38, height: 38)
                                    // v2.0.35：去掉"思考中"文字（用户要求），保留三点跳动动画
                                    TypingIndicator()
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 15)
                                        .background(Color(uiColor: .systemGray5))
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .frame(minHeight: 44)
                                    Spacer(minLength: 48)
                                }
                                .id("streaming")
                                .transition(.opacity)
                            } else {
                                streamingBubble
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .id("messages")   // v2.0.39：与欢迎页分支区分身份
                }
            // v2.0.50：.scrollPosition 在隐藏页内容清空时是已知崩溃点（新建会话=TabView
            // 隐藏页清空→scrollPos 更新异常→SIGTRAP）→ 换 GeometryReader + PreferenceKey 检测滚动
            // v2.0.111：消息区背景透明（ScrollView 默认白底遮住上方 logo/内容）
            .scrollContentBackground(.hidden)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                            value: geo.frame(in: .named("scrollspace")).minY)
                }
            )
            // v2.0.86h：Dock 滑动隐藏已删除（从未生效，手动开关替代）
            // v2.0.43：搜索定位——滚动到命中消息并高亮 2 秒
            .onChange(of: chat.highlightTarget?.content) { _, _ in
                guard let t = chat.highlightTarget,
                      let idx = chat.indexOfMessage(role: t.role, contentPrefix: t.content) else { return }
                let mid = chat.messages[idx].id
                highlightMessageID = mid
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(mid, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) { highlightMessageID = nil }
                }
            }
            // v2.0.58：两步走新建会话——先切欢迎页（列表卸载），下一帧再清数据
            // （v2.0.44 的切tab+延迟清空在 tab 过渡期仍崩，清空按钮的两步走才是稳定模式）
            .onChange(of: chat.pendingNewSession) { _, pending in
                guard pending else { return }
                clearing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    // v3.0.11 fix：新建会话前先清队列+停流——原实现旧流仍在跑，
                    // 回答内容会持续显示/落进新会话（同 bot 串话根因族）
                    clearPendingQueue()
                    if stream.isStreaming { stream.stop(auth: auth) }
                    withAnimation(nil) { chat.newSession() }
                    chat.pendingNewSession = false
                    clearing = false
                }
            }
            // v2.0.88：切换/新建会话 → 清空待发队列（避免排队消息发到别的会话）
            .onChange(of: chat.sessionId) {
                clearPendingQueue()
                toolCards = []   // v3.0.18：工具卡片跨会话残留清理
            }
            // 滚动消息区即收起键盘（微信式）
            .scrollDismissesKeyboard(.immediately)
            // v2.0.135：ScrollView 是 UIKit 桥接视图，其区域点击不冒泡到 ZStack 根手势
            // （v2.0.112b 把 onTapGesture 移到 ZStack 后，有消息时点空白收键盘失效，用户复报）
            // → ScrollView 自身也挂一个：点消息区空白收键盘（点气泡由 MessageBubble 手势优先消费，不受影响）
            .onTapGesture {
                inputFocus = false
            }
            .onChange(of: chat.messages.count) {
                scrollBottom(proxy)
            }
            .onChange(of: stream.content) {
                scrollBottom(proxy)
            }
        }
        }
        }
        // v2.0.112b：点消息区空白收键盘——原 onTapGesture 只挂 ScrollView（有消息才显示），
        // 欢迎页（无消息）状态点空白无法收键盘 → 移到 ZStack 根统一生效
        // v2.0.135：ZStack 无 contentShape 时透明空白不可命中（此前只有点 logo/气泡才触发收键盘）
        // → 补 contentShape(Rectangle()) 让整片区域可命中；有消息场景由 ScrollView 自身手势兜底
        .contentShape(Rectangle())
        .onTapGesture {
            inputFocus = false
        }
        .task {
            // 服务器连接状态检测（真实绿点）
            let r = await auth.testConnection(server: auth.serverURL)
            serverOnline = r.hasPrefix("✅")
            // v3.0.7：Bot 列表加载（节流版：5min 缓存内不重复请求，免切页触发网络+状态翻转）
            if !CloudConfig.shared.isCloudMode {
                await botStore.load(auth: auth)
            }
        }
        .sheet(isPresented: $showModelSheet) {
            ModelSheet(current: modelName)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBotManage) {
            // v3.0.7：Bot 管理（列表/新建/编辑/删除）
            BotManageSheet()
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $bigBangPayload) { payload in
            BigBangView(text: payload.text)
        }
        // v2.0.59：上下文过长提示（60+ 条建议压缩）
        .alert("上下文较长", isPresented: $showLongContextAlert) {
            Button("压缩后发送") {
                if let p = pendingSend {
                    chat.compressContext()
                    inputText = ""   // v2.0.102：确认发送才清空（取消保留草稿）
                    pendingImage = nil
                    pendingImageData = nil
                    sendCore(text: p.text, imageData: p.imageData)
                }
                pendingSend = nil
            }
            Button("直接发送") {
                if let p = pendingSend {
                    inputText = ""   // v2.0.102：确认发送才清空（取消保留草稿）
                    pendingImage = nil
                    pendingImageData = nil
                    sendCore(text: p.text, imageData: p.imageData)
                }
                pendingSend = nil
            }
            Button("取消", role: .cancel) { pendingSend = nil }
        } message: {
            Text("当前会话已 \(chat.messages.count) 条消息，继续发送可能接近模型上下文上限。压缩后仅保留最近 20 条（早期内容替换为摘要标记）。")
        }
        // v2.0.36：图片大图查看器（v2.0.62 相册翻页）
        .fullScreenCover(item: $viewerPayload) { p in
            ImageViewer(images: p.images, index: p.index)
        }
        // v2.0.36：导出会话记录
        .fileExporter(isPresented: $showExporter,
                      document: ChatLogDocument(text: exportText),
                      contentType: .plainText,
                      defaultFilename: "轻聊会话") { _ in }
        // v2.0.36：录音权限被拒提示
    }

    /// 思考中动画（三点跳动）
    struct TypingIndicator: View {
        @State private var animating = false
        var body: some View {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .offset(y: animating ? -4 : 4)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: animating)
                }
            }
            .onAppear { animating = true }
        }
    }

    /// 相邻消息间隔 >5 分钟的居中时间分隔
    private func timeDivider(_ ts: Double) -> some View {
        let d = Date(timeIntervalSince1970: ts / 1000)
        let text: String
        if Calendar.current.isDateInToday(d) {
            text = d.formatted(date: .omitted, time: .shortened)
        } else if Calendar.current.isDateInYesterday(d) {
            text = "昨天 " + d.formatted(date: .omitted, time: .shortened)
        } else {
            text = d.formatted(date: .abbreviated, time: .shortened)
        }
        return Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    /// v2.0.60：跨天日期分隔线（灰色胶囊，微信式）
    private func dateDivider(_ ts: Double) -> some View {
        let d = Date(timeIntervalSince1970: ts / 1000)
        let text: String
        if Calendar.current.isDateInToday(d) {
            text = "今天"
        } else if Calendar.current.isDateInYesterday(d) {
            text = "昨天"
        } else {
            text = d.formatted(date: .abbreviated, time: .omitted)
        }
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private func scrollBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if stream.isStreaming {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = chat.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - 发送

    /// v2.0.116：AI 总结会话（菜单按钮 → 自动发总结请求走正常流式）
    private func summarizeSession() {
        guard !chat.messages.isEmpty else { return }
        guard !stream.isStreaming else { return }
        sendCore(text: "请用简洁的要点总结我们这次对话（分点列出，突出结论和待办）", imageData: nil)
    }

    private func send() {
        var text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = pendingImageData
        // v2.0.88f：去掉 isStreaming 拦截——AI 回答中发送走 sendCore 排队路径
        guard !text.isEmpty || img != nil else { return }
        // v2.0.36：引用回复（markdown 引用块注入，AI 可见上下文）
        if let q = quotedMessage, !text.isEmpty {
            let quoted = q.content.replacingOccurrences(of: "\n", with: "\n> ")
            text = "> " + quoted + "\n\n" + text
        }
        // v2.0.102：清空输入框移到发送确认之后——长上下文弹窗点"取消"时草稿保留（修复草稿丢失）
        quotedMessage = nil
        if chat.messages.count > 60 {
            pendingSend = (text, img)
            showLongContextAlert = true
            return
        }
        inputText = ""
        pendingImage = nil
        pendingImageData = nil
        sendCore(text: text, imageData: img)
    }

    /// v2.0.59：发送核心（send / 失败重试共用）
    /// v2.0.88：AI 回答中发送不再被拦截——消息上屏 + 入队，当前回答结束后自动逐条发送
    /// v2.0.102：sendingLock 同步置位——防极快双击时 isStreaming 尚未置位导致双流竞态
    private func sendCore(text: String, imageData: String?) {
        guard !text.isEmpty || imageData != nil else { return }
        // v3.0.19 review fix #1：语音指令标志在此一次性消费——标记本消息 + 转播报意图 + 清空 sid
        // （原实现只在主路径标记，排队/失败/切会话路径会悬挂 → 误标下一条 + 无故 TTS）
        let isVoiceCommandSend = pendingVoiceSpeakSid == chat.sessionId
        if isVoiceCommandSend {
            pendingVoiceSpeakSid = nil
            pendingVoiceSpeak = true
        }
        // v2.0.126：蜂窝 relay 3.5KB 限制自动分段（粘贴长文本不丢内容）
        // relay payload = base64url(JSON{m,p,h,b}) 进 URL；限制 ~3.5KB；WiFi 直连无限制不走此分支
        if imageData == nil, NetworkMonitor.shared.isCellular, text.count > 200 {
            let hist = chat.historyPayload()
            if relayPayloadLength(messages: hist + [["role": "user", "content": text]]) > 3400 {
                let chunks = splitLongText(text)
                if chunks.count > 1 {
                    // 顺序：第一段先发（流式中走排队路径排最前），后续段再入队
                    sendCore(text: chunks[0], imageData: nil)
                    for c in chunks.dropFirst() {
                        var m = ChatMessage.local(role: "user", content: c, imageDataURL: nil)
                        m.queued = true
                        withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                            chat.append(m)
                        }
                        pendingQueue.append(PendingSend(text: c, imageData: nil))
                    }
                    Task { await chat.saveToServer(auth: auth) }
                    return
                }
            }
        }
        if stream.isStreaming {
            // 排队路径：消息立即显示（标记排队中），回答结束后自动发送
            var msg = ChatMessage.local(role: "user", content: text, imageDataURL: imageData)
            msg.queued = true
            // v3.0.19 review fix #5：排队路径也应用 🎤 标记（sendCore 开头已消费标志）
            if isVoiceCommandSend {
                msg.voiceCommand = true
            }
            withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                chat.append(msg)
            }
            pendingQueue.append(PendingSend(text: text, imageData: imageData))
            Task { await chat.saveToServer(auth: auth) }
            return
        }
        guard !sendingLock else { return }   // 双击保护：第一次发送的流尚未置位时，第二次直接忽略
        sendingLock = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // v2.0.65：发送通知 → Dock 聊天图标轻跳
        NotificationCenter.default.post(name: .qingliaoSent, object: nil)
        var msg = ChatMessage.local(role: "user", content: text, imageDataURL: imageData)
        // v3.0.19：语音指令触发的消息打 🎤 标记（sendCore 开头已消费标志）
        if isVoiceCommandSend {
            msg.voiceCommand = true
        }
        // v2.0.59：单条插入动效（批量移除才崩，插入安全）
        withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
            chat.append(msg)
        }
        startStream(for: msg)
    }

    /// v2.0.88：启动流式回答（消息已在列表；失败标记/回复完成/队列联动统一在这里）
    /// v2.0.102：记录发起会话——回答期间切换会话则丢弃结果（防跨会话污染）；完成回调释放 sendingLock
    /// v3.0：云端模式走 CloudBackend 直连 SSE（不经过 NAS 后端）
    private func startStream(for msg: ChatMessage) {
        // v3.0 云端模式：直连大模型 API
        if CloudConfig.shared.isCloudMode {
            startCloudStream(for: msg)
            return
        }
        // v2.0.126：蜂窝 relay 3.5KB 限制——历史从后往前保留直到 payload 达标（只影响蜂窝兜底路径）
        var history = chat.historyPayload()
        if NetworkMonitor.shared.isCellular {
            history = relaySafeHistory(history)
        }
        let startSid = chat.sessionId

        Task {
            await stream.start(
                auth: auth,
                sessionId: chat.sessionId,
                model: modelName,
                provider: provider,
                messages: history,
                bot: effectiveBot
            ) { success, error in
                sendingLock = false   // 无论结果，先释放发送锁
                guard chat.sessionId == startSid else { return }   // 已切换会话 → 本次结果丢弃
                if !success {
                    chat.markFailed(id: msg.id)   // v2.0.59 失败标记 → 重试按钮
                    // v3.0.19：限流错误友好提示（sensenova 等免费额度 tpm 爆了 → 提示换路由）
                    let friendly = Self.friendlyStreamError(error)
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(friendly)" : stream.content + "\n\n⚠️ \(friendly)", agent: stream.isAgent)
                } else {
                    chat.upsertAssistant(stream.content, agent: stream.isAgent)
                    showSentOK()
                    // v3.0.19：语音指令回复完成 → TTS 播报摘要
                    speakVoiceResultIfNeeded(stream.content)
                    // v2.0.36：App 退后台时 AI 回复完成发本地通知（v2.0.60 携带会话 id）
                    if UIApplication.shared.applicationState != .active {
                        NotificationHelper.notify(title: "轻聊", body: "AI 回复完成，点击查看",
                                                  sessionId: chat.sessionId)
                    }
                }
                // 保存会话到后端（会话记录同步）
                // v3.0.11 fix：快照参数化——同步捕获 sid/messages/title，防止 Task 延迟执行时
                // 读到切换后的新会话（空/新 bot 消息）而把内容存错会话
                let saveSid = chat.sessionId
                let saveMsgs = chat.messages
                let saveTitle = chat.title
                Task { await chat.saveToServer(auth: auth, sessionId: saveSid, messages: saveMsgs, title: saveTitle) }
                // v2.0.88：回答完成（成功/失败/停止）→ 自动发送队列中的下一条
                if !pendingQueue.isEmpty {
                    let next = pendingQueue.removeFirst()
                    sendQueued(next)
                }
            }
        }
    }

    // MARK: - v3.0 云端流式直连（SSE 增量拼接，UI 与本地模式一致）

    /// 云端模式回答：直连 OpenAI 兼容端点，逐段追加 assistant 内容
    /// v3.0.18：改用 stream.content 驱动 streamingBubble（粒子头像 + SwiftUI Text 渲染），结束落库；
    ///         接入 CloudToolLoop 本地工具调用（function calling：日历/提醒/计时器/天气/剪贴板/计算器/通知）
    private func startCloudStream(for msg: ChatMessage) {
        let startSid = chat.sessionId
        // v3.0.18：启用流式气泡（三点 / 粒子头像 / Text 渲染）
        stream.isStreaming = true
        stream.isDone = false
        stream.content = ""
        stream.isAgent = false
        toolCards = []
        CloudBackend.shared.isStreaming = true   // v3.0.2：标记云端流式进行中（驱动 Siri 发光）
        Task {
            defer {
                sendingLock = false
                stream.isStreaming = false
                stream.isDone = true
                CloudBackend.shared.isStreaming = false
            }
            do {
                let history = chat.historyPayload()
                // v3.0.18：工具循环内 escaping 闭包修改局部 var 触发 Swift 6 并发错误 → 用 @MainActor 容器
                let acc = CloudTextAccumulator()
                // v3.0.18：工具循环（确认弹窗 → 执行 → 回传 → 最终文本）
                // 注：ChatView 是 struct，闭包直接捕获 self（值捕获；@State 底层是引用存储，修改仍生效）
                let finalText = await CloudToolLoop.shared.run(
                    messages: history,
                    confirmHandler: { [self] pending in
                        // v3.0.18 review：确认弹窗期间切了会话 → 拒绝执行（防日历/提醒建到别的会话场景）
                        guard self.chat.sessionId == startSid else { return false }
                        return await self.confirmToolRun(pending)
                    },
                    events: { [self, acc] event in
                        guard self.chat.sessionId == startSid else { return }
                        switch event {
                        case .text(let delta):
                            acc.text += delta
                            self.stream.content = acc.text
                        case .toolCard(let title, let ok):
                            self.toolCards.append(ToolCardItem(title: title, ok: ok))
                        case .done(let full):
                            acc.text = full
                            self.stream.content = full
                        case .error(let err):
                            // v3.0.18 review fix #3：错误同时拼入 acc——run 返回 nil 后落库走 acc.text 路径，真实错误不丢失
                            // v3.0.19：限流错误友好提示（与本地模式一致）
                            let friendly = Self.friendlyStreamError(err)
                            let errText = acc.text.isEmpty ? "⚠️ " + friendly : acc.text + "\n\n⚠️ " + friendly
                            acc.text = errText
                            self.stream.content = errText
                        }
                    }
                )
                guard chat.sessionId == startSid else { return }
                if let finalText, !finalText.isEmpty {
                    // 落库 assistant 消息（替换掉 streamingBubble）
                    chat.upsertAssistant(finalText)
                    showSentOK()
                    // v3.0.19：语音指令回复完成 → TTS 播报摘要
                    speakVoiceResultIfNeeded(finalText)
                    if UIApplication.shared.applicationState != .active {
                        NotificationHelper.notify(title: "轻聊", body: "AI 回复完成，点击查看",
                                                  sessionId: chat.sessionId)
                    }
                } else if acc.text.isEmpty {
                    chat.markFailed(id: msg.id)
                    chat.upsertAssistant("⚠️ 云端未返回内容")
                } else {
                    chat.upsertAssistant(acc.text)
                }
                CloudSessionStore.shared.saveChat(store: chat)
                finishCloudQueue()
            } catch {
                guard chat.sessionId == startSid else { return }
                chat.markFailed(id: msg.id)
                chat.upsertAssistant("⚠️ \(error.localizedDescription)")
                CloudSessionStore.shared.saveChat(store: chat)
                finishCloudQueue()
            }
        }
    }

    /// v3.0.18：工具写操作确认弹窗（await 用户点确认/取消；60s 无响应自动取消防挂死）
    /// 超时 @Sendable 闭包只捕获 toolGate（@MainActor 类），不捕获 ChatView struct
    private func confirmToolRun(_ pending: PendingToolConfirm) async -> Bool {
        await withCheckedContinuation { cont in
            toolGate.pending = pending
            toolGate.onConfirm = { ok in
                cont.resume(returning: ok)
                self.toolGate.pending = nil
                self.toolGate.onConfirm = nil
            }
            // 兜底：60s 用户无操作 → 自动取消（防 continuation 永不 resume 挂死工具循环）
            let gate = toolGate
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                guard gate.onConfirm != nil else { return }
                gate.onConfirm?(false)
            }
        }
    }

    /// 云端流式增量：更新最后一条 assistant 消息内容（流式过程中不追加新消息，只更新）
    private func cloudUpsertDelta(_ text: String) {
        if let idx = chat.messages.indices.last,
           chat.messages[idx].role == "assistant" {
            // 更新最后一条 assistant（重建 struct，保留时间戳）
            let old = chat.messages[idx]
            chat.messages[idx] = ChatMessage(role: "assistant", content: text,
                                             timestamp: old.timestamp ?? Date().timeIntervalSince1970 * 1000)
        } else {
            // 无 assistant 尾巴 → 新建（首段）
            chat.upsertAssistant(text)
        }
    }

    /// 云端模式回答完成 → 自动发送队列下一条
    private func finishCloudQueue() {
        if !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            sendQueued(next)
        }
    }

    // MARK: - v2.0.126 蜂窝 relay 3.5KB 限制（粘贴长文本自动分段）

    /// 模拟 SafariRelay.relay 的最终 URL 长度：payload={m,p,h,b} → base64url → /r?r=<b64>
    /// 用于发送前预判是否超限（限制 ~3.5KB = 3584，保守取 3400）
    /// v3.0.7：bot 字段同步进估算（与 streamStart payload 一致，否则低估长度导致 relay 超限）
    private func relayPayloadLength(messages: [[String: Any]]) -> Int {
        var body: [String: Any] = ["sessionId": chat.sessionId,
                                   "model": modelName,
                                   "provider": provider,
                                   "messages": messages,
                                   "pushEnabled": false,
                                   "agentEnabled": true]
        if let b = effectiveBot, !b.isEmpty { body["bot"] = b }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyStr = String(data: bodyData, encoding: .utf8) else { return Int.max }
        let payload: [String: Any] = ["m": "POST", "p": "/api/stream/start", "b": bodyStr]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return Int.max }
        let b64Len = Int(ceil(Double(jsonData.count) * 4 / 3))   // base64url ≈ 4/3 膨胀
        return auth.serverURL.count + 8 + b64Len                 // https://host:port/r?r=
    }

    /// 蜂窝下历史从后往前保留，直到 payload ≤ 3400（AI 至少看到最近上下文 + 新消息）
    private func relaySafeHistory(_ history: [[String: Any]]) -> [[String: Any]] {
        let limit = 3400
        if relayPayloadLength(messages: history) <= limit { return history }
        var kept: [[String: Any]] = []
        for m in history.reversed() {
            let test = [m] + kept
            if relayPayloadLength(messages: test) <= limit {
                kept = test
            } else { break }
        }
        return kept
    }

    /// 长文本拆段：每段使「历史 + 该段」payload ≤ 3400（二分最大前缀，至少 1 字符防死循环）
    private func splitLongText(_ text: String) -> [String] {
        let limit = 3400
        let baseHistory = chat.historyPayload()
        var chunks: [String] = []
        var rest = text
        while !rest.isEmpty {
            var lo = 1, hi = rest.count
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                let prefix = String(rest.prefix(mid))
                let len = relayPayloadLength(messages: baseHistory + [["role": "user", "content": prefix]])
                if len <= limit - 100 { lo = mid } else { hi = mid - 1 }
            }
            let take = max(1, lo)
            chunks.append(String(rest.prefix(take)))
            rest = String(rest.dropFirst(take))
        }
        return chunks
    }

    /// v2.0.88：发送排队消息（消息已上屏——去掉排队标记复用该消息启动流式，不重复插入）
    private func sendQueued(_ item: PendingSend) {
        guard !stream.isStreaming else { return }
        // firstIndex = FIFO：先入队的先发（内容相同也会按入队顺序）
        if let idx = chat.messages.firstIndex(where: {
            $0.queued && $0.content == item.text && $0.imageDataURL == item.imageData
        }) {
            chat.messages[idx].queued = false
            startStream(for: chat.messages[idx])
        }
        // v2.0.102：排队消息已不在列表（被删除/清空/切换）→ 直接丢弃，不重发（修复"删除后复活"）
    }

    /// v2.0.88：取消排队（停止按钮/切换会话）——清队列 + 消息恢复"已送达"状态
    private func clearPendingQueue() {
        pendingQueue.removeAll()
        for i in chat.messages.indices where chat.messages[i].queued {
            chat.messages[i].queued = false
        }
    }

    /// v2.0.62：打开图片查看器（收集会话内全部图片消息 → 相册翻页）
    /// v2.0.102：索引钳制——解码失败导致 images 比 imgMsgs 短时防越界
    private func openImageViewer(for msg: ChatMessage) {
        let imgMsgs = chat.messages.enumerated().filter { $0.element.imageDataURL != nil }
        let images = imgMsgs.compactMap { dataURLImage($0.element.imageDataURL ?? "") }
        guard !images.isEmpty,
              let rawIdx = imgMsgs.firstIndex(where: { $0.element.id == msg.id }) else { return }
        let idx = min(rawIdx, images.count - 1)   // v2.0.102：坏图跳过导致偏移时钳制
        viewerPayload = ImageViewPayload(images: images, index: idx)
    }

    /// v2.0.128：AI 消息内图片点击 → 打开大图查看器（单张）
    /// data URL 直接解码进查看器；http(s) URL 双通道下载（URLSession → 自签证书降级 CFStream）
    private func openAIImage(_ url: String) {
        if url.hasPrefix("data:image/") {
            if let img = dataURLImage(url) {
                viewerPayload = ImageViewPayload(images: [img], index: 0)
            }
            return
        }
        guard let u = URL(string: url), url.hasPrefix("http") else { return }
        Task {
            let img = await Self.downloadImage(url: url, u: u)
            guard let img else { return }
            await MainActor.run {
                viewerPayload = ImageViewPayload(images: [img], index: 0)
            }
        }
    }

    /// 双通道下载：URLSession（外部图）→ 失败降级 StreamHTTPClient（自签证书服务器）
    @MainActor
    private static func downloadImage(url: String, u: URL) async -> UIImage? {
        if let cached = cachedRemoteImage(url) { return cached }
        if let (data, _) = try? await URLSession.shared.data(from: u),
           let img = UIImage(data: data) {
            setRemoteImageCache(url, img, cost: data.count)
            return img
        }
        if let host = u.host, let scheme = u.scheme {
            let port = UInt16(u.port ?? (scheme == "https" ? 443 : 80))
            let path = u.path + (u.query.map { "?" + $0 } ?? "")
            let client = StreamHTTPClient()
            let result = await Task.detached(priority: .userInitiated) {
                try? client.request(host: host, port: port, isTLS: scheme == "https",
                                    method: "GET", path: path, headers: [:], body: nil, timeout: 15)
            }.value
            if let (data, code) = result, (200..<300).contains(code),
               let img = UIImage(data: data) {
                setRemoteImageCache(url, img, cost: data.count)
                return img
            }
        }
        return nil
    }

    /// v2.0.59：失败消息重试（移除失败标记后按原内容重发）
    private func retryMessage(_ msg: ChatMessage) {
        guard !stream.isStreaming else { return }
        if let idx = chat.messages.firstIndex(where: { $0.id == msg.id }) {
            chat.messages.remove(at: idx)
        }
        sendCore(text: msg.content, imageData: msg.imageDataURL)
    }

    /// v2.0.96：退出语音转文字模式（按钮/空白点击共用）
    /// v2.0.96c：停止录音 → 上传转写 → 文字回填输入框
    /// v3.0.19：语音指令模式退出 → 停止录音 → 转写 → 自动发送（uploadAndTranscribe 内分支）
    private func exitVoiceMode() {
        guard voiceMode else { return }
        voiceRecorder.stop()
        withAnimation(.easeOut(duration: 0.2)) { voiceMode = false }
        uploadAndTranscribe()
    }

    /// v3.0.19：长按智能球 → 语音指令（ASR 后自动发送执行 + TTS 播报结果）
    /// 复用 toggleVoiceMode 的录音/震动/键盘逻辑，仅置 voiceCommandMode 标记区分去向
    private func startVoiceCommand() {
        voiceCommandMode = true
        toggleVoiceMode(keyboardWasUp: false)
    }

    /// v3.0.19：限流/服务错误 → 用户友好提示（429/rate limit/tpm exhausted → 建议换模型路由）
    static func friendlyStreamError(_ error: String) -> String {
        // v3.0.19 review：截断过长原始错误（防消息里塞整页错误日志）
        let brief = error.count > 160 ? String(error.prefix(160)) + "…" : error
        let low = error.lowercased()
        if low.contains("429") || low.contains("rate limit") || low.contains("tpm") ||
           low.contains("exhausted") || low.contains("too many request") {
            return "\(brief)\n\n💡 当前模型的额度限流了（tpm 用尽）。请到「设置 → 模型管理」换一个 provider 的模型（如官方 DeepSeek 或 opencode），稍后再试。"
        }
        if low.contains("timeout") || low.contains("timed out") {
            return "\(brief)\n\n💡 请求超时，可能网络波动或服务繁忙，请重试。"
        }
        return brief
    }

    /// v3.0.19：语音指令回复完成 → TTS 播报摘要（工具类播结果，闲聊播开头；前台/后台都播）
    /// 仅当本次回复是语音指令触发（sendCore 已置 pendingVoiceSpeak）时播报；播报后清空意图
    private func speakVoiceResultIfNeeded(_ text: String) {
        guard pendingVoiceSpeak, !text.isEmpty else { return }
        pendingVoiceSpeak = false
        // 播报摘要：去 markdown + 截断（工具类结果如"客厅灯已打开"很短，闲聊长回复截 ~100 字）
        var clean = text
            .replacingOccurrences(of: #"[*#`>_~\[\]()!|\-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n+", with: "。", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 100 {
            clean = String(clean.prefix(100)) + "。"
        }
        guard !clean.isEmpty else { return }
        // 后台播报：确保音频会话在 playback 模式（VoiceRecorder.stop 已恢复 playback）
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        SpeechManager.shared.toggle(clean, id: "voice-command")
    }

    /// v2.0.96c：上传录音转写（服务器 faster-whisper）
    /// v2.0.100：transcribing 动画（输入框「语音转换中…」+ 按钮转圈）+ 完成/失败震动
    /// v2.0.101：停止按钮（transcribeToken 代次——停止/重录使旧 Task 结果作废，杜绝竞态回填）
    private func uploadAndTranscribe() {
        // v3.0.19 review fix #2：voiceCommandMode 在最顶部消费（guard/录音太短早退也不泄漏）
        let isVoiceCommand = voiceCommandMode
        voiceCommandMode = false
        guard let url = voiceRecorder.stop(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        // v2.0.102：录音太短明确提示（原静默丢弃）
        if data.count <= 100 {
            voiceTooShort = true
            return
        }
        transcribeToken += 1
        let token = transcribeToken
        transcribing = true
        Task {
            do {
                let text = try await auth.asrTranscribe(data)
                transcribing = false
                guard token == transcribeToken else { return }   // 已停止/已重录 → 丢弃结果
                if !text.isEmpty {
                    if isVoiceCommand {
                        // v3.0.19：语音指令闭环——转文字后直接发送执行（不确认，说→干）
                        pendingVoiceSpeakSid = chat.sessionId   // 回复完成后 TTS 播报
                        sendCore(text: text, imageData: nil)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else if inputText.isEmpty {
                        inputText = text   // v2.0.102：用户已在输入时不覆盖（保留正在打的内容）
                        UINotificationFeedbackGenerator().notificationOccurred(.success)   // 转换完成轻反馈
                    }
                } else {
                    // v2.0.107：转写无结果 = 录音太短/没听清——提示「录音太短」（原误用 voiceAuthFailed「不可用」，
                    // 那是麦克风权限/服务故障的提示，与太短场景不匹配）
                    voiceTooShort = true
                }
            } catch {
                transcribing = false
                guard token == transcribeToken else { return }
                voiceAuthFailed = true
            }
        }
    }

    /// v2.0.101：停止转写（代次递增使旧 Task 结果作废 + 立即隐藏转换动画）
    private func stopTranscribe() {
        transcribeToken += 1
        transcribing = false
    }

    /// v2.0.96：语音转文字模式开关（长按发送按钮进入，点按钮/空白退出）
    /// v2.0.100：进入时震动反馈（UIImpactFeedbackGenerator medium）
    /// v2.0.106：长按输入框进入同款路径
    /// v2.0.107：键盘两场景——长按前键盘已开 → 保持；未开 → 收回（触摸聚焦弹的，语音模式不弹键盘）
    /// v2.0.107b：震动改 heavy + prepare（原 medium 无 prepare，首次 impact 常被系统丢弃/偏弱）
    private func toggleVoiceMode(keyboardWasUp: Bool = false) {
        // v3.0.4：云端模式无后端 ASR → 屏蔽语音转文字入口（双重保护，避免误入）
        guard !CloudConfig.shared.isCloudMode else { return }
        if voiceMode {
            exitVoiceMode()
        } else {
            if voiceRecorder.start() {
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.prepare()
                gen.impactOccurred()   // 长按激活震动反馈
                if !keyboardWasUp {
                    inputFocus = false   // 键盘原本未开 → 收回触摸聚焦弹起的键盘（语音模式不弹键盘）
                    // v2.0.108c：FocusState 在触摸聚焦动画中设置可能被系统覆盖（iOS27）——
                    // 延迟 60ms 用 UIKit 强制 resignFirstResponder 兜底，确保键盘收回
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                }
                withAnimation(.easeOut(duration: 0.2)) { voiceMode = true }
            } else {
                // v3.0.19 review fix #2：麦克风失败 → 重置语音指令标志（防残留劫持下次转文字）
                voiceCommandMode = false
                voiceAuthFailed = true   // 麦克风权限被拒
            }
        }
    }

    /// v2.0.96：消息撤回（标记 withdrawn → 显示"已撤回"占位 + 服务器同步）
    private func withdrawMessage(_ msg: ChatMessage) {
        if let idx = chat.messages.firstIndex(where: { $0.id == msg.id }) {
            chat.messages[idx].withdrawn = true
            Task { await chat.saveToServer(auth: auth) }
        }
    }

    /// v2.0.92：分享会话卡片（最近 15 条渲染成图片 → 系统分享/微信）
    private func shareSessionCard() {
        let msgs = Array(chat.messages.suffix(15))
        guard !msgs.isEmpty else { return }
        let rows = msgs.map { msg -> (role: String, text: String) in
            if msg.withdrawn { return (msg.role, "[已撤回]") }
            var t = msg.content.replacingOccurrences(of: "\n", with: " ")
            if t.count > 120 { t = String(t.prefix(120)) + "…" }
            return (msg.role, t)
        }
        let card = SessionCardView(rows: rows)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3   // @3x 高清
        guard let img = renderer.uiImage else { return }
        presentShare([img])
    }

    // MARK: - 消息操作

    /// v2.0.36：单条删除（按索引精确删除，防同内容 hash id 误删）
    /// v2.0.102：同步移除对应排队项（修复排队消息删除后"复活"自动重发）
    private func deleteMessage(_ msg: ChatMessage) {
        if let idx = chat.messages.firstIndex(where: { $0.timestamp == msg.timestamp && $0.role == msg.role && $0.content == msg.content }) {
            withAnimation { chat.messages.remove(at: idx) }
            pendingQueue.removeAll { $0.text == msg.content && $0.imageData == msg.imageDataURL }
            Task { await chat.saveToServer(auth: auth) }
        }
    }

    /// v2.0.36+88：系统分享（微信分享扩展不支持纯文本 → 自动转 原图/URL/文字图片）
    private func shareMessage(_ msg: ChatMessage) {
        // 1) 图片消息：分享原图（微信支持图片；原来分享 "[图片]" 文本会失败）
        if let urlStr = msg.imageDataURL, !urlStr.isEmpty,
           let img = dataURLImage(urlStr) {
            presentShare([img])
            return
        }
        let text = msg.content
        guard !text.isEmpty else { return }
        // 2) 纯链接：分享 URL（微信支持网页链接）
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           !trimmed.contains(" ") {
            presentShare([url])
            return
        }
        // 3) 普通文本：渲染成文字图片再分享（微信唯一接受的文本形态）
        if let img = textShareImage(text) {
            presentShare([img])
        } else {
            presentShare([text])   // 兜底：渲染失败退回原始文本
        }
    }

    /// 分享面板统一弹出（v2.0.88：iPad 必须提供 popover 锚点，否则崩溃）
    private func presentShare(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = av.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        }
        root.present(av, animated: true)
    }

    /// 文本 → 分享图片（固定白底深字，宽度固定高度自适应，微信友好）
    private func textShareImage(_ text: String) -> UIImage? {
        let maxChars = 2000
        var content = textShareClean(text)
        if content.count > maxChars {
            content = String(content.prefix(maxChars)) + "\n\n…（内容过长，已截断）"
        }
        let width: CGFloat = 320
        let hPad: CGFloat = 20
        let vPad: CGFloat = 24
        let font = UIFont.systemFont(ofSize: 16)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 6
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(white: 0.13, alpha: 1),
            .paragraphStyle: para
        ]
        let ns = content as NSString
        let drawSize = CGSize(width: width - hPad * 2, height: .greatestFiniteMagnitude)
        let box = ns.boundingRect(with: drawSize,
                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                  attributes: attrs, context: nil)
        let height = ceil(box.height) + vPad * 2
        guard height < 4000 else { return nil }   // 极端超长防爆内存
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor(white: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ns.draw(with: CGRect(x: hPad, y: vPad, width: drawSize.width, height: box.height + 20),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs, context: nil)
        }
    }

    /// 分享前轻量清理 markdown 符号（转图片后更干净）
    private func textShareClean(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "```", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: "### ", with: "")
        t = t.replacingOccurrences(of: "## ", with: "")
        t = t.replacingOccurrences(of: "# ", with: "")
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "> ", with: "")
        return t
    }

    /// v2.0.36：图片 dataURL → UIImage（大图查看用；与 MessageBubble 同逻辑）

    /// 发送 PDF 文件对话（PDFKit 提取文本拼进消息，AI 直接读内容）
    // MARK: - v2.0.84 文件整份上传（原件存 NAS，文本类/PDF 同时提取内容给 AI）

    /// v2.0.86s：上传结果细分（区分服务器拒绝 / 蜂窝限制 / 连接失败，提示不误导）
    enum UploadResult {
        case success
        case rejected(String)       // 服务器返回错误（带信息）
        case networkFailed(String)  // 网络/连接失败（错误信息含蜂窝限制时提示 WiFi/Web）
    }

    /// 上传整份文件到 NAS（/api/files/upload；WiFi 直连可传大文件，蜂窝 relay 受限自动失败）
    private func uploadFile(_ url: URL, name: String) async -> UploadResult {
        guard let data = try? Data(contentsOf: url) else { return .rejected("文件读取失败") }
        do {
            let j = try await auth.uploadMultipart("/api/files/upload", fileName: name, data: data)
            if (j["ok"] as? Bool) == true { return .success }
            return .rejected(j["message"] as? String ?? j["error"] as? String ?? "上传失败")
        } catch {
            return .networkFailed("\(error)")
        }
    }

    private func sendFile(_ url: URL) {
        // v2.0.102：流式中发文件不再静默丢弃——明确提示
        guard !stream.isStreaming else {
            fileSendBlocked = true
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        let name = url.lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()

        Task {
            // v2.0.102：安全作用域在 Task 内保持到读取完成（原 defer 提前释放导致 iOS 读取失败）
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            // 整份上传 NAS（原件服务器保留，可下载）
            let result = await uploadFile(url, name: name)
            var content: String
            switch result {
            case .success:
                if ["txt", "md", "log", "json", "csv"].contains(ext),
                   let text = try? String(contentsOf: url, encoding: .utf8) {
                    // 文本类：上传原件 + 提取前 12000 字给 AI 阅读
                    content = "[文件: \(name)]（已上传 NAS）\n\(String(text.prefix(12000)))"
                } else if ext == "pdf" {
                    // PDF：上传原件 + PDFKit 提取文本给 AI
                    let raw = extractPDFText(from: url) ?? ""
                    content = raw.isEmpty
                        ? "[PDF: \(name)]（已上传 NAS，扫描件无文字层）"
                        : "[PDF: \(name)]（已上传 NAS）\n\(String(raw.prefix(12000)))"
                } else {
                    // Word/Excel 等：整份上传（本地不提取，文件在 NAS 可下载）
                    content = "[文件: \(name)]（已上传 NAS）"
                }
            case .rejected(let msg):
                // v2.0.86s：服务器拒绝（磁盘满/路径错误等）→ 显示具体原因
                content = "[文件: \(name)]（上传失败：\(msg)）"
            case .networkFailed(let msg):
                // v2.0.86s：蜂窝 relay 上行 ~2KB 限制大文件；WiFi 网络异常则提示重试
                if msg.contains("蜂窝") || msg.contains("文件过大") || NetworkMonitor.shared.isCellular {
                    content = "[文件: \(name)]（上传失败：蜂窝网络限制大文件，请连接 WiFi 重试或使用 Web 版上传）"
                } else {
                    content = "[文件: \(name)]（上传失败：连接异常，请重试）"
                }
            }
            chat.append(.local(role: "user", content: content))
            let history = chat.historyPayload()
            await stream.start(auth: auth, sessionId: chat.sessionId, model: modelName,
                               provider: provider, messages: history) { success, error in
                if !success {
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)", agent: stream.isAgent)
                } else {
                    chat.upsertAssistant(stream.content, agent: stream.isAgent)
                    showSentOK()
                    // v2.0.36：App 退后台时 AI 回复完成发本地通知
                    if UIApplication.shared.applicationState != .active {
                        NotificationHelper.notify(title: "轻聊", body: "AI 回复完成，点击查看",
                                                  sessionId: chat.sessionId)
                    }
                }
                Task { await chat.saveToServer(auth: auth) }
            }
        }
    }

    /// PDFKit 提取文本（文本型 PDF 才有内容；扫描件无文字层返回空）
    private func extractPDFText(from url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        return doc.string
    }

    /// 重新生成：长按 AI 消息 → 删除该条及其后，重发
    private func regenerate(at id: String) {
        guard !stream.isStreaming,
              let idx = chat.messages.firstIndex(where: { $0.id == id }) else { return }
        chat.messages.removeSubrange(idx...)
        let history = chat.historyPayload()
        Task {
            await stream.start(auth: auth, sessionId: chat.sessionId, model: modelName,
                               provider: provider, messages: history) { success, error in
                if !success {
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)", agent: stream.isAgent)
                } else {
                    chat.upsertAssistant(stream.content, agent: stream.isAgent)
                    showSentOK()
                }
                Task { await chat.saveToServer(auth: auth) }
            }
        }
    }

    /// ✅送达提示条（仅成功时显示，2.5s 后消失）
    private func showSentOK() {
        withAnimation(.easeOut(duration: 0.3)) { sentOK = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { sentOK = false }
        }
    }

    /// 内联附件面板按钮（类微信 + 面板样式）
    private func attachButton(_ icon: String, _ name: String, _ color: Color,
                              action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { showAttachmentMenu = false }
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// v2.0.96b：发牌弹出附件按钮（idx 控制延迟，依次从底部弹出 + 回弹）
    /// v2.0.96c：onAppear 驱动（if 包裹下按钮创建即终态，值动画无效 → 子视图内部 appeared 状态）
    private func menuButton(_ icon: String, _ name: String, _ color: Color, idx: Int,
                            action: @escaping () -> Void) -> some View {
        DealAttachmentButton(icon: icon, name: name, color: color, idx: idx,
                             onPick: {
                                 withAnimation(.spring(duration: 0.3, bounce: 0.2)) { showAttachmentMenu = false }
                                 action()
                             })
    }

    /// 图片压缩（PWA 同款：最长边 1280 / JPEG 0.72，超 900KB 降质）
    private func compressImage(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1280
        var w = image.size.width
        var h = image.size.height
        if max(w, h) > maxSide {
            let scale = maxSide / max(w, h)
            w *= scale
            h *= scale
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let resized = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var quality: CGFloat = 0.72
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > 900_000, quality > 0.25 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }
        guard let d = data else { return nil }
        return "data:image/jpeg;base64," + d.base64EncodedString()
    }
}

// MARK: - v2.0.96c 发牌弹出附件按钮（onAppear stagger：依次从底部弹出 + 回弹）

struct DealAttachmentButton: View {
    let icon: String
    let name: String
    let color: Color
    let idx: Int
    let onPick: () -> Void
    @State private var appeared = false

    var body: some View {
        Button(action: onPick) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 34)
        .rotationEffect(.degrees(appeared ? 0 : -10))
        .scaleEffect(appeared ? 1 : 0.5)
        .onAppear {
            // v2.0.98：插入帧 withAnimation 的 .delay 会被父级 transition 动画吞掉（实测发牌不生效）
            //          → 改 DispatchQueue 真延迟逐张弹出
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.07) {
                withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                    appeared = true
                }
            }
        }
    }
}

// MARK: - 消息气泡




