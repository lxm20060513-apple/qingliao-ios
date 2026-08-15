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
            AVSampleRateKey: 44100,
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

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
    }
}
