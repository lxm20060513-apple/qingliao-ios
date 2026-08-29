import AVFoundation

// MARK: - v2.0.96c 语音转文字录音器（服务器 ASR：AVAudioRecorder 录音 → 上传转写）
// 侧载兼容：AVAudioRecorder 仅需麦克风权限（无 speech-recognition entitlement 限制），
// 替代 v2.0.85 因 SideStore SIGTRAP 移除的 SFSpeechRecognizer。

@MainActor
final class VoiceRecorder: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var audioURL: URL?

    /// 开始录音（返回是否成功；失败=无麦克风权限）
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            // v3.0.74：先释放旧会话再激活（避免上次录音未释放导致 setCategory 失败）
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            // v2.0.102：启动失败清空上次残留（防 stop() 上传旧音频）
            recorder = nil
            audioURL = nil
            return false
        }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("voice_asr.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            // v2.0.107：44.1k→16k 采样（whisper 原生 16k，识别质量无损；文件小 2.7 倍，蜂窝上传更快）
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.record()
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
        recorder?.stop()
        isRecording = false
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        return audioURL
    }

    /// v3.0.36 分段流式：暂停当前段并返回音频（保留 record 会话，供立即重录下一段）
    /// 仅切换 AVAudioRecorder 实例，不切 AVAudioSession——避免 stop() 的会话重置开销
    func stopCurrentSegment() -> URL? {
        guard let r = recorder else { return nil }
        r.stop()
        let u = audioURL
        audioURL = nil
        recorder = nil
        return u
    }

    /// v3.0.36 分段流式：续录新段（沿用 start 的会话设置，快速重建 recorder）
    func resumeSegment() -> Bool {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("voice_asr.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.record()
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
