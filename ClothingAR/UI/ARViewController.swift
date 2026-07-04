import UIKit
import SceneKit
import CoreImage
import Photos

final class ARViewController: UIViewController {

    // MARK: - Modules

    private let cameraManager = CameraManager()
    private let bodyTracker = BodyTracker()
    private let skeletonMapper = SkeletonMapper()
    private let sceneRenderer = SceneRenderer()
    private let personSegmentation = PersonSegmentation()
    private let videoRecorder = VideoRecorder()
    private let performanceMonitor = PerformanceMonitor()
    private let qualityManager = QualityManager()

    // MARK: - UI

    private var recordButton: RecordButton!
    private var statusIndicator: StatusIndicator!

    // MARK: - State

    private var isRecording: Bool = false
    private var isTogglingRecording: Bool = false
    private var viewSize: CGSize = .zero
    private var currentFPS: Int = 0

    /// 跟踪丢失后的计时
    private var trackingLostTime: CFTimeInterval?
    private var lastSkeletonPose: SkeletonPose?

    /// 模型加载状态
    private var modelLoaded: Bool = false

    // MARK: - Lifecycle

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // ── 初始化顺序必须严格 ──
        setupSceneRenderer()
        setupCamera()
        setupBodyTracker()
        setupPersonSegmentation()
        setupVideoRecorder()
        setupPerformanceMonitor()
        setupUI()
        setupLifecycleObservers()

