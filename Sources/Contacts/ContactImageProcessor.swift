import CoreGraphics
import Core
import Foundation
import ImageIO

public struct ProcessedContactImage: Equatable, Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let wasCompressed: Bool

    public init(data: Data, width: Int, height: Int, wasCompressed: Bool) {
        self.data = data
        self.width = width
        self.height = height
        self.wasCompressed = wasCompressed
    }
}

public struct ContactImageProcessor: Sendable {
    public static let maxInputBytes = 10 * 1024 * 1024
    public static let maxDimension = 1024
    public static let maxOutputBytes = 200 * 1024

    public init() {}

    public func process(_ input: Data) throws -> ProcessedContactImage {
        guard input.count <= Self.maxInputBytes else {
            throw ContactsError.invalidInput("image input exceeds 10 MB")
        }
        guard let source = CGImageSourceCreateWithData(input as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ContactsError.invalidInput("image cannot be decoded")
        }

        let hasAlpha = image.alphaInfo == .first || image.alphaInfo == .last || image.alphaInfo == .premultipliedFirst || image.alphaInfo == .premultipliedLast
        var dimension = min(Self.maxDimension, max(image.width, image.height))
        while dimension >= 1 {
            guard let resized = makeThumbnail(source: source, maxDimension: dimension) else {
                throw ContactsError.invalidInput("image cannot be resized")
            }
            if hasAlpha {
                if let data = encodePNG(resized), data.count <= Self.maxOutputBytes {
                    return ProcessedContactImage(data: data, width: resized.width, height: resized.height, wasCompressed: data != input)
                }
            } else {
                for quality in stride(from: 0.9, through: 0.1, by: -0.1) {
                    if let data = encodeJPEG(resized, quality: quality), data.count <= Self.maxOutputBytes {
                        return ProcessedContactImage(data: data, width: resized.width, height: resized.height, wasCompressed: data != input)
                    }
                }
            }
            if dimension <= 256 { break }
            dimension = max(256, dimension * 3 / 4)
        }
        throw ContactsError.invalidInput("image cannot be compressed below 200 KB")
    }

    private func makeThumbnail(source: CGImageSource, maxDimension: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }

    private func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
