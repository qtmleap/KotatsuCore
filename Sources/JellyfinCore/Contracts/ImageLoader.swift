import Foundation
import CoreGraphics

public protocol ImageLoader: Sendable {
    func loadImageData(from url: URL, targetPixelSize: CGSize) async throws -> Data
}
