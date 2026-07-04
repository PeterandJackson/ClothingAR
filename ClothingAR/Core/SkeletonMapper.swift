import Foundation
import simd
import SceneKit
import Vision

// MARK: - Bone Rotation Output

/// 解算后的骨骼姿态数据
struct SkeletonPose {
    /// 骨骼名 → 旋转四元数的映射
    let rotations: [String: simd_quatf]
    /// 骨骼名 → 3D 世界位置的映射（根骨骼在原点）
    let positions: [String: SIMD3<Float>]
    /// 检测到的人体身高（用于模型缩放参考）
    let estimatedBodyHeight: Float
    /// 时间戳
    let timestamp: CFTimeInterval
}

// MARK: - SkeletonMapper

final class SkeletonMapper {

    // MARK: - Configuration

    /// 目标人体身高（米），默认 1.7m
    var bodyHeight: Float = 1.7

    /// 帧间旋转平滑系数（slerp 因子，0 = 完全用历史，1 = 完全用新值）
    let rotationSmoothing: Float = 0.4

    // MARK: - Vision Joint → Bone Name Mapping

    /// Vision 关节到通用骨骼名的映射
    /// Vision 关节名在人体模型中的对应位置
    let visionJointToBone: [VNHumanBodyPoseObservation.JointName: String] = [
        .root: "hips",
        .neck: "neck",
        .leftShoulder: "left_shoulder",
        .leftElbow: "left_elbow",
        .leftWrist: "left_wrist",
        .rightShoulder: "right_shoulder",
        .rightElbow: "right_elbow",
        .rightWrist: "right_wrist",
        .leftHip: "left_hip",
        .leftKnee: "left_knee",
        .leftAnkle: "left_ankle",
        .rightHip: "right_hip",
        .rightKnee: "right_knee",
        .rightAnkle: "right_ankle",
    ]

    // MARK: - Bone Hierarchy

    /// 骨骼父子层级关系（通用名）
    struct BoneDefinition {
        let name: String       // 通用名
        let parent: String?    // 父骨骼通用名（nil 表示根骨骼）
        let restDirection: SIMD3<Float> // T-Pose 下的默认方向
        let expectedLength: Float // 标准人体骨骼长度（相对于 1.7m 身高），单位米
    }

    /// 骨骼定义表（T-Pose 参考方向）
    let boneDefinitions: [BoneDefinition] = [
        // 躯干
        BoneDefinition(name: "hips",      parent: nil,              restDirection: SIMD3<Float>(0,  1,  0), expectedLength: 0.00),
        BoneDefinition(name: "spine",     parent: "hips",           restDirection: SIMD3<Float>(0,  1,  0), expectedLength: 0.20),
        BoneDefinition(name: "spine1",    parent: "spine",          restDirection: SIMD3<Float>(0,  1,  0), expectedLength: 0.15),
        BoneDefinition(name: "spine2",    parent: "spine1",         restDirection: SIMD3<Float>(0,  1,  0), expectedLength: 0.15),
        BoneDefinition(name: "neck",      parent: "spine2",         restDirection: SIMD3<Float>(0,  1,  0), expectedLength: 0.08),

        // 左臂
        BoneDefinition(name: "left_shoulder", parent: "spine2",    restDirection: SIMD3<Float>(-1,  0,  0), expectedLength: 0.18),
        BoneDefinition(name: "left_elbow",    parent: "left_shoulder", restDirection: SIMD3<Float>(-1,  0,  0), expectedLength: 0.30),
        BoneDefinition(name: "left_wrist",    parent: "left_elbow",    restDirection: SIMD3<Float>(-1,  0,  0), expectedLength: 0.26),

        // 右臂
        BoneDefinition(name: "right_shoulder", parent: "spine2",   restDirection: SIMD3<Float>( 1,  0,  0), expectedLength: 0.18),
        BoneDefinition(name: "right_elbow",    parent: "right_shoulder", restDirection: SIMD3<Float>( 1,  0,  0), expectedLength: 0.30),
        BoneDefinition(name: "right_wrist",    parent: "right_elbow",    restDirection: SIMD3<Float>( 1,  0,  0), expectedLength: 0.26),

        // 左腿
        BoneDefinition(name: "left_hip",    parent: "hips",        restDirection: SIMD3<Float>(-0.1, -1,  0), expectedLength: 0.12),
        BoneDefinition(name: "left_knee",   parent: "left_hip",    restDirection: SIMD3<Float>( 0,  -1,  0), expectedLength: 0.42),
        BoneDefinition(name: "left_ankle",  parent: "left_knee",   restDirection: SIMD3<Float>( 0,  -1,  0), expectedLength: 0.40),

        // 右腿
        BoneDefinition(name: "right_hip",   parent: "hips",        restDirection: SIMD3<Float>( 0.1, -1,  0), expectedLength: 0.12),
        BoneDefinition(name: "right_knee",  parent: "right_hip",   restDirection: SIMD3<Float>( 0,  -1,  0), expectedLength: 0.42),
        BoneDefinition(name: "right_ankle", parent: "right_knee",  restDirection: SIMD3<Float>( 0,  -1,  0), expectedLength: 0.40),
    ]

