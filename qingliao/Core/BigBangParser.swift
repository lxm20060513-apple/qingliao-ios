import Foundation

// MARK: - BigBang 分词器（复刻锤子"大爆炸"语义分词）
// 中文：CFStringTokenizer（ICU 词典分词，按词切分）
// 英文/数字/URL：ICU 按词切分
// 标点：独立成块（便于选择）；空白：跳过

struct BigBangWord: Identifiable {
    let id: Int
    let text: String
}

enum BigBangParser {
    /// 将文本按语义拆成词块（限制 5000 字，防超长消息卡 UI）
    static func tokenize(_ text: String) -> [BigBangWord] {
        let ns = text as NSString
        let maxLen = min(ns.length, 5000)
        var words: [BigBangWord] = []
        var cursor = 0

        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, text as CFString,
            CFRange(location: 0, length: ns.length),
            kCFStringTokenizerUnitWord,
            Locale(identifier: "zh_CN") as CFLocale
        )

        func appendGap(from: Int, to: Int) {
            guard to > from else { return }
            let gap = ns.substring(with: NSRange(location: from, length: to - from))
            var i = 0
            for scalar in gap.unicodeScalars {
                let ch = String(UnicodeScalar(scalar)!)
                if !scalar.properties.isWhitespace {
                    words.append(BigBangWord(id: words.count, text: ch))
                }
                i += 1
            }
        }

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let loc = r.location
            let len = r.length
            if loc >= maxLen { break }
            // 词前的空隙（标点/空白）
            appendGap(from: cursor, to: loc)
            let word = ns.substring(with: NSRange(location: loc, length: len))
            words.append(BigBangWord(id: words.count, text: word))
            cursor = loc + len
        }
        // 尾部空隙
        appendGap(from: cursor, to: maxLen)

        return words.isEmpty ? [BigBangWord(id: 0, text: text)] : words
    }
}
