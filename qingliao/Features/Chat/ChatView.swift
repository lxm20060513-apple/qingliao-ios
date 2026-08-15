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

struct ChatView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream
    @Environment(KeyboardObserver.self) private var kb

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
    @State private var voiceAuthFailed = false
    // v2.0.88：AI 回答中发送的消息队列（回答结束后自动逐条发送）
    @State private var pendingQueue: [PendingSend] = []

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

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "聊天",
                       subtitle: headerSubtitle,
                       trailing: AnyView(
                           Button {
                               showMoreMenu = true
                           } label: {
                               Image(systemName: "ellipsis.circle")
                                   .font(.system(size: 17, weight: .semibold))
                                   .foregroundStyle(Color.accentColor)
                           }
                           .buttonStyle(.plain)
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
            // 内联附件面板（类微信 + 面板：点击回形针展开）
            // v2.0.96b：发牌弹出效果（每个按钮依次从底部弹出 + 回弹）
            if showAttachmentMenu {
                HStack(spacing: 26) {
                    menuButton("photo.on.rectangle", "图片", Color.blue, idx: 0) { showPhotoPicker = true }
                    menuButton("doc.fill", "文件", Color.indigo, idx: 1) { showFileImporter = true }
                    // v2.0.43：快捷指令（常用 prompt 模板）
                    menuButton("bolt.fill", "指令", Color.orange, idx: 2) { showQuickPrompts = true }
                    // v2.0.96：Hermes 捷径（官方斜杠命令列表）
                    menuButton("sparkles", "Hermes 捷径", Color.purple, idx: 3) { showHermesShortcut = true }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // v2.0.36：引用回复条（发送后自动清除）
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
                        onVoiceModeToggle: { toggleVoiceMode() },
                        transcribing: transcribing)   // v2.0.100：转换中动画
                         // v2.0.37：键盘弹出时输入框贴键盘顶部（绝对坐标换算，0 空隙）；
            // v2.0.46：隐藏 Dock 栏开关开启时输入框贴底（不留 Dock 避让），否则留 86pt 避让贴底 Dock
            .padding(.bottom, kb.isVisible
                     ? max(0, UIScreen.main.bounds.height - kb.topY)
                     : (hideDock ? 0 : 86))
        }
        .animation(.easeOut(duration: 0.22), value: kb.height)
        // v2.0.96：语音授权/转写失败提示（服务器 ASR：麦克风权限或转写无结果）
        .alert("语音转文字不可用", isPresented: $voiceAuthFailed) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("请检查麦克风权限（设置 → 轻聊 → 麦克风），或稍后重试。")
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
            QuickPromptSheet { prompt in
                inputText = prompt
                showAttachmentMenu = false
            }
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
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // v2.0.40：clearing 期间直接显示欢迎页（列表已卸载，数据稍后清空）
                if (chat.messages.isEmpty || clearing) && !stream.isStreaming {
                    // 首次进入欢迎占位（v2.0.39：.id 强制与消息列表分支区分身份，
                    // 清空会话时列表↔欢迎页切换不再复用视图身份导致崩溃）
                    // v2.0.87h：欢迎页扁平轻量色彩化（多彩渐变气泡 + 渐变标题）
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
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                    .id("welcome")
                } else {
                    // v2.0.40：LazyVStack → VStack（懒加载在批量移除时有复用状态残留，
                    // 普通 VStack 全量渲染，移除只是简单数组变化，彻底绕开崩溃）
                    VStack(spacing: 10) {
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
                            }
                            .id(msg.id)
                            // 气泡出现动效：淡入 + 轻微上移（灵动）
                            // v2.0.38：去掉 .animation(value: messages.count)——
                            // 批量清空（清空会话/新建会话）时全 cell 同时移除的 spring 动画曾导致闪退
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                                    removal: .opacity))
                        }
                        if stream.isStreaming {
                            if stream.content.isEmpty {
                                // 思考中动画（三点跳动，气泡加大版）
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
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
                                MessageBubble(
                                    message: ChatMessage(role: "assistant", content: stream.content, timestamp: nil, agent: stream.isAgent)
                                )
                                .id("streaming")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .id("messages")   // v2.0.39：与欢迎页分支区分身份
                }
            }
            // v2.0.50：.scrollPosition 在隐藏页内容清空时是已知崩溃点（新建会话=TabView
            // 隐藏页清空→scrollPos 更新异常→SIGTRAP）→ 换 GeometryReader + PreferenceKey 检测滚动
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
                    withAnimation(nil) { chat.newSession() }
                    chat.pendingNewSession = false
                    clearing = false
                }
            }
            // v2.0.88：切换/新建会话 → 清空待发队列（避免排队消息发到别的会话）
            .onChange(of: chat.sessionId) {
                clearPendingQueue()
            }
            // 滚动消息区即收起键盘（微信式）
            .scrollDismissesKeyboard(.immediately)
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
        .task {
            // 服务器连接状态检测（真实绿点）
            let r = await auth.testConnection(server: auth.serverURL)
            serverOnline = r.hasPrefix("✅")
        }
        .sheet(isPresented: $showModelSheet) {
            ModelSheet(current: modelName)
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
                    sendCore(text: p.text, imageData: p.imageData)
                }
                pendingSend = nil
            }
            Button("直接发送") {
                if let p = pendingSend {
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
        inputText = ""
        quotedMessage = nil
        pendingImage = nil
        pendingImageData = nil
        // v2.0.59：上下文过长时先提示压缩（60 条以上）
        if chat.messages.count > 60 {
            pendingSend = (text, img)
            showLongContextAlert = true
            return
        }
        sendCore(text: text, imageData: img)
    }

    /// v2.0.59：发送核心（send / 失败重试共用）
    /// v2.0.88：AI 回答中发送不再被拦截——消息上屏 + 入队，当前回答结束后自动逐条发送
    private func sendCore(text: String, imageData: String?) {
        guard !text.isEmpty || imageData != nil else { return }
        if stream.isStreaming {
            // 排队路径：消息立即显示（标记排队中），回答结束后自动发送
            var msg = ChatMessage.local(role: "user", content: text, imageDataURL: imageData)
            msg.queued = true
            withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                chat.append(msg)
            }
            pendingQueue.append(PendingSend(text: text, imageData: imageData))
            Task { await chat.saveToServer(auth: auth) }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // v2.0.65：发送通知 → Dock 聊天图标轻跳
        NotificationCenter.default.post(name: .qingliaoSent, object: nil)
        let msg = ChatMessage.local(role: "user", content: text, imageDataURL: imageData)
        // v2.0.59：单条插入动效（批量移除才崩，插入安全）
        withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
            chat.append(msg)
        }
        startStream(for: msg)
    }

    /// v2.0.88：启动流式回答（消息已在列表；失败标记/回复完成/队列联动统一在这里）
    private func startStream(for msg: ChatMessage) {
        let history = chat.historyPayload()

        Task {
            await stream.start(
                auth: auth,
                sessionId: chat.sessionId,
                model: modelName,
                provider: provider,
                messages: history
            ) { success, error in
                if !success {
                    chat.markFailed(id: msg.id)   // v2.0.59 失败标记 → 重试按钮
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)", agent: stream.isAgent)
                } else {
                    chat.upsertAssistant(stream.content, agent: stream.isAgent)
                    showSentOK()
                    // v2.0.36：App 退后台时 AI 回复完成发本地通知（v2.0.60 携带会话 id）
                    if UIApplication.shared.applicationState != .active {
                        NotificationHelper.notify(title: "轻聊", body: "AI 回复完成，点击查看",
                                                  sessionId: chat.sessionId)
                    }
                }
                // 保存会话到后端（会话记录同步）
                Task { await chat.saveToServer(auth: auth) }
                // v2.0.88：回答完成（成功/失败/停止）→ 自动发送队列中的下一条
                if !pendingQueue.isEmpty {
                    let next = pendingQueue.removeFirst()
                    sendQueued(next)
                }
            }
        }
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
        } else {
            // 排队消息已不在列表（如会话被清空/切换）→ 正常发送兜底
            sendCore(text: item.text, imageData: item.imageData)
        }
    }

    /// v2.0.88：取消排队（停止按钮/切换会话）——清队列 + 消息恢复"已送达"状态
    private func clearPendingQueue() {
        pendingQueue.removeAll()
        for i in chat.messages.indices where chat.messages[i].queued {
            chat.messages[i].queued = false
        }
    }

    /// v2.0.62：打开图片查看器（收集会话内全部图片消息 → 相册翻页）
    private func openImageViewer(for msg: ChatMessage) {
        let imgMsgs = chat.messages.enumerated().filter { $0.element.imageDataURL != nil }
        let images = imgMsgs.compactMap { dataURLImage($0.element.imageDataURL ?? "") }
        guard !images.isEmpty,
              let idx = imgMsgs.firstIndex(where: { $0.element.id == msg.id }) else { return }
        viewerPayload = ImageViewPayload(images: images, index: idx)
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
    private func exitVoiceMode() {
        guard voiceMode else { return }
        voiceRecorder.stop()
        withAnimation(.easeOut(duration: 0.2)) { voiceMode = false }
        uploadAndTranscribe()
    }

    /// v2.0.96c：上传录音转写（服务器 faster-whisper）
    /// v2.0.100：transcribing 动画（输入框「语音转换中…」+ 按钮转圈）+ 完成/失败震动
    private func uploadAndTranscribe() {
        guard let url = voiceRecorder.stop(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url), data.count > 100 else { return }
        transcribing = true
        Task {
            do {
                let text = try await auth.asrTranscribe(data)
                transcribing = false
                if !text.isEmpty {
                    inputText = text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)   // 转换完成轻反馈
                } else {
                    voiceAuthFailed = true   // 没识别出内容 → 提示
                }
            } catch {
                transcribing = false
                voiceAuthFailed = true
            }
        }
    }

    /// v2.0.96：语音转文字模式开关（长按发送按钮进入，点按钮/空白退出）
    /// v2.0.100：进入时震动反馈（UIImpactFeedbackGenerator medium）
    private func toggleVoiceMode() {
        if voiceMode {
            exitVoiceMode()
        } else {
            if voiceRecorder.start() {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()   // 长按激活震动反馈
                withAnimation(.easeOut(duration: 0.2)) { voiceMode = true }
            } else {
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
    private func deleteMessage(_ msg: ChatMessage) {
        if let idx = chat.messages.firstIndex(where: { $0.timestamp == msg.timestamp && $0.role == msg.role && $0.content == msg.content }) {
            withAnimation { chat.messages.remove(at: idx) }
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
        guard !stream.isStreaming else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()

        Task {
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




