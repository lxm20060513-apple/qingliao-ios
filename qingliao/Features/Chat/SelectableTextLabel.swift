import SwiftUI
import UIKit

// MARK: - v2.0.125 可选取文字视图（UITextView 包装）
// 长按文字 → 弹出自定义编辑菜单（复制/引用/分享/大爆炸/选择文本/重新生成/删除/撤回）
// 点「选择文本」→ 菜单消失，手按位置的词被选中，出现原生拖动手柄，可自由拖动选取范围。
// 纯 SwiftUI Text 无法程序化选中文字，必须用 UITextView（isSelectable）实现。
//
// ⚠️ iOS 26+ 关键坑（v2.0.124 曾在此改坏）：
//  - iOS 26 起弃用 textView(_:editMenuForTextIn:) 委托，长按时不再调用 → 必须实现
//    textView(_:editMenuForTextInRanges:)，否则自定义菜单全丢、只弹系统默认菜单
//  - iOS 26 弃用的是 UITextView.selectedRange（NSRange 版），UITextInput 的
//    selectedTextRange（UITextRange 版）依然有效 —— 选中文字统一用 selectedTextRange

struct SelectableTextLabel: UIViewRepresentable {
    let attributedText: NSAttributedString
    let fallbackColor: UIColor          // 无颜色属性的文本用此色（用户消息白字 / AI 消息 label）
    // v2.0.125：行距可配（AI 回复行距缩小；用户消息保持原行距）
    var lineSpacing: CGFloat = 3
    // v2.0.130：AI 消息行距从设置实时读（UserDefaults 直读，不依赖 SwiftUI 参数传递时机——修复"调了没生效"）
    var lineSpacingFromSettings: Bool = false
    // v3.0.11 fix：AI 消息统一满容器宽（流式宽度恒定，消除"字变小/排版每帧跳变"）
    // —— v3.0.2/a253fe4 引入的"按内容宽收缩"在流式内容增长时会跳变（v3.0.4 曾修复又被同天回退），
    // 用户消息保持内容自适应（短文本窄气泡，微信风格）不受影响。
    var fillWidth: Bool = false
    var onCopy: () -> Void = {}
    var onQuote: () -> Void = {}
    var onShare: () -> Void = {}
    var onBigBang: () -> Void = {}
    // v3.0.8：onSelectText 已随「选择文本」菜单项移除（复制选中覆盖），不再使用
    var onDelete: () -> Void = {}
    var onRegenerate: (() -> Void)? = nil
    var onWithdraw: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true
        tv.delegate = context.coordinator
        tv.dataDetectorTypes = []
        // 尺寸行为与 SwiftUI Text 一致：短文本气泡窄、长文本换行不撑爆
        //（hugging required → 按内容宽；compression low → 超宽时压缩换行）
        tv.setContentHuggingPriority(.required, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        tv.textColor = fallbackColor
        // v3.0.7 fix：兜底字号跟随聊天字号设置（原硬编码 15，设置调大后无属性 run 仍是 15 → 大小不齐）
        let uiFontSize = UserDefaults.standard.double(forKey: "qingliao_font_size")
        tv.font = UIFont.systemFont(ofSize: CGFloat(uiFontSize > 0 ? uiFontSize : 15))
        // 行距：AI 消息从设置实时读（0-6），用户消息用固定值
        let spacing = lineSpacingFromSettings
            ? UserDefaults.standard.double(forKey: "qingliao_ai_line_spacing")
            : lineSpacing
        // v2.0.132：内容指纹——文本/行距/颜色/字号未变化则跳过重建（LazyVStack 滚动
        // 复用 cell 时 SwiftUI 反复调 updateUIView，重设 attributedText + layoutIfNeeded
        // 是长记录滑动卡顿主因；同内容直接 return 保留现有布局）
        // v3.0.7 fix：字号加入指纹——设置改字号后同文本不再被指纹命中跳过（旧字大小不齐根因）
        // v3.0.12 fix：宽度加入指纹——AI 长消息折叠/展开、旋转或气泡宽度变化时，即使文本
        // 指纹未变，UITextView 的 NSTextContainer 宽度也须跟随刷新，否则字体被压进旧的小
        // 容器宽里等比例变小（刷新窗口即恢复的现象根因）。宽度一变强制重排。
        let key = "\(attributedText.string.hashValue)|\(spacing)|\(fallbackColor.cgColor)|\(uiFontSize)|\(Int(tv.bounds.width))"
        if context.coordinator.lastKey == key {
            return
        }
        context.coordinator.lastKey = key
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        let attr = NSMutableAttributedString(attributedString: attributedText)
        attr.addAttribute(.paragraphStyle, value: style,
                          range: NSRange(location: 0, length: attr.length))
        tv.attributedText = attr
        tv.layoutIfNeeded()
        tv.invalidateIntrinsicContentSize()
    }

