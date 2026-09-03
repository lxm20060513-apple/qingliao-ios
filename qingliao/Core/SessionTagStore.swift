import Foundation
import SwiftUI

/// v3.0.51 B7：会话标签/分组（轻量版）——本地 UserDefaults 存储 会话id → 标签数组。
/// 与置顶/收藏同类「本地概念」，不改后端 merge API。预置常用标签 + 自定义标签。
@Observable
@MainActor
final class SessionTagStore {
    static let shared = SessionTagStore()
    private let key = "qingliao_session_tags"        // [sessionId: [String]]
    private let allKey = "qingliao_tag_defs"         // [String] 全部可用标签（含自定义）

    private(set) var tagsBySession: [String: [String]] = [:]
    private(set) var allTags: [String] = []

    private init() {
        load()
    }

    private func load() {
        let ud = UserDefaults.standard
        tagsBySession = (ud.dictionary(forKey: key) as? [String: [String]]) ?? [:]
        let defaults: [String] = ["工作", "学习", "生活"]
        allTags = ud.stringArray(forKey: allKey) ?? defaults
        // 合并缺失的预置标签
        for t in defaults where !allTags.contains(t) { allTags.append(t) }
    }

    /// 会话的标签数组
    func tags(for sessionID: String) -> [String] {
        tagsBySession[sessionID] ?? []
    }

    /// 增/删某会话的一个标签
    func toggle(_ tag: String, on sessionID: String) {
        var current = tags(for: sessionID)
        if let i = current.firstIndex(of: tag) {
            current.remove(at: i)
        } else {
            current.append(tag)
        }
        // 上限 3 个标签
        if current.count > 3 { current = Array(current.prefix(3)) }
        tagsBySession[sessionID] = current.isEmpty ? nil : current
        persist()
    }

    /// 新增自定义标签（同时入库可用标签集合）
    func addCustomTag(_ tag: String) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !allTags.contains(t), t.count <= 6 else { return }
        allTags.append(t)
        UserDefaults.standard.set(allTags, forKey: allKey)
    }

    private func persist() {
        UserDefaults.standard.set(tagsBySession, forKey: key)
    }
}

// MARK: - 标签彩色扩展（按哈希稳定分配，深浅色都醒目）
extension SessionTagStore {
    /// 标签颜色（按名称哈希稳定分配）
    static func tagColor(_ tag: String) -> Color {
        let palette: [Color] = [
            .blue, .teal, .green, .orange, .pink, .purple, .indigo, .mint
        ]
        var h = 5381
        for b in tag.utf8 { h = (h &* 33) &+ Int(b) }
        return palette[abs(h) % palette.count]
    }
}

/// 全局便捷访问（向后兼容现有调用）
func tagColor(_ tag: String) -> Color {
    SessionTagStore.tagColor(tag)
}