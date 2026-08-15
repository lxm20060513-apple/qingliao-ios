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
            return false
        }
    }

    /// 停止录音，返回音频文件（用于上传转写）
    func stop() -> URL? {
        recorder?.stop()
        isRecording = false
        return audioURL
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
    }
}
