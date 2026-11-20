//
//  ImagePipeline.swift
//  Tanuki's Stash
//
//  Shared networking, image decoding and cache management.
//

import SwiftUI
import UIKit
import ImageIO

/// One shared URLSession for the API, images and downloads, backed by a
/// generous HTTP cache. Reusing a single session keeps connections alive and
/// lets thumbnails and API responses survive scrolling and relaunches instead
/// of being fetched again.
enum NetworkSession {
    nonisolated(unsafe) static let urlCache: URLCache = URLCache(
        memoryCapacity: 32 * 1024 * 1024,
        diskCapacity: 256 * 1024 * 1024,
        diskPath: "tanuki-http-cache"
    )

    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        // The app talks to JSON APIs only; cookies add overhead and are never
        // used for authentication (that is the API key).
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()
}

/// A decoded, downsampled image. Marked unchecked Sendable because a CGImage
/// is immutable once created, so it can safely cross an executor boundary.
private struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    var cost: Int { cgImage.bytesPerRow * cgImage.height }
}

/// Bounded in-memory image cache with a downsampling loader.
///
/// Downloads go through `NetworkSession` (so the HTTP disk cache applies),
/// decoding happens once off the main thread at the size the image is actually
/// drawn at, and results are kept in a cost-limited `NSCache`. This avoids
/// decoding multi-megapixel originals for small cells and stops repeat visits
/// from re-downloading or re-decoding anything.
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    /// Requests for the same URL/size share one download instead of racing.
    private var inFlight: [String: (id: UUID, task: Task<DecodedImage?, Never>)] = [:]

    private init() {
        memory.countLimit = 400
        memory.totalCostLimit = 128 * 1024 * 1024
    }

    func cachedImage(for url: URL?, maxPixelSize: CGFloat) -> UIImage? {
        guard let url else { return nil }
        return memory.object(forKey: Self.key(url, maxPixelSize) as NSString)
    }

    @discardableResult
    func image(
        for url: URL?,
        maxPixelSize: CGFloat,
        priority: TaskPriority = .userInitiated
    ) async -> UIImage? {
        guard let url, maxPixelSize > 0 else { return nil }
        let key = Self.key(url, maxPixelSize)
        if let cached = memory.object(forKey: key as NSString) { return cached }

        let entry: (id: UUID, task: Task<DecodedImage?, Never>)
        if let existing = inFlight[key] {
            entry = existing
        } else {
            let id = UUID()
            let task = Task.detached(priority: priority) {
                await Self.download(url: url, maxPixelSize: maxPixelSize)
            }
            entry = (id, task)
            inFlight[key] = entry
        }

        let decoded = await entry.task.value
        if inFlight[key]?.id == entry.id { inFlight[key] = nil }
        guard let decoded else { return nil }

        let image = UIImage(cgImage: decoded.cgImage)
        memory.setObject(image, forKey: key as NSString, cost: decoded.cost)
        return image
    }

    /// Warms the cache for an image the user is likely to open next.
    func prefetch(url: URL?, maxPixelSize: CGFloat) {
        guard let url, maxPixelSize > 0,
              cachedImage(for: url, maxPixelSize: maxPixelSize) == nil else { return }
        let key = Self.key(url, maxPixelSize)
        guard inFlight[key] == nil else { return }

        let id = UUID()
        let task = Task.detached(priority: .utility) {
            await Self.download(url: url, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = (id, task)
        Task { @MainActor [weak self] in
            let decoded = await task.value
            guard let self else { return }
            if self.inFlight[key]?.id == id { self.inFlight[key] = nil }
            if let decoded {
                self.memory.setObject(
                    UIImage(cgImage: decoded.cgImage),
                    forKey: key as NSString,
                    cost: decoded.cost
                )
            }
        }
    }

    func clearMemory() {
        memory.removeAllObjects()
    }

    // MARK: - Loading

    private nonisolated static func key(_ url: URL, _ maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixelSize.rounded()))"
    }

    private nonisolated static func download(url: URL, maxPixelSize: CGFloat) async -> DecodedImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await NetworkSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return downsample(data: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    /// ImageIO shrinks the image while decoding, so only the pixels we need are
    /// ever allocated. This is dramatically cheaper than `UIImage(data:)` plus
    /// letting the view scale a full-resolution image.
    private nonisolated static func downsample(data: Data, maxPixelSize: CGFloat) -> DecodedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return DecodedImage(cgImage: cgImage)
    }
}

/// Small, cached thumbnail for grids and placeholders. Shows a flat color until
/// the image is ready instead of an animating spinner, which keeps scrolling
/// cheap.
struct ThumbnailImage: View {
    var urlString: String?
    var maxPixelSize: CGFloat
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .clipped()
        .task(id: urlString) {
            guard let urlString, let url = URL(string: urlString) else { return }
            image = await ImagePipeline.shared.image(
                for: url,
                maxPixelSize: maxPixelSize,
                priority: .utility
            )
        }
    }
}

/// Sizes and clears the on-disk HTTP cache and temporary files.
enum AppCache {
    static func totalSize() -> Int64 {
        directories.reduce(0) { $0 + size(of: $1) }
    }

    private static var directories: [URL] {
        let fileManager = FileManager.default
        return [
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fileManager.temporaryDirectory
        ].compactMap { $0 }
    }

    private static func size(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    @MainActor
    static func clear() async {
        ImagePipeline.shared.clearMemory()
        NetworkSession.urlCache.removeAllCachedResponses()

        let directories = self.directories
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            for directory in directories {
                guard let contents = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                ) else { continue }
                for url in contents {
                    try? fileManager.removeItem(at: url)
                }
            }
        }.value
    }
}
