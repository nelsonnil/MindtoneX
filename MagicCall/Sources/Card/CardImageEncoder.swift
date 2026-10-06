import CoreImage
import UIKit
import VideoToolbox

enum CardImageEncoder {
    static func jpegData(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.74) -> Data? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
}
