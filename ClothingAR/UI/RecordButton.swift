import UIKit

final class RecordButton: UIButton {

    // MARK: - State

    var isRecording: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    // MARK: - Private

    private let outerRing = CAShapeLayer()
    private let innerCircle = CAShapeLayer()
    private let blinkAnimation = CABasicAnimation(keyPath: "opacity")

    private let buttonSize: CGFloat = 72
    private let outerRadius: CGFloat = 30
    private let innerRadiusNormal: CGFloat = 12
    private let innerRadiusRecording: CGFloat = 20

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
        backgroundColor = .clear
        isUserInteractionEnabled = true

        // ── 外环 ──
        let outerPath = UIBezierPath(arcCenter: CGPoint(x: buttonSize / 2, y: buttonSize / 2),
                                      radius: outerRadius,
                                      startAngle: 0,
                                      endAngle: .pi * 2,
                                      clockwise: true)
        outerRing.path = outerPath.cgPath
        outerRing.fillColor = UIColor.clear.cgColor
        outerRing.strokeColor = UIColor.white.cgColor
        outerRing.lineWidth = 4
        layer.addSublayer(outerRing)

        // ── 内圆 ──
        updateInnerCirclePath(radius: innerRadiusNormal)
        innerCircle.fillColor = UIColor.white.cgColor
        layer.addSublayer(innerCircle)

        // ── 闪烁动画（录制时使用） ──
        blinkAnimation.fromValue = 1.0
        blinkAnimation.toValue = 0.3
        blinkAnimation.duration = 0.6
        blinkAnimation.repeatCount = .infinity
        blinkAnimation.autoreverses = true

        // ── 自带长按重置 ──
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 3.0
        addGestureRecognizer(longPress)
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: buttonSize, height: buttonSize)
    }

    // MARK: - Appearance

    private func updateAppearance() {
        if isRecording {
            // 红点 + 圆角矩形
            updateInnerCirclePath(radius: 8)
            innerCircle.fillColor = UIColor.systemRed.cgColor
            innerCircle.add(blinkAnimation, forKey: "blink")
            outerRing.strokeColor = UIColor.systemRed.withAlphaComponent(0.7).cgColor
        } else {
            // 白色圆
            updateInnerCirclePath(radius: innerRadiusNormal)
            innerCircle.fillColor = UIColor.white.cgColor
            innerCircle.removeAnimation(forKey: "blink")
            outerRing.strokeColor = UIColor.white.cgColor
        }
    }

    private func updateInnerCirclePath(radius: CGFloat) {
        let path = UIBezierPath(arcCenter: CGPoint(x: buttonSize / 2, y: buttonSize / 2),
                                 radius: radius,
                                 startAngle: 0,
                                 endAngle: .pi * 2,
                                 clockwise: true)
        innerCircle.path = path.cgPath
    }

    // MARK: - Long Press → Reset Calibration

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        ModelCalibration.resetCalibration()
        // 给用户一个震动反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        print("[RecordButton] 长按 3 秒 → 校准已重置")
    }

    // MARK: - Highlight

    override var isHighlighted: Bool {
        didSet {
            let scale: CGFloat = isHighlighted ? 0.9 : 1.0
            UIView.animate(withDuration: 0.15) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }
}
