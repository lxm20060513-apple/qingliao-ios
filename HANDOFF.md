# 轻聊 App 项目交接文档

> 最后更新：2026-08-30
> 最新版本：v3.0.83（feature/handoff-301 分支，Hermes 主动推送收件箱 inbox）

---

## 一、项目概况

**轻聊** 是一个 iOS 原生 AI 聊天 App，Swift 6 + SwiftUI 开发，支持本地 AI 和云端 AI 双模式。

- **仓库**：https://github.com/lxm20060513-svg/qingliao-ios
- **主分支**：`native-3.0`（v3.x 开发线）
- **开发分支**：`feature/handoff-301`（当前活跃）
- **旧分支**：`native-2.0`（v2.0.140 已冻结，带 tag `v2.0.140`）
- **Tag 规范**：`v3.0.XX`，CI 自动触发构建

### 核心架构

| 层 | 技术 |
|---|---|
| UI | SwiftUI，glassEffect 毛玻璃卡片，Siri 淡雅配色 |
| 网络层 | 注入式 HttpClient 协议，测试可 mock |
| 流式输出 | SSEStreamDecoder（SSE 逐 token 推送） |
| 数据层 | @Observable ViewModel + FileManager JSON 持久化 |
| 语音 | AVAudioRecorder 本地录音 + 后端 ASR 转写（输入栏长按触发） |
| 云端工具 | CloudToolLoop + LocalToolRunner（日历/提醒/计时器/天气/剪贴板/计算器/通知） |

### 关键源文件

| 文件 | 职责 |
|---|---|
| `QingliaoApp.swift` | 入口 + GlobalEnvironment + 主题初始化 + 主题切换动画 + scenePhase 后台恢复 |
| `ContentView.swift` | 主界面 + 导航逻辑 |
| `ChatViewModel.swift` | 核心聊天逻辑，local/cloud 双模式 + 7 个工具 |
| `ChatComponents.swift` | MessageBubble / ChatInputBar / SiriBallView / BubbleTheme / MarkdownTableView |
| `ChatStore.swift` | 聊天数据持久化 + 导出功能（txt/Markdown/PDF） |
| `ChatView.swift` | 聊天页面 + 消息列表 + 语音转文字 + 导出菜单 + 钉一钉回调 |
| `VoiceRecorder.swift` | AVAudioRecorder 录音 + 分段管理 |
| `StreamClient.swift` | SSE 流式轮询 + restartPolling 后台恢复 |
| `PinStore.swift` | 钉一钉数据层（CRUD + NAS JSON 持久化 + UserDefaults 兜底） |
| `PinCard.swift` | 钉一钉卡片组件（长按复制/删除） |
| `DockTabView.swift` | Tab 切换 + 淡入缩放动画 |
| `MarkdownRenderer.swift` | 正则解析 Markdown，渐进渲染 + 逐字显示 |
| `LiquidGlass.swift` | 主题系统 + AI 推荐卡片 + BubbleTheme + DashboardCardStyle |
| `DashboardView.swift` | 智能看板（NAS/HA/路由器/钉一钉） |
| `Models.swift` | 所有数据模型（含 cpuText/pctText/maxDiskPctText 预格式化） |
| `SettingsView.swift` | 设置页（8 个 @ViewBuilder section + 输入校验 + 钉一钉存储路径） |

---

## 二、版本历史

### v3.0.83（2026-08-30 已发版）

Hermes 主动推送收件箱（inbox）：让 Hermes 能主动推消息给轻聊App（此前 App 只有"请求-响应"模型，服务端无法主动塞消息）。

