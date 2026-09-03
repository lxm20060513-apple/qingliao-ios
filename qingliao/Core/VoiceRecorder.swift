import AVFoundation

// MARK: - v2.0.96c 语音转文字录音器（服务器 ASR：AVAudioRecorder 录音 → 上传转写）
// 侧载兼容：AVAudioRecorder 仅需麦克风权限（无 speech-recognition entitlement 限制），
// 替代 v2.0.85 因 SideStore SIGTRAP 移除的 SFSpeechRecognizer。
// v3.1.4+ 修复：setCategory/setActive 移到后台线程，避免主线程阻塞卡死

@MainActor
final class VoiceRecorder: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    /// v3.0.78 诊断：AVAudioRecorder.record() 返回值（false=录音未真正开始，多因麦克风权限/会话未激活）
    private(set) var lastRecordOK: Bool? = nil
    /// v3.1.4+：后台音频会话配置中标志（防止 stop() 在配置完成前打断会话）
    private var sessionConfiguring = false

    /// v3.0.76：每个录音段用独立文件名（避免分段流式反复 stop/resume 同一 URL 的数据竞争 / 读到空段）
    /// v3.0.x fix：加单调递增计数器，防止高频调用时时间戳重复产生相同文件名
    private static var _urlCounter: Int = 0
    private func makeURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        Self._urlCounter += 1
        let name = "voice_asr_\(Int(Date().timeIntervalSince1970 * 1000))_\(Self._urlCounter).m4a"
        return dir.appendingPathComponent(name)
    }

    /// 开始录音（异步：音频会话配置在后台线程，不阻塞主线程）
    /// v3.1.4+ 修复：setCategory(.playAndRecord)/setActive(true) 可能阻塞主线程数百毫秒。
    /// 改为后台线程配置会话，UI 立即响应，录音就绪后自动开始。
    func start() -> Bool {
        let url = makeURL()

        // v3.1.4+：先标记录音中（UI 立即显示录音状态），音频会话在后台配置
        sessionConfiguring = true
        isRecording = true
        audioURL = url

        // 后台线程配置音频会话（setCategory + setActive 是阻塞调用）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let session = AVAudioSession.sharedInstance()
            var sessionOK = false
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
                try session.setActive(true)
                sessionOK = true
            } catch {
                NSLog("[VOICE] session config failed: \(error)")
            }

            // 回到主线程创建 AVAudioRecorder（必须在主线程操作 @MainActor 属性）
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sessionConfiguring = false

                // v3.1.5: 如果 stop() 在后台配置期间被调用，isRecording 已被清除，不再创建 recorder
                guard self.isRecording else { return }

                guard sessionOK else {
                    self.isRecording = false
                    self.recorder = nil
                    self.audioURL = nil
                    self.lastRecordOK = false
                    return
                }

                // v3.1.7: settings 在 MainActor 闭包内创建，避免跨 actor 传递 [String:Any] 数据竞争
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
                    self.lastRecordOK = ok
                    NSLog("[VOICE] record()->\(ok) url=\(url.lastPathComponent) mode=playAndRecord")
                    if ok {
                        self.recorder = r
                    } else {
                        self.isRecording = false
                        self.audioURL = nil
                    }
                } catch {
                    NSLog("[VOICE] recorder create failed: \(error)")
                    self.isRecording = false
                    self.recorder = nil
                    self.audioURL = nil
                    self.lastRecordOK = false
                }
            }
        }
        // 立即返回 true（UI 已切换到录音状态，录音实际在后台就绪后开始）
        return true
    }

    /// 停止录音，返回音频文件（用于上传转写）
    /// v2.0.102：恢复音频会话为 playback 并停用——否则 TTS 朗读无声
    /// v3.1.4+：setActive(false) 移到后台线程，避免阻塞主线程
    func stop() -> URL? {
        if let r = recorder { r.stop() }
        let url = audioURL
        isRecording = false
        recorder = nil
        audioURL = nil

        if let u = url {
            let sz: Int = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int ?? -1
            NSLog("[VOICE] stop() url=\(u.lastPathComponent) size=\(sz)")
        }

        // 后台恢复音频会话（避免阻塞主线程）
        DispatchQueue.global(qos: .utility).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        return url
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
