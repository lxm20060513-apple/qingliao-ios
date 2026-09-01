import AVFoundation

// MARK: - v2.0.96c 语音转文字录音器（服务器 ASR：AVAudioRecorder 录音 → 上传转写）
// 侧载兼容：AVAudioRecorder 仅需麦克风权限（无 speech-recognition entitlement 限制），
// 替代 v2.0.85 因 SideStore SIGTRAP 移除的 SFSpeechRecognizer。

@MainActor
final class VoiceRecorder: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published var isRecording = false

    /// v3.0.85：.voiceChat 预热标志——后台线程首次初始化成功后置 true，后续录音直接用（不阻塞主线程）
    static var voiceChatReady = false

    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    /// v3.0.78 诊断：AVAudioRecorder.record() 返回值（false=录音未真正开始，多因麦克风权限/会话未激活）
    private(set) var lastRecordOK: Bool? = nil

    /// v3.0.76：每个录音段用独立文件名（避免分段流式反复 stop/resume 同一 URL 的数据竞争 / 读到空段）
    private func makeURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "voice_asr_\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
        return dir.appendingPathComponent(name)
    }

    /// 开始录音（返回是否成功；失败=无麦克风权限）
    /// v3.0.85 fix：.voiceChat setActive 可能阻塞主线程（系统初始化 AEC 管线），先在后台预热，主线程不等
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let url = makeURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        // .voiceChat 预热：后台线程尝试，主线程立即用 .record 兜底开始录音（不卡 UI）
        // 预热成功后下次录音自动用 .voiceChat（热路径不再阻塞）
        if Self.voiceChatReady {
            // 已预热 → 直接用 .voiceChat
            do {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: .defaultToSpeaker)
                try session.setActive(true)
            } catch {
                try? session.setCategory(.record, mode: .default)
                try? session.setActive(true)
            }
        } else {
            // 首次/未就绪 → .record 兜底 + 后台预热 .voiceChat
            try? session.setCategory(.record, mode: .default)
            try? session.setActive(true)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.setCategory(.playAndRecord, mode: .voiceChat, options: .defaultToSpeaker)
                    try session.setActive(true)
                    Self.voiceChatReady = true
                    NSLog("[VOICE] .voiceChat preheat OK")
                } catch {
                    NSLog("[VOICE] .voiceChat preheat fail: \(error)")
                }
            }
        }

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            let ok = r.record()
            lastRecordOK = ok
            NSLog("[VOICE] record()->\(ok) url=\(url.lastPathComponent) voiceChat=\(Self.voiceChatReady)")
            recorder = r
            audioURL = url
            isRecording = true
            return true
        } catch {
            recorder = nil
            audioURL = nil
            return false
        }
    }

    /// 停止录音，返回音频文件（用于上传转写）
    /// v2.0.102：恢复音频会话为 playback 并停用——否则 TTS 朗读无声（setCategory(.record) 未恢复）
    func stop() -> URL? {
        if let r = recorder { r.stop() }
        isRecording = false
        if let u = audioURL {
            let sz: Int = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int ?? -1
            NSLog("[VOICE] stop() url=\(u.lastPathComponent) size=\(sz)")
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        return audioURL
    }

    /// v3.0.36 分段流式：暂停当前段并返回音频（保留 record 会话，供立即重录下一段）
    /// 仅切换 AVAudioRecorder 实例，不切 AVAudioSession——避免 stop() 的会话重置开销
    /// v3.0.76：每段用独立文件名（resumeSegment 生成新 URL），杜绝 stop→读→resume 同一文件的覆盖竞争
    func stopCurrentSegment() -> URL? {
        guard let r = recorder else { return nil }
        r.stop()
        let u = audioURL
        audioURL = nil
        recorder = nil
        return u
    }

    /// v3.0.36 分段流式：续录新段（沿用 start 的会话设置，快速重建 recorder）
    /// v3.0.76：改独立文件名，不再复用 voice_asr.m4a（配合 flushVoiceSegment 先读后 resume）
    func resumeSegment() -> Bool {
        let url = makeURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            let ok = r.record()
            lastRecordOK = ok
            NSLog("[VOICE] record()->\(ok) url=\(url.lastPathComponent)")
            recorder = r
            audioURL = url
            isRecording = true
            return true
        } catch {
            recorder = nil
            audioURL = nil
            return false
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
    }
}
