import AVFoundation
import UIKit

// MARK: - Delegate Protocol

protocol CameraManagerDelegate: AnyObject {
    /// 视频帧回调（后台队列）
    func cameraManager(_ manager: CameraManager, didOutputVideo sampleBuffer: CMSampleBuffer)
    /// 音频帧回调（后台队列，仅录制时）
    func cameraManager(_ manager: CameraManager, didOutputAudio sampleBuffer: CMSampleBuffer)
    /// 相机状态变更
    func cameraManager(_ manager: CameraManager, didChangeStatus isRunning: Bool)
    /// 权限错误
    func cameraManager(_ manager: CameraManager, didFailWithPermission type: CameraManager.PermissionType)
}

// MARK: - CameraManager

final class CameraManager: NSObject {

    enum PermissionType {
        case camera
        case microphone
    }

    enum Status {
        case uninitialized
        case ready
        case running
        case failed(Error)
    }

    // MARK: - Public Properties

    weak var delegate: CameraManagerDelegate?
    private(set) var status: Status = .uninitialized
    private(set) var isRecordingAudio: Bool = false

    // MARK: - Private Properties

    private let session = AVCaptureSession()
    private let sessionLock = NSLock()

    // 视频
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.clothingar.camera.video", qos: .userInitiated)

    // 音频（按需启用）
    private var audioOutput: AVCaptureAudioDataOutput?
    private let audioQueue = DispatchQueue(label: "com.clothingar.camera.audio", qos: .userInitiated)

    // 防抖：视频帧处理中标记
    private var isProcessingVideoFrame = false

    // MARK: - Session Interruption

    private var wasInterrupted = false
    private var wasRecordingWhenInterrupted = false

    // MARK: - Setup

    /// 初始化相机采集管线（先请求权限再配置）
    func setup() {
        checkCameraPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.status = .failed(NSError(domain: "CameraManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "相机权限被拒绝"]))
                self.delegate?.cameraManager(self, didFailWithPermission: .camera)
                return
            }
            self.configureSession()
        }
    }

    // MARK: - Permission

    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    // MARK: - Session Configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium // A11 性能最优选择

        // ── 视频输入：前置摄像头 ──
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoInput = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            status = .failed(NSError(domain: "CameraManager", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "无法访问前置摄像头"]))
            return
        }
        guard session.canAddInput(videoInput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)

        // ── 视频输出 ──
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true // 弃旧帧，不积压
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        // ── 竖屏 + 前置镜像 ──
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            connection.isVideoMirrored = true // 前置摄像头镜像
        }

        session.commitConfiguration()
        status = .ready

        // ── 监听中断 ──
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    // MARK: - Start / Stop

    func start() {
        guard case .ready = status else { return }
        sessionLock.lock()
        session.startRunning()
        sessionLock.unlock()
        status = .running
        delegate?.cameraManager(self, didChangeStatus: true)
    }

    func stop() {
        sessionLock.lock()
        session.stopRunning()
        sessionLock.unlock()
        status = .ready
        delegate?.cameraManager(self, didChangeStatus: false)
    }

    // MARK: - Audio (按需启用，省电)

    func enableAudio() {
        guard audioOutput == nil else { return }
        requestMicrophonePermission { [weak self] granted in
            guard let self, granted else {
                self?.delegate?.cameraManager(self!, didFailWithPermission: .microphone)
                return
            }
            self.addAudioOutput()
        }
    }

    private func addAudioOutput() {
        session.beginConfiguration()
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: audioQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        session.commitConfiguration()
        audioOutput = output
        isRecordingAudio = true
    }

    func disableAudio() {
        guard let output = audioOutput else { return }
        output.setSampleBufferDelegate(nil, queue: nil)  // 立即停止回调
        session.beginConfiguration()
        session.removeOutput(output)
        session.commitConfiguration()
        audioOutput = nil
        isRecordingAudio = false
    }

    // MARK: - Interruption Handling

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        wasInterrupted = true
        wasRecordingWhenInterrupted = isRecordingAudio
        // 被打断时自动停止录制
        if isRecordingAudio {
            disableAudio()
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        wasInterrupted = false
        // 恢复相机
        sessionLock.lock()
        session.startRunning()
        sessionLock.unlock()
        status = .running
        delegate?.cameraManager(self, didChangeStatus: true)
    }

    // MARK: - Check Running

    func checkAndRecover() {
        guard case .running = status, !session.isRunning, !wasInterrupted else { return }
        sessionLock.lock()
        session.startRunning()
        sessionLock.unlock()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        if output == videoOutput {
            // 防抖：上一帧还在处理则直接丢弃，避免 Vision 请求堆积
            guard !isProcessingVideoFrame else { return }
            isProcessingVideoFrame = true
            delegate?.cameraManager(self, didOutputVideo: sampleBuffer)
            isProcessingVideoFrame = false
        } else if output == audioOutput {
            delegate?.cameraManager(self, didOutputAudio: sampleBuffer)
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // 丢帧不做处理，保持静默
    }
}
