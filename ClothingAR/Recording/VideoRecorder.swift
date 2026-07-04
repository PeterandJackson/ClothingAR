import AVFoundation
import UIKit

// MARK: - VideoRecorderDelegate

protocol VideoRecorderDelegate: AnyObject {
    func videoRecorder(_ recorder: VideoRecorder, didFinishWith url: URL, error: Error?)
    func videoRecorderDidStart(_ recorder: VideoRecorder)
}

// MARK: - VideoRecorder

final class VideoRecorder {

    weak var delegate: VideoRecorderDelegate?

    // MARK: - State

    private(set) var isRecording: Bool = false
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let writerQueue = DispatchQueue(label: "com.clothingar.recorder", qos: .userInitiated)
    private var isSessionStarted = false

    /// 首帧时间戳（用于后续帧时间对齐）
    private var firstVideoTimestamp: CMTime?
    private var firstAudioTimestamp: CMTime?

    /// 统一的 timescale
    private let timescale: CMTimeScale = 600

    // MARK: - Start Recording

    /// 开始录制
    /// - Parameters:
    ///   - videoSize: 输出视频尺寸（渲染分辨率）
    func startRecording(videoSize: CGSize) {
        guard !isRecording else { return }

        isRecording = true
        isSessionStarted = false
        firstVideoTimestamp = nil
        firstAudioTimestamp = nil

        writerQueue.async { [weak self] in
            self?.setupWriter(videoSize: videoSize)
        }
    }

    private func setupWriter(videoSize: CGSize) {
        // ── 清理旧临时文件 ──
        let outputURL = tempOutputURL()
        try? FileManager.default.removeItem(at: outputURL)

        // ── AVAssetWriter ──
        guard let writer = try? AVAssetWriter(url: outputURL, fileType: .mp4) else {
            print("[VideoRecorder] ❌ 无法创建 AVAssetWriter")
            isRecording = false
            return
        }
        assetWriter = writer

        // ── 视频输入 ──
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        vInput.transform = CGAffineTransform(rotationAngle: 0) // 竖屏无需旋转

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height),
            ]
        )
        pixelBufferAdaptor = adaptor

        guard writer.canAdd(vInput) else {
            print("[VideoRecorder] ❌ 无法添加视频输入")
            isRecording = false
            return
        }
        writer.add(vInput)
        videoInput = vInput

        // ── 音频输入 ──
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]

        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        if writer.canAdd(aInput) {
            writer.add(aInput)
            audioInput = aInput
        }

        // ── 启动写入 ──
        writer.startWriting()
    }

    // MARK: - Append Video Frame

    func appendVideo(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isRecording,
              let writer = assetWriter,
              let input = videoInput,
              input.isReadyForMoreMediaData else {
            return
        }

        if !isSessionStarted {
            // 等音频也准备好再开始 session
            if let aInput = audioInput, !aInput.isReadyForMoreMediaData {
                return
            }
            writer.startSession(atSourceTime: timestamp)
            isSessionStarted = true
            firstVideoTimestamp = timestamp
            delegate?.videoRecorderDidStart(self)
        }

        guard let adaptor = pixelBufferAdaptor else { return }

        let relativeTime = relativeTimestamp(timestamp)
        if !adaptor.append(pixelBuffer, withPresentationTime: relativeTime) {
            print("[VideoRecorder] ⚠️ 写入视频帧失败: \(writer.error?.localizedDescription ?? "未知错误")")
        }
    }

    // MARK: - Append Audio

    func appendAudio(sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              isSessionStarted,
              let writer = assetWriter,
              let input = audioInput,
              input.isReadyForMoreMediaData else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstAudioTimestamp == nil {
            firstAudioTimestamp = timestamp
        }

        let relativeTime = relativeTimestamp(timestamp)

        // 重新打包音频 buffer 到统一 timescale
        if let adaptedBuffer = adaptAudioTimestamp(sampleBuffer, to: relativeTime) {
            if !input.append(adaptedBuffer) {
                print("[VideoRecorder] ⚠️ 写入音频帧失败: \(writer.error?.localizedDescription ?? "未知错误")")
            }
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        let writer = assetWriter
        let videoIn = videoInput
        let audioIn = audioInput

        videoInput = nil
        audioInput = nil
        assetWriter = nil
        pixelBufferAdaptor = nil

        videoIn?.markAsFinished()
        audioIn?.markAsFinished()

        writer?.finishWriting { [weak self] in
            guard let self else { return }
            let url = writer?.outputURL ?? self.tempOutputURL()
            let error = writer?.error
            DispatchQueue.main.async {
                self.delegate?.videoRecorder(self, didFinishWith: url, error: error)
            }
        }
    }

    // MARK: - Timestamp Helpers

    private func relativeTimestamp(_ absolute: CMTime) -> CMTime {
        guard let first = firstVideoTimestamp else { return absolute }
        let diff = CMTimeSubtract(absolute, first)
        return CMTimeConvertScale(diff, timescale: timescale, method: .quickTime)
    }

    /// 将音频 sample buffer 的时间戳适配到统一 timescale
    private func adaptAudioTimestamp(_ buffer: CMSampleBuffer, to targetTime: CMTime) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo()
        timingInfo.duration = CMSampleBufferGetDuration(buffer)
        timingInfo.presentationTimeStamp = targetTime
        timingInfo.decodeTimeStamp = targetTime

        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        guard status == noErr else { return nil }
        return newBuffer
    }

    // MARK: - URL

    private func tempOutputURL() -> URL {
        let dir = NSTemporaryDirectory()
        let filename = "clothing_ar_\(Int(Date().timeIntervalSince1970)).mp4"
        return URL(fileURLWithPath: (dir as NSString).appendingPathComponent(filename))
    }

    // MARK: - Cleanup

    deinit {
        if isRecording {
            stopRecording()
        }
    }
}
