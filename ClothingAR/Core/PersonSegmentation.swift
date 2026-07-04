import Vision
import CoreImage
import CoreGraphics

// MARK: - PersonSegmentationDelegate

protocol PersonSegmentationDelegate: AnyObject {
    func personSegmentation(_ segmentation: PersonSegmentation,
                            didProduceMask maskImage: CGImage)
}

// MARK: - PersonSegmentation

final class PersonSegmentation {

    weak var delegate: PersonSegmentationDelegate?

    // MARK: - Configuration

    /// 遮罩分辨率
    var maskWidth: Int = 320
    var maskHeight: Int = 240

    // MARK: - Private

    private let request = VNGeneratePersonSegmentationRequest()
    private let queue = DispatchQueue(label: "com.clothingar.segmentation", qos: .userInitiated)

    /// 降频计数器（外部每帧+1，满足间隔才执行）
    private var frameCounter: Int = 0
    var framesBetweenSegmentation: Int = 3  // 由 QualityManager 动态调整

    /// 上一帧的遮罩缓存（降频时复用）
    private var cachedMask: CGImage?

    // MARK: - Process Frame

    func processFrameIfNeeded(_ pixelBuffer: CVPixelBuffer) {
        frameCounter += 1
        guard frameCounter >= framesBetweenSegmentation else { return }
        frameCounter = 0

        // 异步执行，不阻塞调用线程
        let localPixelBuffer = pixelBuffer // 持有引用
        queue.async { [weak self] in
            self?.performSegmentation(localPixelBuffer)
        }
    }

    private func performSegmentation(_ pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return // 静默跳过错误
        }

        guard let maskPixelBuffer = request.results?.first?.pixelBuffer else {
            return
        }

        // ── 转为 CGImage ──
        guard let maskCGImage = pixelBufferToCGImage(maskPixelBuffer) else {
            return
        }

        cachedMask = maskCGImage

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.personSegmentation(self, didProduceMask: maskCGImage)
        }
    }

    // MARK: - Convert

    /// CVPixelBuffer (单通道 Float32) → CGImage (Alpha 灰度)
    private func pixelBufferToCGImage(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // 翻转 Y 轴：CVPixelBuffer 原点在左下，SceneKit 纹理原点在左上
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: ciImage.extent.height))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(flipped, from: flipped.extent)
    }

    // MARK: - Cached Mask

    func getCachedMask() -> CGImage? {
        return cachedMask
    }

    // MARK: - Reset

    func reset() {
        frameCounter = 0
        cachedMask = nil
    }
}