    // MARK: - Private State

    /// 上一帧的骨骼旋转结果，用于帧间 slerp
    private var previousRotations: [String: simd_quatf] = [:]

    // MARK: - Main Mapping Function

    /// 从 Vision 2D 关节点解算 3D 骨骼姿态
    /// - Parameter bodyData: Vision 检测到的人体关节点（归一化坐标）
    /// - Parameter viewSize: 画面尺寸（用于反归一化）
    /// - Returns: SkeletonPose 或 nil（数据不足无法解算）
    func mapToSkeleton(bodyData: BodyJointData,
                       viewSize: CGSize) -> SkeletonPose? {

        let points = bodyData.points
        let confidences = bodyData.confidences

        // Step 1: 构建 Vision 关节的 3D 位置（深度估算）
        var joint3D: [VNHumanBodyPoseObservation.JointName: SIMD3<Float>] = [:]
        let estimatedHeight = estimateJoint3DPositions(points: points, confidences: confidences,
                                                        viewSize: viewSize,
                                                        outPositions: &joint3D)

        // Step 2: 为每个骨骼计算旋转
        var rotations: [String: simd_quatf] = [:]
        var positions: [String: SIMD3<Float>] = [:]

        for bone in boneDefinitions {
            let targetPosition: SIMD3<Float>
            let visionJoint = reversedVisionJoint(bone.name)

            if let vj = visionJoint, let jp = joint3D[vj] {
                targetPosition = jp
            } else if let parent = bone.parent, let pp = positions[parent] {
                // 关节缺失：用父骨骼位置 + 默认方向 * 默认长度估算
                targetPosition = pp + bone.restDirection * bone.expectedLength
            } else {
                continue
            }

            // 计算父骨骼位置
            let parentPosition: SIMD3<Float>
            if let parent = bone.parent, let pp = positions[parent] {
                parentPosition = pp
            } else {
                parentPosition = SIMD3<Float>(0, 0, 0)
            }

            // 从父骨骼指向目标的方向
            var targetDirection = simd_normalize(targetPosition - parentPosition)

            // 除零保护
            guard simd_length(targetDirection) > 0.001 else {
                rotations[bone.name] = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                positions[bone.name] = targetPosition
                continue
            }

            // 计算从 restDirection 到 targetDirection 的旋转
            let restDir = simd_normalize(bone.restDirection)
            let rotation = rotationFromDirection(from: restDir, to: targetDirection)

            // 帧间平滑
            if let prev = previousRotations[bone.name] {
                rotations[bone.name] = simd_slerp(prev, rotation, rotationSmoothing)
            } else {
                rotations[bone.name] = rotation
            }

            positions[bone.name] = targetPosition
        }

        // 缓存用于下一帧平滑
        previousRotations = rotations

        return SkeletonPose(
            rotations: rotations,
            positions: positions,
            estimatedBodyHeight: estimatedHeight,
            timestamp: bodyData.timestamp
        )
    }

    // MARK: - Depth Estimation