| 改动 | 文件 | 说明 |
|---|---|---|
| 后端收件箱 API | `inbox_api.py`（NAS 新增） | GET /api/inbox（App 轮询拉取）、POST /api/inbox/{id}/done（标记已读）、POST /api/inbox/push（Hermes 主动推，鉴权 X-Inbox-Token）；存储 inbox_queue.json，复用 push_api 的 RLock 队列模式 |
| 后端路由挂载 | `unified_router.py`（NAS） | 路由表加 `/api/inbox`（已验证容器日志 `[router] /api/inbox -> inbox_api.Handler: ok`） |
| **AI回复完成→推App收件箱** | `stream_api.py`（NAS） | 新增 `_maybe_push_app(st)`：AI 回复 done 且内容≥1字就调 inbox_api.push(摘要)（**不受"用户是否在看/pushEnabled"门控，每条都推**，用户选方案A）。5 个 done 路径 + 2 个异常兜底都挂载（error/cancelled 不推） |
| App 收件箱轮询 | `InboxStore.swift`（新增） | 每 15s 轮询 /api/inbox，拉到消息 → 注入当前会话（assistant+isPush）→ 弹本地通知 → 标记已读 → 保存会话；方案B（进当前聊天会话，用户确认） |
| 推送标记字段 | `Models.swift` | ChatMessage 加 `isPush: Bool` |
| 推送标签 UI | `ChatMessageBubble.swift` | isPush 消息气泡显示「🔔 推送」蓝色小标签（区别于渐变"Agent 回复"） |
| App 注入与轮询 | `QingliaoApp.swift` | @State inbox + .task 里 attach(auth,chat:)+startPolling() + scenePhase 前台恢复 refreshOnActive() |
| 鉴权加固 | `docker-compose.yml`（NAS） | 注入 192-bit 强 `QL_INBOX_TOKEN`（旧默认 ql-inbox-default 已失效 401） |
| Hermes 推送入口 | `profiles/wechat-profile/scripts/ql_push_app.sh` | Hermes/cron 主动推：`ql_push_app.sh "消息"` 或 stdin |

> ✅ 后端已全部上线验证：inbox_api + 路由 + stream_api 的 `_maybe_push_app` + QL_INBOX_TOKEN 强 token + ql_push_app.sh（md5 一致 / docker restart / 端口回读 / 容器日志 / 端到端 `[push] App收件箱推送 True: 已推送`）。App 端已过 check_swift.sh（v3.0.83 已发版，用户装 v3.0.83 IPA 真机）。Hermes→App 主动推送 + AI回复→App收件箱 双双打通。

### v3.0.79（2026-08-30 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 语音转文字 WiFi 分流修复 | `AuthStore.swift` | asrTranscribe 加 isCellular 分流：蜂窝走 CFStream /r/asr（已通）；WiFi 走 URLSession /api/asr——修复「蜂窝能转写、WiFi 仍报太短」（根因：asrTranscribe 漏网络分流） |
| 点按空白处停止录音 | `ChatView.swift` | 录音中（voiceMode&&isRecording）点消息区空白处 → exitVoiceMode（停止+转写），补上 exitVoiceMode 注释原本的「按钮/空白点击共用」 |
| 版本号 | `project.yml` | 3.0.79 / build 376 |
### v3.0.78（2026-08-29 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 录音链路诊断版 | `VoiceRecorder.swift`+`ChatView.swift` | record()返回值/文件大小/data计数/App版本显示于"录音太短"弹窗——用户反馈讲很久仍太短，先诊断录音拿不到数据的具体环节（record未开始/文件读不到/数据小），据以根治 |
| 版本号 | `project.yml` | 3.0.78 / build 375 |
### v3.0.77（2026-08-29 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 语音转文字根治 | `ChatView.swift` | 回退 v3.0.36 分段流式，改回整段录音一次转写——分段每 2s stop/resume（局部/独立文件名）导致段音频读不到、恒判"录音太短"，讲多久都失败 |
| 钉一钉存储弹窗对齐 | `SettingsView.swift` | 由系统 .alert 改为 App 统一底部 .sheet（对齐 PasswordSheet/ModelSheet 风格） |
| 版本号 | `project.yml` | 3.0.77 / build 374 |
### v3.0.76（2026-08-29 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 语音转文字修复 | `VoiceRecorder.swift` | 回退 v3.0.74 破坏录音的 setActive(false,.notifyOthersOnDeactivation)（录音采不到字节）+ 分段录音改独立文件名（杜绝 stop/resume 同一文件的数据竞争/读到空段） |
| 语音转文字不跳球 | `ChatComponents.swift` | voiceMode 期间保持输入框形态（v3.0.68 收球逻辑会在语音转文字期间收成智能球） |
| 版本号 | `project.yml` | 3.0.76 / build 373 |
### v3.0.75（2026-08-29 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 自定义 provider 模型组 | `SettingsView.swift` | App 模型管理页新增「自定义模型」区块 + 添加表单，用户自主增删模型组（Base URL / API Key / 模型名），免更新 App |
| 后端自定义 provider 接口 | `stream_api.py` | 存储 + 聚合合并 + GET/POST /api/stream/custom-providers；本地 AI 聊天 `_agent_endpoint`/`_worker` 均支持自定义 provider |
| 版本号 | `project.yml` | 3.0.75 / build 372 |
### v3.0.74（2026-08-29 已发版）

