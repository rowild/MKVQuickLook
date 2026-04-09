import CoreGraphics

enum VideoLayout {
    static func fittedRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.midX.isFinite,
              bounds.midY.isFinite,
              contentSize.width.isFinite,
              contentSize.height.isFinite,
              bounds.width > 0,
              bounds.height > 0,
              contentSize.width > 0,
              contentSize.height > 0 else {
            return bounds
        }

        let widthRatio = bounds.width / contentSize.width
        let heightRatio = bounds.height / contentSize.height
        let scale = min(widthRatio, heightRatio)
        guard scale.isFinite, scale > 0 else {
            return bounds
        }
        let fittedSize = CGSize(width: floor(contentSize.width * scale),
                                height: floor(contentSize.height * scale))
        let origin = CGPoint(x: bounds.midX - fittedSize.width / 2,
                             y: bounds.midY - fittedSize.height / 2)
        return CGRect(origin: origin, size: fittedSize)
    }
}
