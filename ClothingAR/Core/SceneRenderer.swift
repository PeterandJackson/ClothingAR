import SceneKit
import CoreGraphics
import UIKit

// MARK: - SceneRenderer

final class SceneRenderer: NSObject {

    // MARK: - Public Properties

    let scene: SCNScene
    let scnView: SCNView
    let cameraNode: SCNNode

    /// 服装模型的根节点（加载后注入）
    var clothingRootNode: SCNNode? {
        didSet {
            if let node = clothingRootNode {
                clothingNodeHolder.addChildNode(node)
            }
        }
    }

    /// 骨骼名 → 模型实际骨骼节点 的映射（加载后配置）
    var boneNodeMap: [String: SCNNode] = [:]

    // MARK: - Private

    private let clothingNodeHolder = SCNNode()
    private let occlusionPlane: SCNNode
    private let occlusionMaterial: SCNMaterial

    /// 双缓冲：避免相机帧撕裂
    private let frameLock = NSLock()
    private var pendingBackgroundImage: CGImage?
    private var currentBackgroundImage: CGImage?

    /// 最新解算出的骨骼旋转
    private let boneRotationLock = NSLock()
    private var pendingBoneRotations: [String: simd_quatf] = [:]

    /// 遮罩纹理
    private let maskLock = NSLock()
    private var pendingMaskImage: CGImage?

    // MARK: - Init

    override init() {
        scene = SCNScene()

        // ── SCNView ──
        scnView = SCNView(frame: .zero)
        scnView.scene = scene
        scnView.backgroundColor = .black
        scnView.preferredFramesPerSecond = 30
        scnView.antialiasingMode = .none  // iPhone X 性能优化，不开抗锯齿
        scnView.allowsCameraControl = false
        scnView.showsStatistics = false   // 发布时关掉 FPS 统计

        // ── Camera ──
        cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.01
        camera.zFar = 100
        cameraNode.camera = camera
        // 放在原点前方，3D 物体在原点附近——面向 Z 轴正方向（模型前置朝向）
        cameraNode.position = SCNVector3(0, 0, 1.5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        // ── 环境光 ──
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor.white
        ambientLight.light!.intensity = 800
        scene.rootNode.addChildNode(ambientLight)

        // ── 方向光（模拟主光源） ──
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light!.type = .directional
        directionalLight.light!.color = UIColor.white
        directionalLight.light!.intensity = 400
        directionalLight.position = SCNVector3(0, 5, 10)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)

        // ── 遮挡平面 ──
        occlusionPlane = SCNNode()
        let planeGeo = SCNPlane(width: 2.0, height: 3.0)
        occlusionMaterial = SCNMaterial()
        occlusionMaterial.diffuse.contents = UIColor.clear
        occlusionMaterial.writesToDepthBuffer = true
        occlusionMaterial.colorBufferWriteMask = []  // 只写深度，不写颜色
        occlusionMaterial.isDoubleSided = true
        planeGeo.materials = [occlusionMaterial]
        occlusionPlane.geometry = planeGeo
        occlusionPlane.position = SCNVector3(0, 0, CalibrationConfig.occlusionPlaneDistance)
        occlusionPlane.renderingOrder = -1  // 最先渲染，写入深度缓冲
        scene.rootNode.addChildNode(occlusionPlane)

        // ── 服装模型容器 ──
        clothingNodeHolder.position = SCNVector3(0, 0, 0)
        clothingNodeHolder.renderingOrder = 1
        scene.rootNode.addChildNode(clothingNodeHolder)

        super.init()
    }

    // MARK: - Background Update (线程安全)

    /// 更新背景画面（从任意线程调用安全）
    func updateBackground(with image: CGImage) {
        frameLock.lock()
        pendingBackgroundImage = image
        frameLock.unlock()
    }

    /// 更新骨骼旋转数据（从任意线程调用安全）
    func updateBoneRotations(_ rotations: [String: simd_quatf]) {
        boneRotationLock.lock()
        pendingBoneRotations = rotations
        boneRotationLock.unlock()
    }

    /// 更新遮罩纹理（从任意线程调用安全）
    func updateSegmentationMask(_ maskImage: CGImage) {
        maskLock.lock()
        pendingMaskImage = maskImage
        maskLock.unlock()
    }

