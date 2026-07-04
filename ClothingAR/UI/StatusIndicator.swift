import UIKit

final class StatusIndicator: UILabel {

    // MARK: - Status

    enum Status {
        case tracking(fps: Int)
        case lost
        case degraded(fps: Int, reason: String)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        textColor = .white
        font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        textAlignment = .left
        numberOfLines = 1

        // 毛玻璃背景
        backgroundColor = UIColor.black.withAlphaComponent(0.4)
        layer.cornerRadius = 8
        layer.masksToBounds = true

        // 内边距通过调整 frame 或使用 attributed text
        update(status: .tracking(fps: 0))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + 16, height: s.height + 8)
    }

    override func drawText(in rect: CGRect) {
        let insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        super.drawText(in: rect.inset(by: insets))
    }

    // MARK: - Update

    func update(status: Status) {
        switch status {
        case .tracking(let fps):
            text = "● 跟踪中  \(fps) fps"
            textColor = UIColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)

        case .lost:
            text = "○ 跟踪丢失"
            textColor = UIColor.white

        case .degraded(let fps, let reason):
            text = "⚠ 性能降级  \(fps) fps"
            textColor = UIColor.orange
        }
    }
}
