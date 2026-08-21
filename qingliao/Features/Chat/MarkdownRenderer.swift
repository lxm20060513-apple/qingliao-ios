import Foundation
import UIKit
import SwiftUI

/// 轻量 Markdown → AttributedString 渲染器（v2.0.34 修复"AI 回复纯文本无排版"）
/// 覆盖 AI 回复常见语法：标题 / 加粗 / 斜体 / 行内代码 / 列表 / 引用 / 链接 / 分隔线。
/// 手动构建 runs，不依赖 AttributedString(markdown:) 的系统解析行为（iOS 上不可控）。
enum MarkdownRenderer {
    static func render(_ text: String, baseSize: CGFloat = 14) -> AttributedString {
        let lines = text.components(separatedBy: "\n")
        var out = AttributedString()
        for (i, line) in lines.enumerated() {
            if i > 0 { out += AttributedString("\n") }
            out += renderLine(line, baseSize: baseSize)
        }
        return out
    }

    // MARK: - 行级语法

    private static func renderLine(_ line: String, baseSize: CGFloat) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // 标题：### / ## / #
        for (mark, size) in [("###", baseSize + 3), ("##", baseSize + 5), ("#", baseSize + 7)] {
            if trimmed.hasPrefix(mark + " ") {
                return renderInline(String(trimmed.dropFirst(mark.count + 1)),
                                    .systemFont(ofSize: size, weight: .bold), .label)
            }
        }
        // 引用：>
        if trimmed.hasPrefix(">") {
            return renderInline(String(trimmed.dropFirst(1)),
                                .italicSystemFont(ofSize: baseSize), .secondaryLabel)
        }
        // 无序列表：- / *
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let body = String(trimmed.dropFirst(2))
            return styled("•  ", .systemFont(ofSize: baseSize, weight: .bold), .secondaryLabel)
                 + renderInline(body, .systemFont(ofSize: baseSize), .label)
        }
        // 有序列表：1. / 1、
        if let m = trimmed.range(of: #"^\d+[\.、]\s"#, options: .regularExpression) {
            let num = String(trimmed[..<m.upperBound])
            let body = String(trimmed[m.upperBound...])
            return styled(num, .systemFont(ofSize: baseSize, weight: .semibold), .secondaryLabel)
                 + renderInline(body, .systemFont(ofSize: baseSize), .label)
        }
        // 分隔线
        if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") {
            return styled("────────", .systemFont(ofSize: baseSize), .tertiaryLabel)
        }
        return renderInline(line, .systemFont(ofSize: baseSize), .label)
    }

    // MARK: - 行内语法：**加粗** `代码` *斜体* [链接](url)

    private static func renderInline(_ text: String, _ font: UIFont, _ color: UIColor) -> AttributedString {
        let ns = text as NSString
        guard let re = try? NSRegularExpression(
            pattern: #"\*\*.+?\*\*|`[^`]+?`|\*[^*]+?\*|\[[^\]]+\]\([^)]+\)"#) else {
            return styled(text, font, color)
        }
        var out = AttributedString()
        var pos = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range
            if r.location > pos {
                out += styled(ns.substring(with: NSRange(location: pos, length: r.location - pos)), font, color)
            }
            let token = ns.substring(with: r)
            if token.hasPrefix("**"), token.hasSuffix("**") {
                out += styled(String(token.dropFirst(2).dropLast(2)),
                              .systemFont(ofSize: font.pointSize, weight: .bold), color)
            } else if token.hasPrefix("`"), token.hasSuffix("`") {
                out += styled(String(token.dropFirst().dropLast()),
                              .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular), color)
            } else if token.hasPrefix("*"), token.hasSuffix("*") {
                out += styled(String(token.dropFirst().dropLast()),
                              .italicSystemFont(ofSize: font.pointSize), color)
            } else if token.hasPrefix("[") {
                // [text](url) → 蓝色文本
                let body = String(token.dropFirst().dropLast())
                if let close = body.range(of: "](") {
                    out += styled(String(body[..<close.lowerBound]), font, .systemBlue)
                }
            }
            pos = r.location + r.length
        }
        if pos < ns.length {
            out += styled(ns.substring(from: pos), font, color)
        }
        return out
    }

    private static func styled(_ s: String, _ font: UIFont, _ color: UIColor) -> AttributedString {
        // NSAttributedString 桥接最稳（基础 API 全版本可用）：UIKit 字体/颜色属性
        // 转换后 Text(AttributedString) 直接按属性渲染
        let ns = NSAttributedString(string: s, attributes: [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: color
        ])
        return AttributedString(ns)
    }

    // MARK: - v3.0.27 大纲导航：提取 Markdown 标题

    struct TOCItem: Identifiable {
        let id = UUID()
        let level: Int       // 1 = #, 2 = ##, 3 = ###
        let title: String
        let lineIndex: Int   // 在原文中的行号（0-based）
    }

    /// 从 Markdown 文本中提取标题列表（# / ## / ###）
    static func extractHeaders(_ text: String) -> [TOCItem] {
        var items: [TOCItem] = []
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for (mark, level) in [("### ", 3), ("## ", 2), ("# ", 1)] {
                if trimmed.hasPrefix(mark) {
                    let title = String(trimmed.dropFirst(mark.count))
                    if !title.isEmpty {
                        items.append(TOCItem(level: level, title: title, lineIndex: i))
                    }
                    break
                }
            }
        }
        return items
    }
}
