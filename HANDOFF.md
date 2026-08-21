# 轻聊 App 项目交接文档

> 最后更新：2026-08-21
> 最新版本：v3.0.30（native-3.0 分支，已发版）

---

## 一、项目概况

**轻聊** 是一个 iOS 原生 AI 聊天 App，Swift 6 + SwiftUI 开发，支持本地 AI 和云端 AI 双模式。

- **仓库**：https://github.com/lxm20060513-svg/qingliao-ios
- **主分支**：`native-3.0`（v3.x 开发线）
- **旧分支**：`native-2.0`（v2.0.140 已冻结，带 tag `v2.0.140`）
- **Tag 规范**：`v3.0.XX`，CI 自动触发构建

### 核心架构

| 层 | 技术 |
|---|---|
| UI | SwiftUI，glassEffect 毛玻璃卡片，Siri 淡雅配色 |
| 网络层 | 注入式 HttpClient 协议，测试可 mock |
| 流式输出 | SSEStreamDecoder（SSE 逐 token 推送） |
| 数据层 | @Observable ViewModel + FileManager JSON 持久化 |
| 语音 | WhisperKit 本地 ASR + AVSpeechSynthesizer TTS |
| 云端工具 | CloudToolLoop + LocalToolRunner（日历/提醒/计时器/天气/剪贴板/计算器/通知） |

### 关键源文件

| 文件 | 职责 |
|---|---|
| `QingliaoApp.swift` | 入口 + GlobalEnvironment + 主题初始化 + 主题切换动画 |
| `ContentView.swift` | 主界面 + 导航逻辑 |
| `ChatViewModel.swift` | 核心聊天逻辑，local/cloud 双模式 + 7 个工具 |
| `ChatComponents.swift` | MessageBubble / ModelPickerSheet / MessageDetailSheet / BubbleTheme / MarkdownTableView |
| `ChatStore.swift` | 聊天数据持久化 + 导出功能（txt/Markdown/PDF） |
| `ChatView.swift` | 聊天页面 + 消息列表 + 导出菜单（三选：纯文本/Markdown/PDF） |
| `MarkdownRenderer.swift` | 正则解析 Markdown，渐进渲染 + 逐字显示 |
| `LiquidGlass.swift` | 主题系统 + AI 推荐卡片 + BubbleTheme + DashboardCardStyle |
| `DashboardView.swift` | 智能看板（NAS/HA/路由器/网络） |
| `Models.swift` | 所有数据模型（含 cpuText/pctText/maxDiskPctText 预格式化） |
| `SettingsView.swift` | 设置页（8 个 @ViewBuilder section + 输入校验） |

---

## 二、版本历史

### v3.0.30（Agent 模型修复，2026-08-21 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| Agent 模型列表加载不出来 | `SettingsView.swift` | AgentModelSheet 端点写错（用了不存在的 `/api/models/providers`，改为 `/api/stream/model-providers?with_models=1`）；hardcoded 过滤把 opencode/deepseek/stepfun/sensenova 全滤掉只剩空列表，已移除 |
| 「跟随主模型」选了不生效 | `ChatView.swift` | `regenerate()` / `sendFile()` 两处流式入口直接读主模型未读 agent 设置；已统一优先级=视觉模型 > agent模型 > 主模型 |
| 版本号 | `project.yml` | 3.0.29 → 3.0.30 |

### v3.0.29（Agent 模型自定义，2026-08-21 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| Agent 模型自定义 | `SettingsView.swift` | 新增 `AgentModelSheet`，独立于主模型，可单独指定 Agent 使用的模型；设置页拉取 `/api/models/providers` 分组展示，含"跟随主模型"清空选项 |
| Agent 模型优先级 | `ChatView.swift` | startStream 优先级 = 视觉模型 > agent模型 > 主模型（agent 开启且配置了独立模型时生效） |
| 会话列表显示 | `SessionsView.swift` | BotCard displayModel 同步显示 agent 模型（配置了独立 agent 模型时） |
| 版本号 | `project.yml` | 3.0.28 → 3.0.29 |

