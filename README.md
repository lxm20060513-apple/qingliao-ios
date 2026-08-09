# 轻聊 2.0 — 原生 SwiftUI（iOS 27 液态玻璃）

PWA（1.x）不动，2.0 为 IPA 原生重写：SwiftUI + XcodeGen，非 HTML 套壳。

## 结构
```
project.yml              XcodeGen 配置（target/settings/Info.plist）
qingliao/
├── QingliaoApp.swift    入口（登录态 → DockTabView）
├── Core/                AuthStore（登录/token/API 请求）、Models
├── Features/            DockTabView + Chat / Sessions / Dashboard / Settings
├── Theme/               液态玻璃组件（glassCard 等）
└── Assets.xcassets      AppIcon（PWA 图标 1024px）+ AccentColor
```

## 构建（本地需 macOS + Xcode 26）
```bash
brew install xcodegen
xcodegen generate
xcodebuild -project 轻聊.xcodeproj -scheme Qingliao -configuration Release \
  -destination generic/platform=iOS -archivePath build/App.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
# 手动 Payload zip 打 unsigned IPA → SideStore 安装
```

CI：`.github/workflows/build-ios.yml`（macos-latest 全自动，产出 unsigned IPA 发 GitHub Release）。

## 分支
- `main`：1.x Capacitor 壳（PWA 打包）
- `native-2.0`：2.0 原生 SwiftUI