钉一钉功能完整实现 + 后台流式恢复 + tab 切换动画 + 录音修复。

| 改动 | 文件 | 说明 |
|---|---|---|
| 钉一钉数据层 | `PinStore.swift` | CRUD + NAS JSON 持久化（pin_write/pin_read API）+ UserDefaults 兜底 |
| 钉一钉卡片 | `PinCard.swift` | 长卡片组件（对齐看板风格），长按菜单：复制内容 / 删除 |
| 钉一钉看板集成 | `DashboardView.swift` | 路由器下方显示钉一钉区段（始终显示，空态有引导文案）；.task 加载 NAS 数据 |
| 钉一钉聊天集成 | `ChatComponents.swift` | MessageBlockView + MessageBubble 的 onPin 参数（传当前段落文字） |
| 钉一钉聊天调用 | `ChatView.swift` | 长按菜单「钉一钉」→ 钉当前段落到看板 |
| 钉一钉设置 | `SettingsView.swift` | 数据与自动化 section 新增「钉一钉存储」路径编辑 |
| 后端 API | `files_api.py`（NAS） | POST /api/files/pin_write + GET /api/files/pin_read（base64 JSON） |
| 后台流式恢复 | `StreamClient.swift` | restartPolling()：后台回来停旧 Task + 起新轮询 |
| 后台流式恢复 | `QingliaoApp.swift` | scenePhase .active 时检查 isStreaming && !isDone → 调 restartPolling |
| 录音修复 | `VoiceRecorder.swift` | 录音前先 setActive(false) 释放旧音频会话（解决多次录音后 setCategory 失败） |
| tab 切换动画 | `DockTabView.swift` | TabTransitionModifier：scaleEffect 0.97→1 + 0.2s easeInOut（保留原生玻璃 tab bar） |
| AuthStore 注入 | `PinStore.swift` + `QingliaoApp.swift` | weak var auth + attach(auth:) 注入式（替代 AuthStore.shared） |
| 版本号 | `project.yml` | 3.0.73 → 3.0.74（build 371） |

### v3.0.73（2026-08-29 已发版）

智能球语音功能全部移除（-335 行），仅保留核心交互。

