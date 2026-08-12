# 轻聊 2.0（Qingliao）— 原生 iOS AI 助手

家庭 NAS 上的 AI 助手客户端，SwiftUI 原生重写（非 HTML 套壳）。连接自部署后端，提供 AI 对话、智能家居看板、文件管理、定时任务等能力，支持 iOS 17+（含 iOS 26/27）。

## ✨ 功能特性

**💬 AI 对话**
- 流式输出（高频轮询接近逐字）、Markdown 渲染（自研渲染器：标题/加粗/代码块/列表/引用）
- 多模型切换（模型管理面板）、引用回复、单条删除、重新生成（BigBang 大爆炸分词）
- 图片发送/查看（压缩上传、相册式翻页浏览、保存到相册）、拍照输入、PDF/文档解析对话
- 语音输入（按住说话转文字）、语音消息（录音 → 语音条播放）
- 发送失败重试、超长上下文提示与一键压缩、杀后台流式恢复
- 会话：搜索定位（命中消息高亮）、置顶/收藏、重命名、导出 txt、清空

**📊 看板**
- 智能家居总览（Home Assistant：灯/空调/门锁/安防，HomeKit 圆角风格，真实数据状态点）
- NAS 状态（磁盘/内存/服务）、路由器状态（在线设备数/Clash 快捷开关）

**⚙️ 设置与工具**
- 密码管理（Face ID 解锁）、文件管理（上传/下载/重命名/删除/新建文件夹）
- 定时任务管理（增删改查/立即运行）、系统日志、模型管理（多 provider）
- 主题：深色/浅色/跟随系统（新装默认跟随系统）、聊天字体大小调节、隐藏 Dock 栏

**🛡️ 稳定性**
- 崩溃自动上报（signal-safe 捕获 → 服务器日志，含信号号）
- 本地通知（AI 回复完成提醒，点击直达会话）
- 网络层多通道容灾（CFStream 直连 / Safari Relay / WebKit 兜底）

## 🏗 技术栈

- SwiftUI + Observation（全 @MainActor 隔离）
- XcodeGen 生成工程（`project.yml`）
- 自定义网络层：NWConnection / URLSession / ASWebAuthenticationSession 多通道
- 自研组件：MarkdownRenderer、BigBangParser、液态玻璃主题（LiquidGlass）

## 🔧 构建（本地需 macOS + Xcode 26）

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project 轻聊.xcodeproj -scheme Qingliao -configuration Release \
  -destination generic/platform=iOS -archivePath build/App.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
# Payload zip 打包 unsigned IPA → SideStore 侧载安装
```

## 🤖 CI

`.github/workflows/build-ios.yml`：macos-latest 全自动构建，产出 unsigned IPA 上传 GitHub Release（SideStore 免签名安装）。

## 📁 结构

```
project.yml              XcodeGen 配置
qingliao/
├── QingliaoApp.swift    入口（登录门禁 → DockTabView）
├── Core/                AuthStore / ChatStore / StreamClient / CrashReporter 等
├── Features/            Chat / Sessions / Dashboard / Settings / BigBang
│   └── Chat/            ChatView + ChatComponents（拆分的 UI 组件）
├── Theme/               液态玻璃主题
└── Assets.xcassets      图标 + 强调色
```

## 🔀 分支

- `native-2.0`：2.0 原生 SwiftUI（当前唯一分支，默认分支）
