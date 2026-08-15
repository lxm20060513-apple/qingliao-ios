import Speech
import AVFoundation

// MARK: - v2.0.96 语音转文字（v2.0.81 恢复版：长按发送按钮触发，实时转写进输入框）
// v2.0.85 曾因 SideStore 侧载缺 speech-recognition entitlement 闪退移除；
// 恢复时带环境可用性检查（requestAuth 返回授权状态，失败提示不闪退）

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var text = ""
    @Published var isRecording = false
    @Published var authorized = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAuth() async -> Bool {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        authorized = (status == .authorized && recognizer?.isAvailable == true)
        return authorized
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
                Task { @MainActor in
                    if let r = result {
                        self?.text = r.bestTranscription.formattedString
                    }
                    if r?.isFinal == true || error != nil {
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
}