        // 加载服装模型
        loadClothingModel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        viewSize = view.bounds.size
        sceneRenderer.scnView.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 从后台回来时恢复
        if case .ready = cameraManager.status {
            cameraManager.start()
        } else {
            cameraManager.checkAndRecover()
        }
        sceneRenderer.resume()
        performanceMonitor.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sceneRenderer.pause()
        performanceMonitor.stop()
        if isRecording {
            stopRecording()
        }
    }

    // MARK: - Setup: SceneRenderer

    private func setupSceneRenderer() {
        let scnView = sceneRenderer.scnView
        scnView.frame = view.bounds
        scnView.translatesAutoresizingMaskIntoConstraints = true
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scnView)

        // SceneKit 渲染代理：每帧应用待处理数据
        scnView.delegate = self
    }

    // MARK: - Setup: Camera

    private func setupCamera() {
        cameraManager.delegate = self
        cameraManager.setup()
    }

    // MARK: - Setup: Body Tracker

    private func setupBodyTracker() {
        bodyTracker.delegate = self
    }

    // MARK: - Setup: Person Segmentation

    private func setupPersonSegmentation() {
        personSegmentation.delegate = self
    }

    // MARK: - Setup: Video Recorder

    private func setupVideoRecorder() {
        videoRecorder.delegate = self
    }

    // MARK: - Setup: Performance Monitor

    private func setupPerformanceMonitor() {
        performanceMonitor.delegate = self
        qualityManager.delegate = self
    }

    // MARK: - Setup: UI

    private func setupUI() {
        // ── 录制按钮 ──
        recordButton = RecordButton()
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        view.addSubview(recordButton)

        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        // ── 状态指示器 ──
        statusIndicator = StatusIndicator()
        view.addSubview(statusIndicator)

        NSLayoutConstraint.activate([
            statusIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusIndicator.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
        ])
    }

    // MARK: - Setup: Notifications

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // 定期检查热状态
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.qualityManager.checkThermalState()
        }
    }

    // MARK: - Model Loading

    private func loadClothingModel() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 加载模型：优先 SCN（CI 构建时转换），fallback GLB
            guard let result = ModelLoader.load(named: "THIN_WELD_DECIMATED_new", extension: "scn")
               ?? ModelLoader.load(named: "THIN_WELD_DECIMATED_new", extension: "glb") else {
                DispatchQueue.main.async {
                    self.showModelLoadError()
                }
                return
            }

            DispatchQueue.main.async {
                self.onModelLoaded(result)
            }
        }
    }

    private func onModelLoaded(_ result: ModelLoadResult) {
        // ── 验证蒙皮 ──
        if result.skinnerNodes.isEmpty {
            let alert = UIAlertController(
                title: "模型无蒙皮数据",
                message: "FBX 文件缺少骨骼蒙皮信息。\n请在 Blender 中确认：\n1. 模型有骨架(Armature)\n2. 网格已绑定到骨架(Parent With Automatic Weights)\n3. 导出时勾选了 Armature",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        // ── 将模型注入 SceneRenderer ──
        sceneRenderer.clothingRootNode = result.rootNode

        // ── 建立骨骼节点映射 ──
        // boneMapping: [通用名: 模型骨骼名]
        // 需要从模型骨骼名找到实际 SCNNode
        let allBoneNodes = result.boneNodes
        for (genericName, modelBoneName) in result.boneMapping {
            if let node = allBoneNodes.first(where: { $0.name == modelBoneName }) {
                sceneRenderer.boneNodeMap[genericName] = node
            }
        }

        // ── 应用初始校准 ──
        ModelCalibration.apply(to: result.rootNode)
        ModelCalibration.printCalibration()

        // ── 更新骨架映射器的骨骼定义以匹配实际模型 ──
        print("[ARViewController] 骨骼映射已建立: \(sceneRenderer.boneNodeMap.count) 个骨骼")
        for (gen, node) in sceneRenderer.boneNodeMap {
            print("[ARViewController]   \(gen) → \(node.name ?? "?")")
        }

        modelLoaded = true
        statusIndicator.update(status: .tracking(fps: 0))

        // 启动相机
        cameraManager.start()
        performanceMonitor.start()
    }

    private func showModelLoadError() {
        let alert = UIAlertController(
            title: "模型加载失败",
            message: "未找到服装模型文件。\n\n请确认：\n1. Mixamo 绑骨后的 GLB 文件已放入 Resources/Models/\n2. 文件名为 THIN_WELD_DECIMATED_new.glb",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
        statusIndicator.update(status: .lost)
    }

    // MARK: - Recording

    @objc private func recordButtonTapped() {
        guard !isTogglingRecording else { return }
        isTogglingRecording = true

        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }

        // 0.5 秒内防连点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isTogglingRecording = false
        }
    }

    private func startRecording() {
        // ── 先检查存储空间 ──
        if let capacity = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity {
            if capacity < 100_000_000 { // < 100MB
                let alert = UIAlertController(
                    title: "存储空间不足",
                    message: "设备剩余空间不足 100MB，无法录制",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                present(alert, animated: true)
                return
            }
        }

        // ── 启用音频采集 ──
        cameraManager.enableAudio()

        // ── 开始录制 ──
        let videoSize = view.bounds.size
        videoRecorder.startRecording(videoSize: videoSize)
    }

    private func stopRecording() {
        videoRecorder.stopRecording()
        cameraManager.disableAudio()
    }

    // MARK: - Memory

    @objc private func handleMemoryWarning() {
        qualityManager.didReceiveMemoryWarning()
        sceneRenderer.cleanup()
        personSegmentation.reset()
    }

    // MARK: - Deinit

    deinit {
        NotificationCenter.default.removeObserver(self)
        performanceMonitor.stop()
        sceneRenderer.cleanup()
    }
}

// MARK: - SCNSceneRendererDelegate

extension ARViewController: SCNSceneRendererDelegate {

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // 每帧在主线程执行：应用所有待处理的缓冲数据
        sceneRenderer.applyPendingUpdates()

        // 录制时捕获渲染结果
        if isRecording, let recorder = videoRecorder as VideoRecorder?, recorder.isRecording {
            let snapshot = sceneRenderer.scnView.snapshot()
            if let pixelBuffer = imageToPixelBuffer(snapshot) {
                let timestamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
                recorder.appendVideo(pixelBuffer: pixelBuffer, timestamp: timestamp)
            }
        }
    }

    /// UIImage → CVPixelBuffer 快速转换
    private func imageToPixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        let size = image.size
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                 width: Int(size.width), height: Int(size.height),
                                 bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        UIGraphicsPushContext(context!)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        return pb
    }
}

// MARK: - CameraManagerDelegate

extension ARViewController: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didOutputVideo sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CACurrentMediaTime()

        // ── 更新背景画面 ──
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            sceneRenderer.updateBackground(with: cgImage)
        }

        // ── 人体姿态检测 ──
        bodyTracker.processFrame(pixelBuffer, timestamp: timestamp)

        // ── 人体分割（降频按需） ──
        personSegmentation.processFrameIfNeeded(pixelBuffer)
    }

    func cameraManager(_ manager: CameraManager, didOutputAudio sampleBuffer: CMSampleBuffer) {
        // 录制时才接收音频
        guard isRecording else { return }
        videoRecorder.appendAudio(sampleBuffer: sampleBuffer)
    }

    func cameraManager(_ manager: CameraManager, didChangeStatus isRunning: Bool) {
        DispatchQueue.main.async {
            if !isRunning {
                self.statusIndicator.update(status: .lost)
            }
        }
    }

    func cameraManager(_ manager: CameraManager, didFailWithPermission type: CameraManager.PermissionType) {
        DispatchQueue.main.async {
            let title = type == .camera ? "需要相机权限" : "需要麦克风权限"
            let msg = type == .camera
                ? "请在 [设置 > 隐私 > 相机] 中允许 ClothingAR 使用相机"
                : "请在 [设置 > 隐私 > 麦克风] 中允许 ClothingAR 使用麦克风"
            let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            self.present(alert, animated: true)
        }
    }
}