### v3.0.28（视觉模型统一，2026-08-21 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 视觉模型配置统一 | `VisionModelSheet.swift` | 原「App 本地视觉模型」与「微信通道视觉模型」两份独立配置合并为**一份共享配置**；模型行点选打勾即同时设置 App + 微信通道（写入 CloudConfig 本地 + 后端 /api/channel/vision-model → wechat-profile auxiliary.vision，自动重启 gateway） |
| 版本号 | `project.yml` | 3.0.27 → 3.0.28 |
| 后端 | 无改动 | 复用既有 GET/POST/DELETE /api/channel/vision-model（channel_api.py 9152） |

### v3.0.27（已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 视觉模型自动切换 | `ChatViewModel.swift` | 主模型支持视觉时自动用主模型，不支持时用配置的视觉模型 |
| 视觉模型配置 UI | `SettingsView.swift` | 本地AI设置→模型管理底部新增视觉模型配置，可选择独立视觉模型 |
| 视觉模型配置移入模型管理弹窗 | `SettingsView.swift` | 视觉模型配置从独立入口移入模型管理统一弹窗 |
| 微信通道视觉模型 | `VisionModelSheet.swift` | 微信通道支持独立视觉模型配置（v3.0.22 起） |

### v3.0.26

| 改动 | 文件 | 说明 |
|---|---|---|
| 视觉模型自动切换 | `ChatViewModel.swift` | 主模型支持视觉时自动用主模型，不支持时用配置的视觉模型 |
| 视觉模型配置 UI | `SettingsView.swift` | 本地AI设置→模型管理底部新增视觉模型配置，可选择独立视觉模型 |

### v3.0.25

| 改动 | 文件 | 说明 |
|---|---|---|
| 视觉模型配置移入模型管理弹窗 | `SettingsView.swift` | 本地AI视觉模型配置从独立入口移入模型管理统一弹窗 |
| 微信通道视觉模型 | `ChatViewModel.swift` + `SettingsView.swift` | 微信通道支持独立视觉模型配置 |

### v3.0.24

改动：本地AI视觉模型配置功能上线。

### v3.0.23

改动：外观弹窗（AppearanceSheet）统一为半屏卡片样式，添加 `.presentationDetents([.medium, .large])`。

涉及文件：`SettingsView.swift`（设置页入口）、`CloudSettingsView.swift`（云端模式入口）。

### v3.0.22

| 改动 | 文件 | 说明 |
|---|---|---|
| 主题切换过渡动画 | `QingliaoApp.swift` | 0.3s easeInOut，深浅切换不再硬切 |
| ServerSheet 输入校验 | `SettingsView.swift` | URL 格式/端口 1-65535/非法字符，红色错误提示 |
| hwCpuText/hwSsdText 预格式化 | `Models.swift` | 跟 cpuText/pctText 同模式 |
| 导出菜单升级为三选 | `ChatView.swift` | 纯文本/Markdown/PDF 三种格式 |
| exportMarkdown() | `ChatStore.swift` | Markdown 结构化导出 |
| ChatMarkdownDocument + ChatPDFDocument | `ChatComponents.swift` | A4 排版，UIKit 绘制 |
| 项目版本号更新 | `project.yml` | 4 处 MARKETING_VERSION 从 3.0.20 更新 |

### v3.0.21

中间版本，已合并到 v3.0.22。

### v3.0.20

| 改动 | 文件 | 说明 |
|---|---|---|
| 看板卡片统一 | `LiquidGlass.swift` | 新增 `DashboardCardStyle` 修饰符 |
| 看板空态折叠 | `DashboardView.swift` | 智慧场景/自动化无数据时收为单行 |
| 气泡颜色集中 | `LiquidGlass.swift` + `ChatComponents.swift` | 新增 `BubbleTheme` 消除 6 处硬编码色值 |
| 模型层预格式化 | `Models.swift` | 新增 `cpuText`/`pctText`/`maxDiskPctText` |
| SettingsView 拆分 | `SettingsView.swift` | body 从 500 行拆为 8 个 @ViewBuilder 计算属性 |

### v3.0.19 及更早

- v3.0.0：云端模式上线（本地 AI / 云端 AI 双模式）
- v3.0.7：Bot Mode + @Observable 切页卡顿根治
- v3.0.18：AI 消息挤小框根治 + 云端工具调用（7 工具）
- v3.0.19：语音指令闭环 + 微信窗通道模型方案 B

---

## 三、CI/CD 发包流程

### 触发条件

`native-3.0` 分支上推送 `v*` tag 会自动触发 `.github/workflows/build-ios.yml`。