| 改动 | 文件 | 说明 |
|---|---|---|
| SiriBallView 精简 | `ChatComponents.swift` | 移除 isRecording/voiceMode/transcribing/isSpeaking/onLongPress/onRelease + LongPressGesture/DragGesture；保留点击展开输入框 + 思考动画 |
| ChatInputBar 参数清理 | `ChatComponents.swift` | 移除 onBallLongPress/onRelease/voiceChatActive/onExitVoiceChat/isSpeaking + onChange(of: transcribing) 自动展开 |
| ChatView 语音对讲清理 | `ChatView.swift` | 移除 voiceCommandMode/voiceChatActive/voiceTurns/voiceStream/isAiSpeaking/pendingVoiceSpeak 状态 + startVoiceCommand/handleVoiceChatLongPress/exitVoiceChat/startVoiceReply/speakVoiceChat/stopVoiceStream 等函数 |
| 灰色遮罩清除 | `ChatView.swift` | 移除 Color.black.opacity(0.15) overlay + messageList .background(Color.clear) |
| 保留：输入栏语音转文字 | `ChatComponents.swift` + `ChatView.swift` | 发送键长按 / 输入框长按 → toggleVoiceMode → 录音 → 松手停止 → ASR 转写上屏 |
| 保留：键盘收起自动回球 | `ChatComponents.swift` | onChange(of: kbEnv.isVisible) 键盘收起 + 输入框空 → 自动收回成球 |
| 版本号 | `project.yml` | 3.0.72 → 3.0.73（build 370） |

### v3.0.72（2026-08-28 已发版，被 v3.0.73 取代）

| 改动 | 文件 | 说明 |
|---|---|---|
| 透明 overlay 松手修复 | `ChatView.swift` | overlay 改 allowsHitTesting(false)；恢复球的 DragGesture 检测松手。根因：透明拦截层(.contentShape+.onTapGesture)覆盖全屏，SwiftUI 把手指抬起事件路由到 overlay 的 onTapGesture |

### v3.0.71（2026-08-28 已发版，被 v3.0.72 取代）

| 改动 | 文件 | 说明 |
|---|---|---|
| 语音录音松手继续 | `ChatComponents.swift` | 移除 SiriBallView DragGesture.onEnded 松手停止录音逻辑 |
| voiceChatActive 透明层 | `ChatView.swift` | 放开 voiceChatActive 时隐藏点击退出层的限制 |

### v3.0.70（2026-08-28 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 语音对讲松手修复 | `ChatComponents.swift` | ChatView 调用 ChatInputBar 时漏传 isRecording，导致 SiriBallView 的 DragGesture.onEnded 松手检测与声波粒子分支全因 isRecording 恒 false 静默失效。补传 isRecording: voiceRecorder.isRecording |
| 后端 nginx /api/tts | nginx conf | 三个轻聊 server 块补 /api/tts → 9132 location |

### v3.0.69（2026-08-28 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 语音对讲浮层 | `ChatComponents.swift` + `ChatView.swift` | 声波涟漪粒子 + TTS 模型选择（小米mimo/智谱glm-tts）+ 键盘回球 |

### v3.0.68（2026-08-28 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 神经 TTS | `ChatComponents.swift` + `ChatView.swift` | 语音对讲多轮 + 粒子拟人表情 |

### v3.0.67（2026-08-27 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 输入框与键盘留 10pt | `ChatView.swift` | `.padding(.bottom, kb.isVisible ? 0 : 10)` 改常量 10——键盘也要留隙 |
| 版本号 | `project.yml` | 3.0.66 → 3.0.67（build 364） |

### v3.0.66（2026-08-27 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 输入框与 dock 留 10pt | `ChatView.swift` | 键盘收起时留 10pt 呼吸间距 |
| 智能球与 dock 间距 | `ChatComponents.swift` | 球态自 padding 4→0，间隙由外层统一留 |
| 版本号 | `project.yml` | 3.0.65 → 3.0.66（build 363） |

### v3.0.65（2026-08-27 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 输入框贴键盘 | `ChatView.swift` | 移除手动键盘高度 padding，改原生键盘避让 |
| 移除 Dock 设置项 | `SettingsView.swift` + `CloudSettingsView.swift` | 移除「隐藏 Dock 栏」开关 + 「Dock 透明度」滑条 + DockVisibility 死类 |
| 版本号 | `project.yml` | 3.0.64 → 3.0.65（build 362，修复 build 号漂移） |

### v3.0.64（2026-08-27 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| Dock 改原生 TabView | `DockTabView.swift` | 弃自定义 DockBar，改用 iOS 26 系统 TabView 原生液态玻璃 tab bar。用户拍板定版。 |