    /// 将 2D 归一化坐标反算为 3D 坐标（含深度）
    private func estimateJoint3DPositions(
        points: [VNHumanBodyPoseObservation.JointName: CGPoint],
        confidences: [VNHumanBodyPoseObservation.JointName: Float],
        viewSize: CGSize,
        outPositions: inout [VNHumanBodyPoseObservation.JointName: SIMD3<Float>]
    ) -> Float {

        // 预设尺度因子：将归一化坐标映射到约 1.7m 的参考世界
        let scaleFactor: Float = Float(viewSize.height) / 2.0

        // 第一遍：X, Y 坐标反归一化，Z 暂设为 0
        var rawPositions: [VNHumanBodyPoseObservation.JointName: SIMD3<Float>] = [:]
        for (joint, point) in points {
            let x = (Float(point.x) - 0.5) * scaleFactor * 2.0
            let y = (Float(point.y) - 0.5) * scaleFactor * 2.0
            rawPositions[joint] = SIMD3<Float>(x, -y, 0) // Y 翻转（屏幕坐标系 → 世界坐标系）
        }

        // 第二遍：基于骨骼长度约束估算 Z 分量
        // 从髋部（root）开始 BFS 传播深度
        guard let rootPos = rawPositions[.root] else {
            return bodyHeight
        }

        var resolvedPositions: [VNHumanBodyPoseObservation.JointName: SIMD3<Float>] = [.root: rootPos]
        var queue: [VNHumanBodyPoseObservation.JointName] = [.root]

        let bonesFromRoot: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName, Float)] = [
            (.root, .leftHip, 0.10),
            (.root, .rightHip, 0.10),
            (.root, .neck, 0.55),
            (.neck, .leftShoulder, 0.18),
            (.neck, .rightShoulder, 0.18),
            (.leftShoulder, .leftElbow, 0.30),
            (.rightShoulder, .rightElbow, 0.30),
            (.leftElbow, .leftWrist, 0.26),
            (.rightElbow, .rightWrist, 0.26),
            (.leftHip, .leftKnee, 0.42),
            (.rightHip, .rightKnee, 0.42),
            (.leftKnee, .leftAnkle, 0.40),
            (.rightKnee, .rightAnkle, 0.40),
        ]

        var visited: Set<VNHumanBodyPoseObservation.JointName> = [.root]

        while !queue.isEmpty {
            let parent = queue.removeFirst()
            guard let parentPos = resolvedPositions[parent] else { continue }

            for (p, child, expectedLen) in bonesFromRoot where p == parent {
                guard !visited.contains(child) else { continue }
                visited.insert(child)

                if let childRaw = rawPositions[child] {
                    // 2D 投影距离
                    let dx = childRaw.x - parentPos.x
                    let dy = childRaw.y - parentPos.y
                    let projected2D = sqrt(dx * dx + dy * dy)

                    // 深度估算：利用勾股定理
                    // expected3D² = projected2D² + dz²
                    var dz: Float = 0
                    if projected2D > 0.001 && projected2D < expectedLen * scaleFactor * 1.2 {
                        let projected3D = projected2D / scaleFactor
                        let delta = expectedLen * expectedLen - projected3D * projected3D
                        if delta > 0 {
                            dz = sqrt(delta) * scaleFactor
                        }
                        // 如果 projected2D 已经很接近 expectedLen → 骨骼在屏幕平面内
                    } else if projected2D >= expectedLen * scaleFactor * 1.2 {
                        dz = 0 // 异常值，忽略深度
                    } else {
                        dz = 0
                    }

                    // Z 方向符号：基于骨骼在身体哪一侧粗略判断
                    // 大多数情况下正面拍摄，Z 近似为 0，这里做最小假设
                    resolvedPositions[child] = SIMD3<Float>(childRaw.x, childRaw.y, dz)
                } else {
                    // 子关节缺失，用默认方向估算
                    resolvedPositions[child] = parentPos + SIMD3<Float>(0, -expectedLen * scaleFactor, 0)
                }

                queue.append(child)
            }
        }

        outPositions = resolvedPositions

        // 估算身高
        if let root = resolvedPositions[.root],
           let neck = resolvedPositions[.neck],
           let leftAnkle = resolvedPositions[.leftAnkle],
           let rightAnkle = resolvedPositions[.rightAnkle] {
            let avgAnkle = (leftAnkle + rightAnkle) / 2.0
            let detectedHeight = simd_distance(root, neck) + simd_distance(root, avgAnkle)
            return detectedHeight / scaleFactor * 1.5
        }

        return bodyHeight
    }

    // MARK: - Rotation Computation

    /// 计算从一个方向向量旋转到另一个方向向量所需的四元数
    private func rotationFromDirection(from: SIMD3<Float>, to: SIMD3<Float>) -> simd_quatf {
        let fromNorm = simd_normalize(from)
        let toNorm = simd_normalize(to)

        let dot = simd_dot(fromNorm, toNorm)

        // 两向量几乎平行
        if dot > 0.9999 {
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        // 两向量几乎反平行
        if dot < -0.9999 {
            // 找任意一个正交轴做 180° 旋转
            let axis = abs(fromNorm.x) < 0.99
                ? simd_normalize(simd_cross(fromNorm, SIMD3<Float>(1, 0, 0)))
                : simd_normalize(simd_cross(fromNorm, SIMD3<Float>(0, 1, 0)))
            return simd_quatf(angle: .pi, axis: axis)
        }

        let axis = simd_normalize(simd_cross(fromNorm, toNorm))
        let angle = acos(dot)
        return simd_quatf(angle: angle, axis: axis)
    }

    // MARK: - Helpers

    /// 从通用骨骼名反查 Vision 关节名
    private func reversedVisionJoint(_ boneName: String) -> VNHumanBodyPoseObservation.JointName? {
        for (joint, name) in visionJointToBone where name == boneName {
            return joint
        }
        return nil
    }

    // MARK: - Reset

    func reset() {
        previousRotations = [:]
    }
}