    // MARK: - Per-Frame Update (在主线程 renderer delegate 中调用)

    /// 每帧同步：应用缓冲区数据到 SceneKit
    /// 必须在主线程调用
    func applyPendingUpdates() {
        // ── 背景画面 ──
        frameLock.lock()
        if let bg = pendingBackgroundImage {
            // 先清空旧内容，避免内存泄漏
            scene.background.contents = nil
            scene.background.contents = bg
            // 同时用于环境光近似
            scene.lightingEnvironment.contents = bg
            scene.lightingEnvironment.intensity = 1.5
            currentBackgroundImage = bg
            pendingBackgroundImage = nil
        }
        frameLock.unlock()

        // ── 骨骼旋转 ──
        boneRotationLock.lock()
        let rotations = pendingBoneRotations
        boneRotationLock.unlock()

        if !rotations.isEmpty {
            applyBoneRotations(rotations)
        }

        // ── 遮罩纹理 ──
        maskLock.lock()
        if let mask = pendingMaskImage {
            updateOcclusionPlane(with: mask)
            pendingMaskImage = nil
        }
        maskLock.unlock()
    }

    // MARK: - Bone Rotation Application

    private func applyBoneRotations(_ rotations: [String: simd_quatf]) {
        for (boneName, rotation) in rotations {
            guard let boneNode = boneNodeMap[boneName] else { continue }
            boneNode.simdOrientation = rotation
        }
    }

    // MARK: - Occlusion Plane

    private func updateOcclusionPlane(with maskImage: CGImage) {
        // 将遮罩作为透明度通道
        let uiImage = UIImage(cgImage: maskImage)

        // 使用遮罩作为 diffuse 纹理的 alpha 通道
        occlusionMaterial.transparent.contents = uiImage
        occlusionMaterial.transparencyMode = .rgbZero

        // 更新遮挡平面距离
        occlusionPlane.position.z = CalibrationConfig.occlusionPlaneDistance
    }

    // MARK: - Lighting Adaption

    /// 根据相机画面亮度自动调整环境光
    func adaptLighting(to image: CGImage) {
        // 降采样到 16×16 计算平均亮度
        guard let avgBrightness = computeAverageBrightness(image) else { return }

        // 映射到 500-2000 lux 范围
        let intensity = 500 + avgBrightness * 1500
        scene.lightingEnvironment.intensity = CGFloat(intensity)

        // 同时调节环境光颜色
        let warm = UIColor(white: CGFloat(avgBrightness), alpha: 1)
        scene.rootNode.childNodes.first?.light?.color = warm
    }

    private func computeAverageBrightness(_ image: CGImage) -> Float? {
        // 简化方案：取中心像素区域亮度
        guard let data = image.dataProvider?.data else { return nil }
        let ptr = CFDataGetBytePtr(data)
        let width = image.width
        let height = image.height

        // 采样中心 10×10 区域
        let cx = width / 2, cy = height / 2
        let sampleSize = 10
        var totalBrightness: Float = 0
        var count: Float = 0

        for y in max(0, cy - sampleSize)..<min(height, cy + sampleSize) {
            for x in max(0, cx - sampleSize)..<min(width, cx + sampleSize) {
                let offset = (y * image.bytesPerRow + x * 4)
                let r = Float(ptr?[offset] ?? 128) / 255.0
                let g = Float(ptr?[offset + 1] ?? 128) / 255.0
                let b = Float(ptr?[offset + 2] ?? 128) / 255.0
                totalBrightness += (r * 0.299 + g * 0.587 + b * 0.114)
                count += 1
            }
        }

        return count > 0 ? totalBrightness / count : nil
    }

    // MARK: - Pause / Resume

    func pause() {
        scnView.isPlaying = false
        scene.isPaused = true
    }

    func resume() {
        scene.isPaused = false
        scnView.isPlaying = true
    }

    // MARK: - Cleanup

    func cleanup() {
        scene.background.contents = nil
        scene.lightingEnvironment.contents = nil
        occlusionMaterial.transparent.contents = nil
        currentBackgroundImage = nil
        pendingBackgroundImage = nil
        pendingMaskImage = nil
        pendingBoneRotations = [:]
    }
}
