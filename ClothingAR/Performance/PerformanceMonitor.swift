import UIKit

// MARK: - PerformanceMonitorDelegate

protocol PerformanceMonitorDelegate: AnyObject {
    func performanceMonitor(_ monitor: PerformanceMonitor, didUpdateFPS fps: Int)
}

// MARK: - PerformanceMonitor

final class PerformanceMonitor {

    weak var delegate: PerformanceMonitorDelegate?

    // MARK: - Private

    private var displayLink: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private let maxSamples = 60  // 滚动 60 帧窗口
    private var lastReportTime: CFTimeInterval = 0

    // MARK: - Start / Stop

    func start() {
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        displayLink?.preferredFramesPerSecond = 0  // 跟随屏幕刷新率
        displayLink?.add(to: .main, forMode: .common)
        frameTimestamps = []
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        frameTimestamps = []
    }

    // MARK: - Frame Tick

    @objc private func frameTick(_ link: CADisplayLink) {
        let now = link.timestamp
        frameTimestamps.append(now)

        // 只保留最近 N 帧
        while frameTimestamps.count > maxSamples {
            frameTimestamps.removeFirst()
        }

        // 每秒计算一次 FPS
        guard now - lastReportTime > 1.0 else { return }
        lastReportTime = now

        let fps = calculateFPS()
        delegate?.performanceMonitor(self, didUpdateFPS: fps)
    }

    // MARK: - Calculate

    private func calculateFPS() -> Int {
        guard frameTimestamps.count >= 2 else { return 0 }

        // 取最后 60 帧窗口的帧率
        let window = Array(frameTimestamps.suffix(60))
        guard window.count >= 2 else { return 0 }

        let duration = window.last! - window.first!
        guard duration > 0 else { return 0 }

        let fps = Double(window.count - 1) / duration
        return Int(round(fps))
    }

    // MARK: - Invalidate

    deinit {
        stop()
    }
}
