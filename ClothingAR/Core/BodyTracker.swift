import Vision
import CoreGraphics

// MARK: - Body Joint Data

/// 一帧人体姿态检测结果
struct BodyJointData {
    /// Vision 检测到的关键点（归一化 0...1 坐标）
    let points: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// 每个点的置信度
    let confidences: [VNHumanBodyPoseObservation.JointName: Float]
    /// 检测到的人体包围盒
    let boundingBox: CGRect
    /// 时间戳
    let timestamp: CFTimeInterval

    /// 是否有足够的关键点（至少需要核心关节）
    var isValid: Bool {
        let requiredJoints: [VNHumanBodyPoseObservation.JointName] = [
            .root, .neck,
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip
        ]
        return requiredJoints.allSatisfy { confidences[$0] ?? 0 > 0.3 }
    }
}

// MARK: - BodyTrackerDelegate

protocol BodyTrackerDelegate: AnyObject {
    func bodyTracker(_ tracker: BodyTracker, didDetectBody bodyData: BodyJointData)
    func bodyTrackerDidLoseTracking(_ tracker: BodyTracker)
    func bodyTrackerDidRecoverTracking(_ tracker: BodyTracker)
}

// MARK: - BodyTracker

final class BodyTracker {

    weak var delegate: BodyTrackerDelegate?

    // MARK: - Configuration

    /// 关节置信度最低阈值
    let confidenceThreshold: Float = 0.3

    // MARK: - Private

    private let request = VNDetectHumanBodyPoseRequest()
    private let trackingQueue = DispatchQueue(label: "com.clothingar.bodytracker", qos: .userInitiated)

    /// EMA 平滑：存储上一帧每个关节的坐标
    private var previousPoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    /// 平滑系数（0 = 完全用历史，1 = 完全用新值）
    private let smoothingAlpha: CGFloat = 0.3

    /// 日志限频：避免没人时刷屏
    private var lastNoPersonLogTime: CFTimeInterval = 0
    private let logThrottleInterval: CFTimeInterval = 3.0

    /// 跟踪状态
    private(set) var isTracking: Bool = false
    private var trackingLostStartTime: CFTimeInterval = 0

    // MARK: - Process Frame

    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            // Vision 内部错误，静默跳过
            return
        }

        guard let observation = request.results?.first else {
            handleNoDetection(timestamp: timestamp)
            return
        }

        // ── 取 boundingBox 最大的人（有多个人的情况） ──
        // VNDetectHumanBodyPoseRequest 默认返回多人结果，这里用 request.results
        // results 已按 confidence 排序，取第一个即可
        let boundingBox = observation.boundingBox

        // ── 提取关键点 ──
        var points: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var confidences: [VNHumanBodyPoseObservation.JointName: Float] = [:]

        let allJoints: [VNHumanBodyPoseObservation.JointName] = [
            .root, .neck,
            .leftShoulder, .leftElbow, .leftWrist,
            .rightShoulder, .rightElbow, .rightWrist,
            .leftHip, .leftKnee, .leftAnkle,
            .rightHip, .rightKnee, .rightAnkle,
            // 额外的辅助关节点（如果有）
            .leftEye, .rightEye, .nose
        ]

        for joint in allJoints {
            guard let point = try? observation.recognizedPoint(joint),
                  point.confidence > confidenceThreshold else {
                continue
            }
            // Vision 返回归一化坐标 (0...1)，原点在左下角
            points[joint] = point.location
            confidences[joint] = point.confidence
        }

        // ── EMA 平滑 ──
        let smoothedPoints = applySmoothing(points)

        // ── 构建结果 ──
        let bodyData = BodyJointData(
            points: smoothedPoints,
            confidences: confidences,
            boundingBox: boundingBox.boundingBox,
            timestamp: timestamp
        )

        guard bodyData.isValid else {
            handleNoDetection(timestamp: timestamp)
            return
        }

        // ── 恢复跟踪 ──
        if !isTracking {
            isTracking = true
            trackingLostStartTime = 0
            delegate?.bodyTrackerDidRecoverTracking(self)
        }

        delegate?.bodyTracker(self, didDetectBody: bodyData)

        // 缓存用于下一帧平滑
        previousPoints = smoothedPoints
    }

    // MARK: - No Detection Handling

    private func handleNoDetection(timestamp: CFTimeInterval) {
        if !isTracking {
            // 本来就没跟踪，限频打日志
            let now = timestamp
            if now - lastNoPersonLogTime > logThrottleInterval {
                lastNoPersonLogTime = now
                print("[BodyTracker] 未检测到人体")
            }
            delegate?.bodyTrackerDidLoseTracking(self)
            return
        }

        // 刚丢失跟踪，记录时间
        if trackingLostStartTime == 0 {
            trackingLostStartTime = timestamp
            delegate?.bodyTrackerDidLoseTracking(self)
        }

        // 超过 3 秒才真正标记为 lost
        if timestamp - trackingLostStartTime > 3.0 {
            isTracking = false
            previousPoints = [:]
        }
    }

    // MARK: - EMA Smoothing

    /// 指数移动平均，减少帧间抖动
    private func applySmoothing(_ current: [VNHumanBodyPoseObservation.JointName: CGPoint])
        -> [VNHumanBodyPoseObservation.JointName: CGPoint] {

        guard !previousPoints.isEmpty else { return current }

        var smoothed: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in current {
            if let prev = previousPoints[joint] {
                smoothed[joint] = CGPoint(
                    x: smoothingAlpha * point.x + (1 - smoothingAlpha) * prev.x,
                    y: smoothingAlpha * point.y + (1 - smoothingAlpha) * prev.y
                )
            } else {
                smoothed[joint] = point
            }
        }
        return smoothed
    }

    // MARK: - Reset

    func reset() {
        isTracking = false
        trackingLostStartTime = 0
        previousPoints = [:]
    }
}
