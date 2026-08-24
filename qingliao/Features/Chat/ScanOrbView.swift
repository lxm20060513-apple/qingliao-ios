import SwiftUI

// MARK: - 扫码球（v3.0.46）
//
// 聊天页智能球上方新增的「扫码球」：青色粒子光晕球（与智能球同款视觉语言，
// 但青绿配色 + 内嵌扫描框 + 扫描线循环扫动 = 一眼识别是扫一扫）。
// 点击 → 青色高光 + 粒子散开，4 个子功能（识物/识人/翻译/扫码）环形浮现。
//
// 只手势用 TapGesture（扫码球无长按——长按留给智能球语音）。散开菜单点外部空白可收起。

enum ScanMode: String, CaseIterable, Identifiable {
    case identify = "识物"   // 拍照/相册 → 「这是什么」
    case person   = "识人"   // 拍照/相册 → 描述这个人
    case translate = "翻译"  // 拍照/相册 → 翻译图中文字
    case qrcode   = "扫码"   // 拍照/相册 → 解析二维码/图示
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .identify: return "camera.viewfinder"
        case .person:   return "person.crop.circle.badge.questionmark"
        case .translate: return "character.bubble"
        case .qrcode:   return "qrcode.viewfinder"
        }
    }
    /// 送视觉模型的系统提示（决定模型怎么答）
    var instruction: String {
        switch self {
        case .identify:  return "识别图片中的主体是什么：给出名称、类别、用途与显著特征，用中文简洁回答。"
        case .person:    return "描述图片中人物的外貌、表情、服装、气质等可观察特征（无法识别具体身份）。用中文简洁回答。"
        case .translate: return "把图片中的文字内容完整提取并翻译成中文。若图片无文字，请说明。用中文简洁回答。"
        case .qrcode:    return "解析图片中的二维码/条码/图示：尝试读出内容（链接/文本/数据），并说明它指向什么。用中文简洁回答。"
        }
    }
}

struct ScanOrbView: View {
    /// 选中某子功能（相机拍到图后再走图片发送链路，由外层处理）
    var onPick: (ScanMode) -> Void = { _ in }

    @State private var expanded = false

    /// 4 子功能相对球体的径向布局（2 上 2 侧，避开下方智能球）
    private let layout: [(dx: CGFloat, dy: CGFloat)] = [
        (-132, -34),   // 左上 识物
        (0, -104),     // 正上 识人
        (132, -34),    // 右上 翻译
        (0, 60),       // 正下 扫码
    ]

    var body: some View {
        let schedule: AnimationTimelineSchedule = .animation(minimumInterval: 1.0 / 30.0)
        TimelineView(schedule) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathe = 0.5 + 0.3 * (sin(t * 2.6) + 1) / 2   // 青绿呼吸
            let scanPhase = (sin(t * 2.2) + 1) / 2              // 扫描线上下

            ZStack(alignment: .center) {
                // ---- 扫码球本体（青色粒子光晕球） ----
                Circle()
                    .fill(AngularGradient(
                        colors: [.green.opacity(0.6 * breathe), .mint.opacity(0.5 * breathe),
                                 .cyan.opacity(0.5 * breathe), .teal.opacity(0.42 * breathe),
                                 .green.opacity(0.6 * breathe)],
                        center: .center))
                    .blur(radius: 6)
                    .frame(width: expanded ? 96 : 84, height: expanded ? 96 : 84)
                Circle()
                    .fill(AngularGradient(
                        colors: [.green.opacity(0.32), .blue.opacity(0.24),
                                 .cyan.opacity(0.28), .teal.opacity(0.2),
                                 .green.opacity(0.32)],
                        center: .center))
                    .frame(width: expanded ? 66 : 62, height: expanded ? 66 : 62)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1.2)
                    )
                    .shadow(color: (expanded ? Color.green : Color.cyan).opacity(0.45 * breathe), radius: 14)
                    // 内嵌粒子（轨道旋转，呼应智能球）
                    .overlay {
                        OrbCanvasView(mode: .orbits, size: expanded ? 54 : 50,
                                      opts: OrbOpts(orbitN: 8, ghostN: 22, ghostR: 2.1, ghostA: 0.7,
                                                    particles: 3, partR: 2.6, partRDepth: 2.0,
                                                    rsPow: 0.6, rMin: 0.8),
                                      dotColors: [.mint, .green, .white, .cyan])
                            .allowsHitTesting(false)
                    }
                    // 扫描框四角
                    .overlay {
                        ScanCornerFrame(size: expanded ? 46 : 42, color: .white.opacity(0.85))
                    }
                    // 扫描线（上下来回）
                    .overlay {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: expanded ? 32 : 28, height: 1.6)
                            .offset(y: CGFloat((scanPhase * 2 - 1)) * (expanded ? 18 : 16))
                            .shadow(color: .white.opacity(0.6), radius: 3)
                            .opacity(0.9)
                    }

                // ---- 展开：4 子功能环形浮现 ----
                ForEach(Array(ScanMode.allCases.enumerated()), id: \.element) { i, mode in
                    Button {
                        onPick(mode)
                        withAnimation(.spring(duration: 0.25, bounce: 0.2)) { expanded = false }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(.mint)
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .opacity(expanded ? 1 : 0)
                    .scaleEffect(expanded ? 1 : 0.3)
                    // ⚠️ review fix：收起态必须关命中——.opacity(0) 不关命中测试，
                    // 若不加 allowsHitTesting，隐形子按钮叠在球心会劫持点击直开相机，永远进不了展开态
                    .allowsHitTesting(expanded)
                    .offset(x: expanded ? layout[i].dx : 0,
                            y: expanded ? layout[i].dy : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.72).delay(Double(i) * 0.05),
                               value: expanded)
                }
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) { expanded.toggle() }
            }
            .onChange(of: expanded) { _, on in
                // 收起 1.2s 后自动复位（避免残留半开）。
                // ⚠️ review fix：guard 防毛刺——若用户在超时前已手动收起（expanded 已 false），
                // 回调用旧值重复 withAnimation(false) 无害但多余，此处直接跳过。
                if on {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        guard expanded else { return }
                        withAnimation(.spring(duration: 0.25)) { expanded = false }
                    }
                }
            }
        }
        .frame(width: 96, height: 96)
    }
}

// MARK: - 扫描框四角

struct ScanCornerFrame: View {
    let size: CGFloat
    let color: Color
    var body: some View {
        ScanCornersShape()
            .stroke(color, lineWidth: 1.6)
            .frame(width: size, height: size)
    }
}

/// 描出四角的 L 形（roundrect 风格，非全框）——用固定 Path 绘制，避免存储闭包引发 Sendable 问题
struct ScanCornersShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let s: CGFloat = 9  // 每个角的边长
        var p = Path()
        // 左上
        p.move(to: CGPoint(x: 0, y: s)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: s, y: 0))
        // 右上
        p.move(to: CGPoint(x: w - s, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: s))
        // 左下
        p.move(to: CGPoint(x: 0, y: h - s)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: s, y: h))
        // 右下
        p.move(to: CGPoint(x: w - s, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - s))
        return p
    }
}