import AVFoundation

// MARK: - v2.0.96c 语音转文字录音器（服务器 ASR：AVAudioRecorder 录音 → 上传转写）
// 侧载兼容：AVAudioRecorder 仅需麦克风权限（无 speech-recognition entitlement 限制），
// 替代 v2.0.85 因 SideStore SIGTRAP 移除的 SFSpeechRecognizer。

@MainActor
final class VoiceRecorder: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published var isRecording = false

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
    /// v3.1.2 根因修复（用户拍板方案A 2026-09-02）：主线程同步 setActive(.voiceChat) 会初始化系统
    /// AEC 声学回声消除管线、阻塞主线程 1s+ → App 卡死。改用轻量 .playAndRecord（无 .voiceChat mode），
    /// setActive 不初始化 AEC，主线程不阻塞。降噪识别交给服务端 whisper（VAD 兜底）。
    /// 注意：不能加 setActive(false)（v3.0.74 实踩会导致录音采不到字节）。
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let url = makeURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)
        } catch {
            // v2.0.102：启动失败清空上次残留（防 stop() 上传旧音频）
            recorder = nil
            audioURL = nil
            return false
        }

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            let ok = r.record()
            lastRecordOK = ok
            NSLog("[VOICE] record()->\(ok) url=\(url.lastPathComponent) mode=playAndRecord")
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
