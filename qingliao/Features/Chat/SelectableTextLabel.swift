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
    var onCopy: () -> Void = {}
    var onQuote: () -> Void = {}
    var onShare: () -> Void = {}
    var onBigBang: () -> Void = {}
    var onSelectText: () -> Void = {}  // v2.0.125：选择文本入口（选中手按位置词）
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
        tv.attributedText = attributedText
        tv.textColor = fallbackColor
        tv.font = UIFont.systemFont(ofSize: 15)   // 无字体属性文本的默认（有属性则保留）
        // 行距：AI 消息从设置实时读（0-6），用户消息用固定值
        let spacing = lineSpacingFromSettings
            ? UserDefaults.standard.double(forKey: "qingliao_ai_line_spacing")
            : lineSpacing
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
    // sizeThatFits 拿到提案宽度后精确计算换行高度；宽度始终占满容器（防换行错乱断句）。
    // 🚨 防 .infinity 提案：宽度为无穷时 UITextView 按单行换行算高度 → 仍会裁切，须钳制到气泡最大宽。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let maxWidth = UIScreen.main.bounds.width - 60   // 消息块水平 padding 后的可用宽
        let w = proposal.width ?? maxWidth
        let width = w.isFinite ? min(max(w, 1), maxWidth) : maxWidth
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: SelectableTextLabel
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

        /// 自定义编辑菜单：复制/引用/分享/大爆炸/选择文本/重新生成/撤回/删除
        private func buildMenu(for range: NSRange, in textView: UITextView) -> UIMenu {
            var children: [UIMenuElement] = []

            children.append(UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) { _ in
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

            // v2.0.127：核心 —— 选中手按位置的文字 → 系统显示拖动手柄，可自由拖动选取范围
            // iOS 26 新属性 selectedRanges: [NSRange]（长按菜单的 range 即手按位置的选区）
            children.append(UIAction(title: "选择文本", image: UIImage(systemName: "selection.pin.in.out")) { _ in
                textView.selectedRanges = [range]
                self.parent.onSelectText()
            })

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
