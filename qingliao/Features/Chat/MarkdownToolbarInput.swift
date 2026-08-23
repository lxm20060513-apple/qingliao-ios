import SwiftUI
import UIKit
import Foundation

// MARK: - v3.0.37 富文本输入（路线 B）
// UITextView 桥接纯文本 Markdown 输入：支持选区读取 → 工具栏对选中文字应用
// Markdown 标记（** / * / ` / [](url) / - / >）。保持外部契约不变（@Binding String + FocusState），
// 发送仍走 Markdown 源码（后端/AI 原生支持），非所见即所得。

/// 工具栏格式操作
enum MarkdownTool {
    case bold, italic, code, link, list, quote
}

/// 对 text 的 [range] 选区应用格式；无选区时在光标处插入模板
/// 返回 (新文本, 新光标位置)
func applyMarkdownTool(_ tool: MarkdownTool, text: String, range: NSRange) -> (String, Int) {
    let ns = text as NSString
    let loc = min(range.location, ns.length)
    let len = min(max(range.length, 0), ns.length - loc)
    let sel = ns.substring(with: NSRange(location: loc, length: len))
    let empty = sel.isEmpty

    switch tool {
    case .bold:
        let open = empty ? "" : "**"
        let body = empty ? "加粗文字" : sel
        let close = empty ? "" : "**"
        let newText = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: open + body + close)
        return (newText, loc + open.count + body.count + close.count)
    case .italic:
        let open = empty ? "" : "*"
        let body = empty ? "斜体文字" : sel
        let close = empty ? "" : "*"
        let newText = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: open + body + close)
        return (newText, loc + open.count + body.count + close.count)
    case .code:
        let body = empty ? "代码" : sel
        let newText = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: "`" + body + "`")
        return (newText, loc + 1 + body.count + 1)
    case .link:
        let body = empty ? "链接文字" : sel
        let newText = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: "[" + body + "](https://)")
        return (newText, loc + body.count + 3)   // 光标落在 url 段开头（[body]( 之后）
    case .list:
        // 每行加 "- " 前缀（作用选区起始行）
        let prefix = "- "
        let newText = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: prefix + sel)
        return (newText, loc + prefix.count + sel.count)
    case .quote:
        let prefix = "> "
        let newText = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: prefix + sel)
        return (newText, loc + prefix.count + sel.count)
    }
}

/// UITextView 桥接输入框：纯文本 Markdown 输入，同步选区 + 内容高度
struct MarkdownToolbarInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var isFocused: Bool = false
    var onFocusChange: (Bool) -> Void = { _ in }
    var onChangeHeight: (CGFloat) -> Void = { _ in }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownToolbarInput
        init(_ parent: MarkdownToolbarInput) { self.parent = parent }

        func textViewDidBeginEditing(_ tv: UITextView) {
            // 用户点击弹键盘 → 写回 FocusState（否则 updateUIView 会误 resign 收回键盘）
            parent.onFocusChange(true)
        }
        func textViewDidEndEditing(_ tv: UITextView) {
            parent.onFocusChange(false)
        }
        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            parent.selectedRange = tv.selectedRange
            parent.onChangeHeight(tv.contentSize.height)
        }
        func textViewDidChangeSelection(_ tv: UITextView) {
            parent.selectedRange = tv.selectedRange
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 2, bottom: 12, right: 2)
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = false
        tv.scrollsToTop = false
        tv.text = text
        context.coordinator.parent.onChangeHeight(tv.contentSize.height)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // 外部文本更新（语音转写/工具栏格式化）→ 同步
        if tv.text != text {
            tv.text = text
            // 工具栏应用格式后恢复目标光标（限幅防越界）
            let target = min(selectedRange.location, (text as NSString).length)
            tv.selectedRange = NSRange(location: target, length: 0)
        }
        // 焦点状态同步（FocusState 不适用于 UIKit 桥接，手动 firstResponder）
        if isFocused && !tv.isFirstResponder {
            tv.becomeFirstResponder()
        } else if !isFocused && tv.isFirstResponder {
            tv.resignFirstResponder()
        }
    }
}

/// 输入框上方格式工具栏：B / I / ` / 链接 / 列表 / 引用
struct MarkdownToolbar: View {
    var onTool: (MarkdownTool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button {
                onTool(.bold)
            } label: {
                Text("B").font(.system(size: 14, weight: .heavy))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)

            Button {
                onTool(.italic)
            } label: {
                Text("I").font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)

            Button {
                onTool(.code)
            } label: {
                Text("`").font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)

            Button {
                onTool(.link)
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)

            Button {
                onTool(.list)
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)

            Button {
                onTool(.quote)
            } label: {
                Image(systemName: "quote.opening")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}