    // v2.0.130：修复"AI 回复文字显示不完整断句"——
    // SwiftUI 用 intrinsicContentSize 布局时宽度未定，UITextView 按单行宽度算高度 → 多行被裁。
    // 🚨 防 .infinity 提案：宽度为无穷时 UITextView 按单行换行算高度 → 仍会裁切，须钳制到气泡最大宽。
    // v3.0.4 fix（气泡自适应+无抖动）：宽度 = min(单行内容宽, 最大宽)——单行短文本窄气泡，
    // 多行超宽自动钳制为最大宽；宽度随文本单调增长（短→窄 长→宽），流式时平滑不跳变
    // （区别于 v3.0.2 按高度判断单行 → 边界抖动"字时大时小"）。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let maxWidth = UIScreen.main.bounds.width - 60
        // v3.0.5 review fix：优先用容器提案宽（iPad 分栏等窄容器），无提案才用屏幕宽
        let available = (proposal.width.map { $0.isFinite ? $0 : nil } ?? nil) ?? maxWidth
        let upperBound = min(available, maxWidth)
        if fillWidth {
            // v3.0.11 fix：满容器宽——宽度恒定（只随行数长高），流式内容增长时布局不跳变
            let size = uiView.sizeThatFits(CGSize(width: upperBound, height: .greatestFiniteMagnitude))
            return CGSize(width: upperBound, height: size.height)
        }
        // 单行整段内容宽（不换行测量）
        let contentW = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
        // 宽度 = min(内容宽 + 少量余量, 容器可用宽, 屏幕最大宽)，单调增长无跳变
        let target = max(min(contentW + 10, upperBound), 1)
        let size = uiView.sizeThatFits(CGSize(width: target, height: .greatestFiniteMagnitude))
        return CGSize(width: target, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: SelectableTextLabel
        // v2.0.132：上次渲染的内容指纹（文本长度|行距|颜色），未变则跳过重建
        var lastKey = ""
        init(parent: SelectableTextLabel) { self.parent = parent }

        // iOS 26+ 新 API（部署目标 26.0，唯一生效路径；旧 API editMenuForTextIn 已弃用不再调用）
        // 🚨 关键坑（v2.0.124/125 改坏根源）：iOS 26 全面转向 NSRange 体系（selectedRanges:
        // [NSRange]、UITextField 新 API 直接 [NSRange]），ranges 的 [NSValue] 包装的是 **NSRange**，
        // 必须用 rangeValue 取；124/125 用 nonretainedObjectValue as? UITextRange 转换必然失败
        // → 返回 nil → 系统默认菜单（自定义项全丢）。
        // ⚠️ 返回 nil = 显示系统默认菜单（Apple 文档原话），任何情况都要返回自定义菜单
        func textView(_ textView: UITextView,
                      editMenuForTextInRanges ranges: [NSValue],
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let first = ranges.first else { return nil }
            // 兼容两种包装：优先 UITextRange（nonretainedObjectValue），失败回退 NSRange（rangeValue）
            let nsRange: NSRange
            if let tr = first.nonretainedObjectValue as? UITextRange {
                let loc = textView.offset(from: textView.beginningOfDocument, to: tr.start)
                let len = textView.offset(from: tr.start, to: tr.end)
                nsRange = NSRange(location: loc, length: len)
            } else {
                nsRange = first.rangeValue
            }
            return buildMenu(for: nsRange, in: textView)
        }

        /// 自定义编辑菜单：复制选中/复制整段/引用/分享/大爆炸/选择文本/重新生成/撤回/删除
        private func buildMenu(for range: NSRange, in textView: UITextView) -> UIMenu {
            var children: [UIMenuElement] = []

            // v3.0.2 fix：区分「复制选中」和「复制整段」——选中文字后点复制应只复制选区，
            // 之前一律走 onCopy() 复制整段（用户 bug：选中几个字却复制全文）。
            // 有实际选区 → 复制选中文本；无选区（长按空白/未选中）→ 复制整段。
            let hasSelection = range.length != 0 && textView.selectedTextRange != nil
            children.append(UIAction(title: hasSelection ? "复制选中" : "复制",
                                     image: UIImage(systemName: "doc.on.doc")) { _ in
                if hasSelection {
                    // 复制当前选中文本（精确选区）
                    if let selected = textView.selectedTextRange,
                       let text = textView.text(in: selected),
                       !text.isEmpty {
                        UIPasteboard.general.string = text
                    } else {
                        self.parent.onCopy()   // 兜底整段
                    }
                } else {
                    self.parent.onCopy()   // 整段复制
                }
            })
            // v3.0.2：始终提供「复制整段」（AI 长回复整段复制）
            children.append(UIAction(title: "复制整段", image: UIImage(systemName: "doc.on.doc.fill")) { _ in
                self.parent.onCopy()
            })
            children.append(UIAction(title: "引用", image: UIImage(systemName: "quote.opening")) { _ in
                self.parent.onQuote()
            })
            children.append(UIAction(title: "分享", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.parent.onShare()
            })
            children.append(UIAction(title: "大爆炸", image: UIImage(systemName: "burst.fill")) { _ in
                self.parent.onBigBang()
            })

            // v3.0.8：移除「选择文本」——已有「复制选中」（长按选区直接复制），该入口冗余
            // （原 v2.0.127 选中手柄功能：系统原生长按已有文本选择手柄，无需重复入口）

            if let onRegenerate = parent.onRegenerate {
                children.append(UIAction(title: "重新生成", image: UIImage(systemName: "arrow.clockwise")) { _ in
                    onRegenerate()
                })
            }
            if let onWithdraw = parent.onWithdraw {
                children.append(UIAction(title: "撤回", image: UIImage(systemName: "arrow.uturn.backward")) { _ in
                    onWithdraw()
                })
            }
            children.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.parent.onDelete()
            })
            return UIMenu(children: children)
        }
    }
}
