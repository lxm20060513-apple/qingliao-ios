# 轻聊 App 项目交接文档

> 最后更新：2026-08-22
> 最新版本：v3.0.35（native-3.0 分支，已发版）

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

### v3.0.37（图片持久化 + 灵动岛位置修正，2026-08-23 开发中未发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 图片持久化 | `ChatView.swift` + `ChatComponents.swift` + `ChatStore.swift` + 后端 `files_api.py` | 发送图片前 base64 自动上传 NAS → URL 替代 base64 入库（跨设备可见/重启不丢/省内存）；ChatComponents 用户图支持 http URL；后端 upload 返回相对 url + download 上传目录匿名可读；实测上传→匿名下载全链路通过 |
| 灵动岛发光位置 | `LiquidGlass.swift` | 光晕下移 10pt（`-6 → +4`），贴合真实灵动岛位置 |

### v3.0.36（看板大版本：磁盘系统盘+模型用量+Hermes重启+分段流式语音+灵动岛发光，2026-08-22 已发版）

**v3.0.36 功能改动**

| 改动 | 文件 | 说明 |
|---|---|---|
| 磁盘系统盘分区 | `DashboardView.swift` + `Models.swift` | NASDisk 加 `kind` 字段（system/data），DisksSheet 分组显示；后端 `/:/host_root:ro` 挂载 + 宿主视角 8 分区（/boot/rootfs/ugreen/mnt_factory/overlay + /volume1/2/3） |
| 模型使用量栏 | `DashboardView.swift` + `Models.swift` + 后端 `usage_api.py` | ProviderUsage 模型 + UsageCard 卡片：DeepSeek ¥36.55（/user/balance）、StepFun ¥15（/v1/accounts）、OpenCode percent 配额（/zen/go/v1/usage：rolling/weekly/monthly + resetsAt）、小米/商汤 unsupported 降级；新接口 `/api/nas/providers-usage` |
| Hermes 网关卡重启 | `DashboardView.swift` + 后端 `stream_api.py` | ServiceControlSheet 泛化支持 qingliao/hermes 双服务（hermes 隐藏停止卡）；后端 `/api/nas/service/restart` 支持 service=hermes（docker exec hermes-hermes-1 重启，stop 拒绝 400） |
| 分段流式语音 | `ChatView.swift` + `VoiceRecorder.swift` | 录音中每 5s 切块上传转写，文字增量追加"边说边出字"毛玻璃条；VoiceRecorder `stopCurrentSegment`/`resumeSegment`；转文字/语音指令双模式；修复 read-before-resume 竞态 |
| 灵动岛发光 | `LiquidGlass.swift` + `QingliaoApp.swift` + `CloudSettingsView.swift` | IslandGlowOverlay（顶部胶囊呼吸光晕，复用 Siri 发光 4 参数）+ 外观弹窗独立开关（本地+云端共用弹窗自动统一） |
| version | `project.yml` | 3.0.35 → 3.0.36（build 334） |

**v3.0.36 发版后 3 个线上 bug 修复（2026-08-23 全部验证通过）**

| Bug | 根因 | 修复 |
|---|---|---|
| Hermes 网关显示已停止 | qingliao 容器极简镜像**无 pgrep/ps** → FileNotFoundError → hermes 恒 null | stream_api.py 改 curl 健康检查 + `docker exec hermes-hermes-1 ps` 取内存 |
| 智能家居卡片刷不出 | compose 的 QL_HA_TOKEN 是 **30 分钟过期 JWT**（误存 access token），HA 端 8-11 后令牌重置，全链路 401 | 用户新提供长期令牌 → 更新 compose/重建容器 + ha_config.json + Hermes 侧 .ha_token（4 处） |
| opencode 卡片 error | 容器内 getent 优先解析 **IPv6**（2606:4700:78::）而 v6 路由不通 → 连接超时 | usage_api.py query_opencode 强制 IPv4（socket.getaddrinfo AF_INET）+ 短超时 8s；实测 1.1-1.5s 稳定 |

**部署注意**：compose env 变更必须 `docker compose up -d --force-recreate`（`docker restart` 不重新注入 env）；容器内无 pgrep/ps/不能直接 docker.sock，验证用宿主 python urllib+sudo PTY。

### v3.0.35（模型列表加载优化，2026-08-22 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 微信通道/Agent 弹窗不再无限转圈 | `SettingsView.swift` + `AgentModelSheet` | 打开先显示缓存（UserDefaults 新 ModelProvidersCache）；`/api/channel/model` 与 model-providers 改 async let 并发（原串行）；失败态+重试按钮（原 try? 静默吞错→永远"正在加载模型列表…"）；新增手动刷新按钮 |
| 通用 provider 接缓存 | `ModelSheet`/`VisionModelSheet` | 打开先显示缓存、后台刷新替换；缓存非空才写，防后端临时故障刷空缓存 |
| 版本号 | `project.yml` | 3.0.34 → 3.0.35（build 333） |

### v3.0.34（模型列表同步并发优化，2026-08-22 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 模型列表同步并发优化 | `SettingsView.swift` + `VisionModelSheet.swift` | ModelSheet/VisionModelSheet 的 4 provider sync-models 改 async let 并行（最坏 40s → ~10s，失效 key 快速失败）；loadAllProviders 去掉空 models 逐个补拉的 N+1（聚合接口已并发+5min 缓存，补拉纯拖慢） |
| 版本号 | `project.yml` | 3.0.33 → 3.0.34（build 332） |

### v3.0.33（Agent 模型覆盖提示，2026-08-22 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 模型管理弹窗加 Agent 覆盖提示 | `SettingsView.swift` | ModelSheet 顶部条件显示提示：Agent 开关开且配置了 agent 模型时聊天实际走 agent 模型（视觉模型 > Agent 模型 > 主模型），此时在模型管理选主模型不生效；提示条说明原因并引导去 Agent 设置改为跟随主模型 |
| 版本号 | `project.yml` | 3.0.32 → 3.0.33（build 331） |

### v3.0.32（视觉模型判定补全，2026-08-22 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 视觉模型判定补全 | `CloudConfig.swift` | modelSupportsVision 补全：minimax M 系列全系（M1/M2/M2.x/M3）+ glm-5.x 全系判为支持视觉，避免主模型选 M3/GLM-5 时发图被视觉模型顶替 |
| 版本号 | `project.yml` | 3.0.31 → 3.0.32（build 330） |
| 清理旧脚本 | `scripts/` | 删除 watch_ci_v3030.sh / watch_v3028.py |

### v3.0.31（流式任务恢复，2026-08-22 已发版）

| 改动 | 文件 | 说明 |
|---|---|---|
| 流式任务恢复 | `StreamClient.swift` | poll 404 时 tryRecover 一次（换新 taskId / 磁盘内容续接 / done 即收尾），避免 qingliao 重启后长任务白等 |
| recover 请求封装 | `AuthStore.swift` | 新增 streamRecover，poll 404 时抛 APIError.server(code) |
| 版本号 | `project.yml` | 3.0.30 → 3.0.31（build 329） |

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