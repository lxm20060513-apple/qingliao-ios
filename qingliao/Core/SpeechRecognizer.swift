import AVFoundation

// MARK: - v2.0.81 AI 回复朗读（全局单例，多消息共用；朗读中再点停止）
// v2.0.96c：语音输入已改服务器 ASR（VoiceRecorder 录音上传），SFSpeechRecognizer 类移除（SideStore 闪退）

@MainActor
final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()
    @Published var speakingID: String?

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(_ raw: String, id: String) {
        if speakingID == id {
            stop()
            return
        }
        stop()
        // 去掉 markdown 符号 + 换行变句号
        let clean = raw
            .replacingOccurrences(of: #"[*#`>_~\[\]()!|\-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n+", with: "。", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let ut = AVSpeechUtterance(string: clean)
        ut.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        ut.rate = 0.48
        speakingID = id
        synth.speak(ut)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speakingID = nil
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingID = nil
        }
    }
}
