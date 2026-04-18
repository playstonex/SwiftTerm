//
//  SelectionHandleView.swift
//  SwiftTerm
//
//  Draggable handle view for adjusting terminal text selection on iOS.
//

#if os(iOS) || os(visionOS)
import UIKit

/// A single draggable selection handle rendered as a vertical line with a circle.
/// Positioned at the start or end of a text selection range.
final class SelectionHandleView: UIView {
    enum HandleRole {
        case start
        case end
    }

    let role: HandleRole
    var onDrag: ((CGPoint) -> Void)?

    private let handleDiameter: CGFloat = 10
    private let lineWidth: CGFloat = 1.5
    private let lineLength: CGFloat = 20

    init(role: HandleRole) {
        self.role = role
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: handleDiameter + 4, height: handleDiameter + lineLength)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let color: UIColor = tintColor ?? .systemBlue

        // Circle at the handle point
        let circleCenter: CGPoint
        let lineStart: CGPoint
        let lineEnd: CGPoint

        let cx = bounds.midX
        if role == .start {
            // Circle at bottom, line goes up
            circleCenter = CGPoint(x: cx, y: bounds.maxY - handleDiameter / 2)
            lineStart = CGPoint(x: cx, y: circleCenter.y - handleDiameter / 2)
            lineEnd = CGPoint(x: cx, y: circleCenter.y - handleDiameter / 2 - lineLength)
        } else {
            // Circle at top, line goes down
            circleCenter = CGPoint(x: cx, y: handleDiameter / 2)
            lineStart = CGPoint(x: cx, y: circleCenter.y + handleDiameter / 2)
            lineEnd = CGPoint(x: cx, y: circleCenter.y + handleDiameter / 2 + lineLength)
        }

        // Draw line
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.move(to: lineStart)
        ctx.addLine(to: lineEnd)
        ctx.strokePath()

        // Draw circle
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: circleCenter.x - handleDiameter / 2,
            y: circleCenter.y - handleDiameter / 2,
            width: handleDiameter,
            height: handleDiameter
        ))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Enlarge touch target
        let margin: CGFloat = 14
        return bounds.insetBy(dx: -margin, dy: -margin).contains(point)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let location = gesture.location(in: superview)
        onDrag?(location)

        if gesture.state == .ended || gesture.state == .cancelled {
            // Snap handle to final position
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectionHandleView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}
#endif
