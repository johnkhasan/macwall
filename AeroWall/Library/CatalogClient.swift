import AppKit
import ImageIO

/// One entry of the macwall.app catalog. Only the fields AeroWall uses are decoded;
/// the API is undocumented, so everything not essential is optional.
struct CatalogWallpaper: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let videoKey: String
    /// Re-encoded 1280 px preview without audio. Good for streaming previews, not for the desktop.
    let videoUrl: URL
    let thumbUrl: URL
    let isPro: Bool?
    let likeCount: Int?

    var fileExtension: String {
        let ext = (videoKey as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext) ? ext : "mp4"
    }

    /// Community uploads that are not moderated yet live under this prefix.
    var isPending: Bool { videoKey.hasPrefix("community-pending/") }
}

struct CatalogPage: Decodable {
    let wallpapers: [CatalogWallpaper]
    let total: Int?
    let hasMore: Bool
}

enum CatalogCategory: String, CaseIterable, Identifiable {
    case anime = "Anime", cars = "Cars", nature = "Nature", heroes = "Heroes", dark = "Dark",
         gaming = "Gaming", space = "Space", abstract = "Abstract", others = "Others"

    var id: String { rawValue }
}

enum CatalogSort: String, CaseIterable, Identifiable {
    case popular, newest

    var id: String { rawValue }
    var title: String { self == .popular ? "Popular" : "Newest" }
}

/// Client for the public macwall.app wallpaper catalog and its CDN.
enum CatalogClient {
    enum CatalogError: LocalizedError {
        case unavailable
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .unavailable: return "The wallpaper catalog is unavailable right now."
            case .http(let status): return "The server answered with HTTP \(status)."
            }
        }
    }

    static let endpoint = URL(string: "https://macwall.app/api/wallpapers")!
    static let cdn = URL(string: "https://cdn.macwall.app")!
    /// The server caps `limit` at 60.
    static let pageSize = 60

    /// Shared session with a disk cache, so catalog pages and thumbnails also show offline.
    static let session: URLSession = {
        let support = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 32 << 20,
            diskCapacity: 300 << 20,
            directory: support.appendingPathComponent("AeroWall/Catalog", isDirectory: true)
        )
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    /// Downloads skip the cache: videos are large and land in the library anyway.
    static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "AeroWall/\(version) (macOS)"
    }()

    static func fetchPage(
        _ page: Int,
        category: CatalogCategory?,
        query: String,
        sort: CatalogSort
    ) async throws -> CatalogPage {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "sort", value: sort.rawValue),
        ]
        // Category is case-sensitive; the search parameter is `q`.
        if let category { items.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        do {
            data = try await load(request)
        } catch let error as URLError where error.code != .cancelled {
            // Offline: fall back to whatever page was cached last time.
            request.cachePolicy = .returnCacheDataDontLoad
            data = try await load(request)
        }
        guard let page = try? JSONDecoder().decode(CatalogPage.self, from: data) else {
            throw CatalogError.unavailable
        }
        return CatalogPage(
            wallpapers: page.wallpapers.filter { $0.isPro != true && !$0.isPending },
            total: page.total,
            hasMore: page.hasMore
        )
    }

    /// Candidate download URLs, sharpest first: the original upload, then the 1280 px preview.
    static func sourceURLs(for wallpaper: CatalogWallpaper) -> [URL] {
        [cdn.appendingPathComponent(wallpaper.videoKey), wallpaper.videoUrl]
    }

    private static func load(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CatalogError.http(status) }
        return data
    }

    // MARK: Thumbnails

    // NSCache is thread-safe, so the grid (main) and the decode task (background) share it directly.
    private static let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    /// Fetches a thumbnail and decodes it downsampled off the main thread. Full-size JPEGs decoded
    /// on the main thread during a scroll starve the desktop wallpaper player and make it stutter;
    /// a small, already-decoded bitmap draws almost for free.
    static func image(at url: URL, maxPixel: CGFloat = 700) async -> NSImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let data = try? await load(URLRequest(url: url)),
              let image = await decodeDownsampled(data, maxPixel: maxPixel) else { return nil }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    private static func decodeDownsampled(_ data: Data, maxPixel: CGFloat) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,          // decode now, on this background thread
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
