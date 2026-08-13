import Speech
import AVFoundation

// MARK: - v2.0.81 语音输入（按住说话 → 中文 ASR 转文字）

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var text = ""
    @Published var isRecording = false
    @Published var authorized = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAuth() async {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        authorized = (status == .authorized && recognizer?.isAvailable == true)
    }

    func start() {
        guard authorized, !isRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            text = ""
            let node = engine.inputNode
            let rq = SFSpeechAudioBufferRecognitionRequest()
            rq.shouldReportPartialResults = true
            request = rq
            task = recognizer?.recognitionTask(with: rq) { [weak self] result, error in
                let final = result?.isFinal ?? false
                let text = result?.bestTranscription.formattedString ?? ""
                let failed = (error != nil)
                Task { @MainActor in
                    if !text.isEmpty {
                        self?.text = text
                    }
                    if final || failed {
                        self?.stop()
                    }
                }
            }
            let format = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            isRecording = false
        }
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 发送后清空
    func reset() {
        text = ""
    }
}

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