> **Dock 演进复盘**：v3.0.61 恢复真液态玻璃 → v3.0.62 每 tab 各自 glassEffect（否决）→ v3.0.63 整条玻璃+手动按压（嫌弃非原生）→ v3.0.64 改用系统原生 tab bar。**核心结论：要原生液态玻璃别手搓，直接上 iOS 26 系统组件。**

### v3.0.59-63（2026-08-27 已发版）

详见 v3.0.64 演进复盘。主要改动：流式气泡文本截断修复 / 智谱 GLM 模型 / 灵动岛发光微调 / 免费模型开关 / 云端厂商删除。

### v3.0.51（2026-08-26 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 多气泡段落流式 | `ChatComponents.swift` + `ChatView.swift` | AI 长回复按空行拆成多个独立气泡 |
| 图片持久化增强 | `ChatStore.swift` + `ChatView.swift` | retryPendingImageUploads 指数退避重传 |
| 长会话分页 | `ChatView.swift` | 极长会话只渲染尾部 300 条 + 顶部「加载更早」 |
| 会话标签 | `SessionTagStore.swift` + `SessionsView.swift` | 预置 工作/学习/生活 + 自定义，彩色小胶囊 |

### v3.0.50（2026-08-25 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 扫码球整体移除 | `ScanOrbView.swift`(整删) + 多文件 | 用户拍板「全部拿掉」；保留 SiriBallView 智能球 |
| ChatMessage.id 稳定化 | `Models.swift` | djb2 稳定哈希替代 content.hashValue |
| StreamClient 竞态修复 | `StreamClient.swift` | generation 递增防旧流污染新流 |
| 超长消息折叠 | `ChatComponents.swift` | >600 字 AI 消息默认折叠 |

### v3.0.49 及更早

详见历史版本记录。

---

## 三、CI/CD 发包流程

### 触发条件

`feature/handoff-301` 分支上推送 `v*` tag 会自动触发 `.github/workflows/build-ios.yml`。

### 完整流程

```bash
# 1. 进入本地仓库
cd /opt/data/qingliao_ios

# 2. check_swift 语法检查
bash check_swift.sh

# 3. 改版本号（project.yml 4 处同步）
sed -i 's/X.Y.Z/A.B.C/g; s/\"OLD_BUILD\"/\"NEW_BUILD\"/g' project.yml

# 4. commit + push
git add -A && git commit -m "fix: ... (vA.B.C)"
git tag vA.B.C
git -c http.version=HTTP/1.1 -c http.lowSpeedLimit=0 -c http.lowSpeedTime=999 push origin feature/handoff-301 vA.B.C

# 5. 等 CI 完成（~15-20 分钟）
curl -s "https://api.github.com/repos/lxm20060513-svg/qingliao-ios/actions/runs?per_page=2"

# 6. 下载 IPA + 转存 NAS
# SFTP put 到 docker/hermes/_upload.ipa，然后 sudo cp 到目标目录
```

### 关键点

- **project.yml 版本号 4 处**：MARKETING_VERSION / CURRENT_PROJECT_VERSION / CFBundleShortVersionString / CFBundleVersion
- **NAS SFTP chroot**：根目录是 `/volume1/`，SFTP 用相对路径 `docker/hermes/...`
- **NAS 上传**：SFTP put 到 `docker/hermes/_upload.ipa` → sudo cp 到目标 → chmod 644
- **NAS 凭据**：`/opt/data/.nas_cred`（单行纯密码，含 @ 勿截断）
- **GitHub 凭据**：`/opt/data/.gh_cred`（明文 40 字符 token）
- **git push 重试**：`for i in $(seq 1 8); do git -c http.version=HTTP/1.1 ... && break; sleep 10; done`
- **盯 CI cron**：构建成功后删 cron，勿空转复读
- **paramiko venv**：`/opt/data/paramiko_old/bin/python3`

