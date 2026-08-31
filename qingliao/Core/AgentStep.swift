import Foundation

// MARK: - v3.1.0 Agent 任务进度卡
// 本地模式：后端 poll 响应 steps 字段 [{"t","s"}] 解析而来（_agent_loop 每轮工具调用上报）
// 云端模式：CloudToolLoop 工具执行前后生成（toolPreview 文案）
// state: "running"（执行中）| "done"（已完成）
struct AgentStep: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var state: String

    var isRunning: Bool { state == "running" }

    /// v3.1.0：相等只看内容（text+state），忽略 id——poll 全量替换时内容不变不触发 UI 重建
    static func == (lhs: AgentStep, rhs: AgentStep) -> Bool {
        lhs.text == rhs.text && lhs.state == rhs.state
    }

    /// 从后端 poll 的 [{"t": "...", "s": "..."}] 解析
    static func parse(_ arr: [[String: Any]]?) -> [AgentStep] {
        guard let arr else { return [] }
        return arr.compactMap { d in
            guard let t = d["t"] as? String, let s = d["s"] as? String else { return nil }
            guard s == "running" || s == "done" else { return nil }   // v3.1.0：未知状态丢弃（防渲染错）
            return AgentStep(text: t, state: s)
        }
    }

    /// 从云端 toolCalls/工具执行构造
    static func make(_ text: String, _ state: String) -> AgentStep {
        AgentStep(text: text, state: state)
    }
}
