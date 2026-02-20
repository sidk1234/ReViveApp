import UIKit

extension UIImage {
    func resizedIfNeeded(maxDimension: CGFloat) -> UIImage {
        guard maxDimension > 0 else { return self }
        let width = size.width
        let height = size.height
        let longest = max(width, height)
        guard longest > maxDimension else { return self }

        let scale = maxDimension / longest
        let targetSize = CGSize(width: width * scale, height: height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func compressedJPEGData(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let clampedQuality = min(max(quality, 0.05), 1.0)
        let resized = resizedIfNeeded(maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: clampedQuality)
    }

    func compressedJPEGDataURL(maxDimension: CGFloat, quality: CGFloat) -> String? {
        guard let data = compressedJPEGData(maxDimension: maxDimension, quality: quality) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
