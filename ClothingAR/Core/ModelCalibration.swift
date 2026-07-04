import SceneKit

// MARK: - Calibration Configuration

/// 模型校准参数 — 在此修改以适应不同模型/人体
/// 这些值会在真机测试后确定最佳值，然后固定
struct CalibrationConfig {

    // MARK: - 模型缩放（自动计算 + 手动微调）

    /// 模型缩放系数（整体缩放）
    /// 初始 1.0，范围 0.5 ~ 2.0
    /// 如果衣服比人大很多，缩小；反之放大
    static var modelScale: Float = 1.0

    // MARK: - 模型位置偏移（SceneKit 世界坐标系）

    /// +X = 右, +Y = 上, +Z = 向前（朝镜头）
    /// 单位：米

    /// 左右偏移：用于对中人体中心
    static var modelOffsetX: Float = 0.0

    /// 上下偏移：让肩膀线与模型肩膀对齐
    /// +Y 往上移（衣服相对于人往上）
    static var modelOffsetY: Float = 0.0

    /// 前后偏移：+Z 朝镜头方向（衣服更靠前）
    /// 调整衣服和人体的前后位置关系
    static var modelOffsetZ: Float = 0.0

    // MARK: - 人体参数

    /// 目标人体身高（米），用于自动缩放比例计算
    static var bodyHeight: Float = 1.7

    // MARK: - 遮挡平面参数

    /// 遮挡平面距离相机的距离（米）
    /// 越近遮挡越多，越远遮挡越少
    static var occlusionPlaneDistance: Float = 0.8

    // MARK: - 骨骼驱动参数

    /// 上半身旋转灵敏度（1.0 = 正常）
    static var upperBodySensitivity: Float = 1.0

    /// 手臂跟随灵敏度（1.0 = 正常）
    static var armSensitivity: Float = 1.0
}

// MARK: - ModelCalibration

final class ModelCalibration {

    // MARK: - Auto Scale

    /// 根据检测到的人体身高自动计算缩放系数
    /// - Parameter detectedHeight: BodyTracker+SkeletonMapper 估算的人体身高（米）
    /// - Returns: 缩放系数
    static func calculateAutoScale(detectedHeight: Float) -> Float {
        let ratio = detectedHeight / CalibrationConfig.bodyHeight
        // 限制在合理范围，避免极端情况
        let clamped = max(0.5, min(2.0, ratio))
        return CalibrationConfig.modelScale * clamped
    }

    // MARK: - Apply Calibration

    /// 将校准参数应用到模型节点
    /// - Parameter node: 服装模型的根节点
    static func apply(to node: SCNNode, scale: Float? = nil) {
        let s = scale ?? CalibrationConfig.modelScale
        node.simdScale = SIMD3<Float>(repeating: s)
        node.simdPosition = SIMD3<Float>(
            CalibrationConfig.modelOffsetX,
            CalibrationConfig.modelOffsetY,
            CalibrationConfig.modelOffsetZ
        )
    }

    // MARK: - Manual Adjust

    /// 手动调整缩放（用于双指缩放手势）
    static func adjustScale(by multiplier: Float) {
        CalibrationConfig.modelScale *= multiplier
        CalibrationConfig.modelScale = max(0.3, min(3.0, CalibrationConfig.modelScale))
    }

    /// 重置所有参数为默认值
    static func resetCalibration() {
        CalibrationConfig.modelScale = 1.0
        CalibrationConfig.modelOffsetX = 0.0
        CalibrationConfig.modelOffsetY = 0.0
        CalibrationConfig.modelOffsetZ = 0.0
        CalibrationConfig.bodyHeight = 1.7
        CalibrationConfig.occlusionPlaneDistance = 0.8
        CalibrationConfig.upperBodySensitivity = 1.0
        CalibrationConfig.armSensitivity = 1.0
        print("[ModelCalibration] ✅ 校准参数已重置为默认值")
    }

    // MARK: - Print Current State

    static func printCalibration() {
        print("""
        [ModelCalibration] 当前校准参数:
          modelScale: \(CalibrationConfig.modelScale)
          offsetX: \(CalibrationConfig.modelOffsetX)
          offsetY: \(CalibrationConfig.modelOffsetY)
          offsetZ: \(CalibrationConfig.modelOffsetZ)
          bodyHeight: \(CalibrationConfig.bodyHeight)
          occlusionDistance: \(CalibrationConfig.occlusionPlaneDistance)
        """)
    }
}