### 完整流程

```bash
# 1. 进入本地仓库
cd /tmp/qingliao-ios

# 2. 确保代码已提交并 push
git push origin native-3.0

# 3. 获取最新 tag，递增
git fetch --tags
git tag -l 'v3.0.*' | sort -V | tail -1  # 例如 v3.0.26
git tag v3.0.27
git push origin v3.0.27

# 4. 等待 CI 完成（约 3-5 分钟）
gh run list --limit 5 --repo lxm20060513-svg/qingliao

# 5. 下载 IPA
gh run download <RUN_ID> --name qingliao-ipa \
  --repo lxm20060513-svg/qingliao \
  -D /tmp/qingliao-artifact

# 6. 上传到 NAS（paramiko base64 管道）
```

### 关键点

- **gh 使用 lxm20060513 的 PAT**（不是 svg 的），因为 release artifact 下载需要仓库 owner 权限
- **NAS SFTP chroot**：根目录是 `/volume1/`，所以路径用 `docker/hermes/...`（相对路径），不要用 `/volume1/docker/...`（绝对路径会 ENOENT）
- **NAS SSH 端口**：22（9122 已不通，2026-08-20 起）
- **NAS 凭据文件**：`/opt/data/.nas_cred`，格式单行密码
- **GitHub PAT 文件**：`/opt/data/.gh_cred`，格式 `token:xxxxx`（base64）
- **watch_ipa_ci.py**：自动监听 CI + 下载 IPA，需先创建目标目录

---

## 四、NAS 部署结构

| 路径 | 内容 |
|---|---|
| `/docker/hermes/微信文件/轻聊web/backend/` | 后端代码（API 服务器） |
| `/docker/hermes/微信文件/轻聊web/frontend/` | Web 前端 |
| `/docker/hermes/微信文件/轻聊app/` | iOS IPA 文件存放 |
| `/docker/hermes/微信文件/轻聊app/qingliao.app/` | SideStore 打包用的 .app 目录 |

---

## 五、踩坑经验

### 1. GitHub PAT 过期
- **现象**：`git push` 返回 401
- **修复**：更新 remote URL 里的 PAT 或设置 `GH_TOKEN` 环境变量

### 2. gh run download 权限问题
- **原因**：用了 svg 的 PAT，但 release artifact 下载需要仓库 owner 的 PAT
- **修复**：`export GH_TOKEN=lxm20060513 的 PAT`

### 3. Xcode Archive 编译失败
- **常见原因**：Swift 语法错误（多/少 `}`）
- **排查**：GitHub API 查 workflow run jobs

### 4. NAS SFTP 路径
- **现象**：`/volume1/docker/hermes/...` 返回 ENOENT
- **原因**：SFTP chroot 根目录是 `/volume1/`
- **修复**：用相对路径 `docker/hermes/...`

### 5. NAS SSH 端口变更
- **端口 22**：当前可用（9122 已不通）

### 6. watch_ipa_ci.py 下载失败（目录不存在）
- **现象**：CI 成功但 FileNotFoundError
- **修复**：先 mkdir -p 创建目标目录，或下载到本地再 paramiko 上传

### 7. project.yml 版本号
- `project.yml` 里有 4 处版本号需要同步更新
- **发版 checklist**：改代码 → 改 project.yml → commit → push → 打 tag

---

## 六、下一步计划（待实现）

| 优先级 | 功能 | 难度 | 说明 |
|---|---|---|---|
| 高 | 图片持久化上传 | 低 | 复用 Web 端 /api/files/upload |
| 高 | 长文目录/折叠 | 低 | 识别 Markdown 标题生成目录 |
| 中 | 用量统计 | 低 | 解析 usage 字段，做图表 |
| 中 | 桌面小组件 | 中 | WidgetKit |
| 中 | 会话文件夹/标签 | 中 | 新增 Category 模型 |
| 中 | LaTeX 公式 | 中 | 检测 `$...$`，内嵌 WKWebView + KaTeX |
| 中 | @ 引用历史消息 | 中 | 输入框检测 @ + 弹列表 |
| 低 | 流式语音对话 | 高 | ASR 流式 + 按句 TTS |
| 低 | 富文本输入 | 高 | UITextView 替换 TextEditor |

---

*文档完。每次发版后请更新此文档的版本号和改动记录。*
