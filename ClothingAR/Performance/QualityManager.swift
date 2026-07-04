import UIKit

// MARK: - QualityLevel

enum QualityLevel: String {
    case normal    = "正常"
    case warning   = "降级-轻度"
    case degraded  = "降级-中度"
    case critical  = "降级-严重"
}

// MARK: - QualityManagerDelegate

protocol QualityManagerDelegate: AnyObject {
    func qualityManager(_ manager: QualityManager, didChangeTo level: QualityLevel)
    /// 要求 PersonSegmentation 调整降频间隔
    func qualityManager(_ manager: QualityManager, didChangeSegmentationInterval frames: Int)
}

// MARK: - QualityManager

final class QualityManager {

    weak var delegate: QualityManagerDelegate?

    // MARK: - Configuration

    /// FPS 阈值（滞后区间）
    private let degradeThreshold: Int = 25    // 低于此值触发降级
    private let restoreThreshold: Int = 28    // 高于此值且持续 3 秒恢复
    private let criticalThreshold: Int = 20

    /// 进入 warning 状态的持续确认时间（秒）
    private let confirmDuration: TimeInterval = 2.0
    /// 恢复确认时间（秒）
    private let restoreDuration: TimeInterval = 3.0

    // MARK: - State

    private(set) var currentLevel: QualityLevel = .normal

    private var lowFpsStartTime: TimeInterval?
    private var normalFpsStartTime: TimeInterval?

    private var currentSegmentationInterval = 3

    // MARK: - FPS Update

    func updateFPS(_ fps: Int, timestamp: TimeInterval) {
        // ── 降级逻辑 ──
        if fps < degradeThreshold {
            if lowFpsStartTime == nil {
                lowFpsStartTime = timestamp
            }
            normalFpsStartTime = nil

            let duration = timestamp - lowFpsStartTime!

            if duration > confirmDuration && fps < criticalThreshold {
                transitionTo(.critical)
            } else if duration > confirmDuration {
                transitionTo(.degraded)
            } else if duration > confirmDuration / 2 {
                transitionTo(.warning)
            }
        }
        // ── 恢复逻辑 ──
        else if fps >= restoreThreshold && currentLevel != .normal {
            if normalFpsStartTime == nil {
                normalFpsStartTime = timestamp
            }
            lowFpsStartTime = nil

            if timestamp - normalFpsStartTime! > restoreDuration {
                transitionTo(.normal)
            }
        }
        // ── 正常范围 ──
        else {
            lowFpsStartTime = nil
            normalFpsStartTime = nil
        }
    }

    // MARK: - Memory Warning

    func didReceiveMemoryWarning() {
        // 内存告警直接降到 critical
        transitionTo(.critical)
        currentSegmentationInterval = 30
        delegate?.qualityManager(self, didChangeSegmentationInterval: currentSegmentationInterval)
    }

    // MARK: - Transitions

    private func transitionTo(_ level: QualityLevel) {
        guard level != currentLevel else { return }
        let oldLevel = currentLevel
        currentLevel = level

        print("[QualityManager] 质量级别变更: \(oldLevel.rawValue) → \(level.rawValue)")

        switch level {
        case .normal:
            currentSegmentationInterval = 3
        case .warning:
            currentSegmentationInterval = 5
        case .degraded:
            currentSegmentationInterval = 10
        case .critical:
            currentSegmentationInterval = 30
        }

        delegate?.qualityManager(self, didChangeTo: level)
        delegate?.qualityManager(self, didChangeSegmentationInterval: currentSegmentationInterval)
    }

    // MARK: - Thermal State

    func checkThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .serious:
            transitionTo(.degraded)
        case .critical:
            transitionTo(.critical)
        default:
            break
        }
    }

    // MARK: - Reset

    func reset() {
        currentLevel = .normal
        lowFpsStartTime = nil
        normalFpsStartTime = nil
        currentSegmentationInterval = 3
    }
}
