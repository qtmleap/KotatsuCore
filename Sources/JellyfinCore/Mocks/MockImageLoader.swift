import Foundation
import CoreGraphics

public struct MockImageLoader: ImageLoader {
    public init() {}

    public func loadImageData(from url: URL, targetPixelSize: CGSize) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
