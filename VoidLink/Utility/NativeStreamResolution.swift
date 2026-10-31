import Foundation
import CoreGraphics

/// Display/window pixel measurements are not necessarily valid 4:2:0 encoder
/// dimensions. Apply only to native presets, never to explicit custom sizes.
@objc
final class NativeStreamResolution: NSObject {
    @objc(alignedSize:)
    static func alignedSize(_ size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 2, size.height >= 2,
              size.width <= CGFloat(Int32.max), size.height <= CGFloat(Int32.max) else {
            return .zero
        }
        return CGSize(width: floor(size.width / 2) * 2,
                      height: floor(size.height / 2) * 2)
    }
}