---

## 四、NAS 部署结构

| 路径 | 内容 |
|---|---|
| `/docker/hermes/微信文件/轻聊web/backend/` | 后端代码（API 服务器，容器 qingliao） |
| `/docker/hermes/微信文件/轻聊web/frontend/` | Web 前端 |
| `/docker/hermes/微信文件/轻聊web/data/` | 钉一钉数据（pins.json，容器可写） |
| `/docker/hermes/微信文件/轻聊app/` | iOS IPA 文件存放 |
| `/docker/hermes/微信文件/轻聊app/qingliao.app/` | SideStore 打包用的 .app 目录 |

---

## 五、踩坑经验

### 1. project.yml 版本号
- 4 处必须同步（MARKETING_VERSION / CURRENT_PROJECT_VERSION / CFBundleShortVersionString / CFBundleVersion）
- `info.properties` 的 CFBundleVersion 会覆盖 settings 的 CURRENT_PROJECT_VERSION
- **发版前 grep 两处都对齐**，并解包产物核对 Info.plist

### 2. NAS SFTP 路径
- SFTP chroot 到 `/volume1/`，用相对路径 `docker/hermes/...`
- 绝对路径 `/volume1/docker/...` 会 ENOENT
- 目标目录属主 root → 需 sudo cp

### 3. NAS 上传流程
- SFTP put 到可写路径（`docker/hermes/_upload.ipa`）→ sudo cp 到目标 → chmod 644
- exec_command cat + stdin 大文件会 Socket closed → 用 SFTP
- sudo -S 必须立即 stdin.write 密码

### 4. Git push 卡死
- `git -c http.version=HTTP/1.1 -c http.lowSpeedLimit=0 -c http.lowSpeedTime=999 push`
- 重试循环最多 8 次，间隔 10s

### 5. CI 失败重发
- 删 tag 重建 + 重推：`git push origin :refs/tags/vX` + 本地 `git tag -d` + `git tag vX` + push

### 6. 智能球语音功能（v3.0.73 已全部移除）
- v3.0.70-72 三次尝试修复语音松手上屏 bug 均失败
- 根因链：DragGesture 移除 → 透明 overlay 拦截松手 → overlay 改 allowsHitTesting(false) → 仍有问题
- 最终方案：球的语音功能全部移除，语音转文字只保留在输入栏（send 按钮/输入框长按）

### 7. 容器文件系统只读
- NAS 容器对 `/volume1/docker/hermes/微信文件/轻聊app/` 是只读的
- 钉一钉数据存储在 `/volume1/docker/hermes/微信文件/轻聊web/data/`（容器可写）
- 后端 API（files_api.py）通过 pin_write/pin_read 端点读写

### 8. 音频会话未释放
- 多次录音后 `AVAudioSession.setCategory(.record)` 可能失败（上次录音未正确释放）
- 修复：录音前先 `try? session.setActive(false, options: .notifyOthersOnDeactivation)`

---

## 六、下一步计划（待实现）

| 优先级 | 功能 | 难度 | 说明 |
|---|---|---|---|
| 中 | 桌面小组件 | 中 | WidgetKit 主屏幕小组件 |
| 中 | 会话文件夹 | 中 | 新增 Category 模型（文件夹） |
| 中 | LaTeX 公式 | 中 | 检测 `$...$`，内嵌 WKWebView + KaTeX |
| 中 | @ 引用历史消息 | 中 | 输入框检测 @ + 弹列表 |
| 低 | 用量图表 | 中 | 已有 providers-usage 数值卡，可加图表 |

**已实现（从待办剔除）**：图片持久化上传（v3.0.37）、长文目录（v3.0.27）、长文折叠（v3.0.50）、会话标签（v3.0.51）、语音对讲（v3.0.68-69，v3.0.73 移除）、钉一钉（v3.0.74）、后台流式恢复（v3.0.74）。

---

*文档完。每次发版后请更新此文档的版本号和改动记录。*
