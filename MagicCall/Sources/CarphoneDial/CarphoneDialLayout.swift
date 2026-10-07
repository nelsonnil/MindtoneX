import UIKit

extension UIView {
    func carphoneDialPinEdges(to other: UIView) {
        makeConstraints(
            top: other.topAnchor,
            left: other.leadingAnchor,
            right: other.trailingAnchor,
            bottom: other.bottomAnchor,
            topMargin: 0,
            leftMargin: 0,
            rightMargin: 0,
            bottomMargin: 0,
            width: 0,
            height: 0
        )
    }

    /// Same helper as CarphoneCALL `Extensions.swift` (used by `PerformanceController` for the dial).
    func makeConstraints(
        top: NSLayoutYAxisAnchor?,
        left: NSLayoutXAxisAnchor?,
        right: NSLayoutXAxisAnchor?,
        bottom: NSLayoutYAxisAnchor?,
        topMargin: CGFloat,
        leftMargin: CGFloat,
        rightMargin: CGFloat,
        bottomMargin: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        if let top {
            topAnchor.constraint(equalTo: top, constant: topMargin).isActive = true
        }
        if let left {
            leftAnchor.constraint(equalTo: left, constant: leftMargin).isActive = true
        }
        if let right {
            rightAnchor.constraint(equalTo: right, constant: -rightMargin).isActive = true
        }
        if let bottom {
            bottomAnchor.constraint(equalTo: bottom, constant: -bottomMargin).isActive = true
        }
        if width != 0 {
            widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        if height != 0 {
            heightAnchor.constraint(equalToConstant: height).isActive = true
        }
    }
}
