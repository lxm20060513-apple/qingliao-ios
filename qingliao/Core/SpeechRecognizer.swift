import Speech
import AVFoundation

// MARK: - v2.0.81 AI 回复朗读（全局单例，多消息共用；朗读中再点停止）

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
        // v2.0.85e：朗读前激活 playback 音频会话（否则静音/其他 App 占用时无声）
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                         options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
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