// MARK: - BodyTrackerDelegate

extension ARViewController: BodyTrackerDelegate {

    func bodyTracker(_ tracker: BodyTracker, didDetectBody bodyData: BodyJointData) {
        trackingLostTime = nil

        // ── 2D → 3D 骨骼映射 ──
        guard let pose = skeletonMapper.mapToSkeleton(bodyData: bodyData, viewSize: viewSize) else {
            return
        }

        lastSkeletonPose = pose

        // ── 更新骨骼旋转到 SceneRenderer ──
        sceneRenderer.updateBoneRotations(pose.rotations)
    }

    func bodyTrackerDidLoseTracking(_ tracker: BodyTracker) {
        let now = CACurrentMediaTime()

        if trackingLostTime == nil {
            trackingLostTime = now
        }

        if now - trackingLostTime! >= 3.0 {
            // 超过 3 秒跟踪丢失 → 复位
            DispatchQueue.main.async {
                self.statusIndicator.update(status: .lost)
                // 复位模型到 T-Pose（清空骨骼旋转）
                self.sceneRenderer.updateBoneRotations([:])
                self.lastSkeletonPose = nil
            }
            skeletonMapper.reset()
            bodyTracker.reset()
        }
        // < 3 秒：保持上一帧骨骼姿态，由 BodyTracker 内部管理
    }

    func bodyTrackerDidRecoverTracking(_ tracker: BodyTracker) {
        DispatchQueue.main.async {
            self.statusIndicator.update(status: .tracking(fps: self.currentFPS))
        }
    }
}

// MARK: - PersonSegmentationDelegate

extension ARViewController: PersonSegmentationDelegate {

    func personSegmentation(_ segmentation: PersonSegmentation,
                            didProduceMask maskImage: CGImage) {
        sceneRenderer.updateSegmentationMask(maskImage)
    }
}

// MARK: - VideoRecorderDelegate

extension ARViewController: VideoRecorderDelegate {

    func videoRecorder(_ recorder: VideoRecorder, didFinishWith url: URL, error: Error?) {
        isRecording = false
        recordButton.isRecording = false

        if let error = error {
            let alert = UIAlertController(
                title: "录制失败",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        // ── 保存到相册 ──
        PhotoAlbumSaver.saveVideo(at: url) { [weak self] success, message in
            guard let self else { return }

            if success {
                // Toast 提示
                let toast = UILabel()
                toast.text = " ✅ 已保存到相册"
                toast.textColor = .white
                toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                toast.textAlignment = .center
                toast.font = UIFont.systemFont(ofSize: 15)
                toast.layer.cornerRadius = 10
                toast.layer.masksToBounds = true
                toast.frame = CGRect(x: 0, y: 0, width: 180, height: 40)
                toast.center = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.maxY - 120)
                self.view.addSubview(toast)

                UIView.animate(withDuration: 0.3, delay: 1.0, options: .curveEaseOut) {
                    toast.alpha = 0
                } completion: { _ in
                    toast.removeFromSuperview()
                }
            } else {
                let alert = UIAlertController(
                    title: "保存失败",
                    message: message ?? "未知错误",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    func videoRecorderDidStart(_ recorder: VideoRecorder) {
        isRecording = true
        recordButton.isRecording = true
    }
}

// MARK: - PerformanceMonitorDelegate

extension ARViewController: PerformanceMonitorDelegate {

    func performanceMonitor(_ monitor: PerformanceMonitor, didUpdateFPS fps: Int) {
        currentFPS = fps
        let now = CACurrentMediaTime()

        // 更新 QualityManager
        qualityManager.updateFPS(fps, timestamp: now)

        // 更新状态指示器
        DispatchQueue.main.async {
            switch self.qualityManager.currentLevel {
            case .normal:
                self.statusIndicator.update(status: .tracking(fps: fps))
            case .warning, .degraded:
                self.statusIndicator.update(status: .degraded(fps: fps, reason: ""))
            case .critical:
                self.statusIndicator.update(status: .degraded(fps: fps, reason: "严重降级"))
            }
        }
    }
}

// MARK: - QualityManagerDelegate

extension ARViewController: QualityManagerDelegate {

    func qualityManager(_ manager: QualityManager, didChangeTo level: QualityLevel) {
        print("[ARViewController] 质量级别: \(level.rawValue)")
    }

    func qualityManager(_ manager: QualityManager, didChangeSegmentationInterval frames: Int) {
        personSegmentation.framesBetweenSegmentation = frames
        print("[ARViewController] 分割降频: 每 \(frames) 帧")
    }
}
