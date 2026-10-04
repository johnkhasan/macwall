# Using MacWall's Wallpaper Catalog & CDN in a Swift (macOS) Live Wallpaper App

> Purpose: implementation guide for Claude Code. The owner has permission to use these videos in his own app. Everything under "Verified" was observed directly on macwall.app on 2026-10-05; everything under "Unverified" must be checked by running the commands in section 7 before relying on it.

---

## 1. What was discovered

### Verified

- The site `https://macwall.app` exposes a public JSON endpoint: **`GET https://macwall.app/api/wallpapers`** (HTTP 200, `application/json`, `Cache-Control: public`, no auth/cookies needed from the browser).
- Videos and thumbnails are served from **`https://cdn.macwall.app`** (Cloudflare).
- Total catalog at time of inspection: **829 wallpapers**, all unique ids, none flagged `isPro`.
- Categories (exact, case-sensitive): `Anime` (249), `Cars` (142), `Others` (138), `Nature` (83), `Heroes` (63), `Dark` (57), `Gaming` (50), `Space` (32), `Abstract` (15).
- Video containers: 791 `.mp4`, 38 `.mov`.
- `fileSizeBytes`, `durationSeconds`, `resolution`, `tags` are present in the schema but **empty/0 for every item**. Do not depend on them; read real metadata from the file (AVAsset) after download.

### Query parameters of `/api/wallpapers`

| Param | Behavior (verified) |
|---|---|
| `page` | 1-based page number |
| `limit` | default 24, **hard cap 60** (asking for 500 returns 60) |
| `category` | exact, case-sensitive: `category=Anime` works, `category=cars` returns 0 |
| `q` | text search (`q=goku` → 19 results). `search=` is ignored |
| `sort` | `popular` and `newest` both change ordering (`popular` orders by `likeCount`, `newest` by `createdAt` desc) |
| `offset` | ignored, use `page` |

There is no per-item endpoint (`/api/wallpapers/{id}` returns the 404 HTML page) and no `/api/categories`.

### Response shape

```json
{
  "wallpapers": [
    {
      "id": "ichigo-kurosaki-purple-aura",
      "name": "Ichigo Kurosaki Purple Aura",
      "category": "Anime",
      "tags": [],
      "resolution": "",
      "durationSeconds": 0,
      "fileSizeBytes": 0,
      "videoKey": "videos/ichigo-kurosaki-purple-aura.mp4",
      "thumbKey": "thumbs/ichigo-kurosaki-purple-aura.jpg",
      "videoUrl": "https://cdn.macwall.app/cdn-cgi/media/mode=video,width=1280,fit=scale-down,audio=false/videos/ichigo-kurosaki-purple-aura.mp4",
      "thumbUrl": "https://cdn.macwall.app/thumbs/ichigo-kurosaki-purple-aura.jpg",
      "isPro": false,
      "isFeatured": false,
      "isCuratedPick": false,
      "likeCount": 8,
      "createdAt": "2026-10-03T07:41:04.767+00:00"
    }
  ],
  "total": 829,
  "page": 1,
  "limit": 24,
  "hasMore": true
}
```

Notes:

- `id` is either a slug (`ichigo-kurosaki-purple-aura`) or a UUID. Treat it as an opaque string.
- `videoKey` is the object path in the CDN bucket. Most start with `videos/`; some community uploads use `community-pending/<uuid>/video.mp4`. The `community-pending/` prefix suggests items not yet moderated. **Recommended: filter them out** unless you want them.
- `videoUrl` is **not the original file**. It goes through Cloudflare Media Transformations (`/cdn-cgi/media/mode=video,width=1280,fit=scale-down,audio=false/<videoKey>`): a re-encoded copy, max width 1280 px, audio removed. It is what the website previews use.
- `thumbUrl` is a plain JPEG on the CDN (fine for grid thumbnails). The website additionally resizes thumbnails via `/cdn-cgi/image/width=1280,quality=75,format=auto,fit=scale-down,onerror=redirect/<thumbKey>`.

### Unverified (could not be tested from the inspection environment)

- That the **original** file is directly downloadable at `https://cdn.macwall.app/<videoKey>` (e.g. `https://cdn.macwall.app/videos/ichigo-kurosaki-purple-aura.mp4`). Browser `<video>` probes from another origin failed, and the sandbox could not reach the CDN, so neither the original URL nor higher-width transform URLs (`width=3840`) were confirmed.
- Whether the CDN sends `Accept-Ranges`/`Content-Length` (needed for resume and progress).
- Whether the CDN rejects requests without a browser-like `Referer`/`User-Agent` (hotlink protection).
- Original resolution/codec (probably H.264 or HEVC, 1080p–4K).

The user wants the **sharpest quality**, so the download strategy below tries the original first and falls back to the transformed URL.

---

## 2. Quality / URL resolution strategy

Implement a `VideoSource` resolver that returns an ordered list of candidate URLs and uses the first that responds successfully to a `HEAD` (or ranged `GET`, bytes=0-0):

1. **Original:** `https://cdn.macwall.app/\(videoKey)`
2. **Large transform (fallback):** `https://cdn.macwall.app/cdn-cgi/media/mode=video,width=3840,fit=scale-down,audio=false/\(videoKey)`
3. **API default (always known to work in the browser):** `videoUrl` from the API (1280 px wide).

Keep the chosen URL in the stored metadata so it can be re-downloaded identically. Make the order configurable (`preferredQuality: .original | .max4K | .web1280`).

> The Cloudflare transform URL accepts options such as `width`, `height`, `fit`, `audio`, `time`, `duration`. Do not assume anything beyond `width`/`fit`/`audio`, which are the ones the site itself uses.

---

## 3. Architecture

```
MacWallCatalogClient   (async API: list, search, category, pagination)
        │
CatalogStore           (in-memory + on-disk JSON cache of the catalog, ETag-aware)
        │
WallpaperDownloadManager (URLSession background downloads, resume, progress, retry)
        │
LocalLibrary           (Application Support/…/Wallpapers/<id>/{video.ext, thumb.jpg, meta.json})
        │
WallpaperPlayer        (AVQueuePlayer + AVPlayerLooper in a desktop-level window)
```

Rules:

- Browsing uses `thumbUrl` (remote, cached by `URLCache`/`AsyncImage` or a small disk cache). **No video is downloaded until the user selects "Save/Use".**
- Once saved, the app plays only from local disk (offline).
- The catalog (names, categories, thumbs) is cached on disk so the grid also works offline.

---

## 4. Swift implementation

Target: macOS 14+ (the MacWall app itself requires macOS 15). Swift 5.9+/6, SwiftUI, async/await.

### 4.1 Models

```swift
import Foundation

struct CatalogPage: Decodable {
    let wallpapers: [Wallpaper]
    let total: Int
    let page: Int
    let limit: Int
    let hasMore: Bool
}

struct Wallpaper: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let tags: [String]
    let videoKey: String
    let thumbKey: String
    let videoUrl: URL        // 1280px transformed preview from the API
    let thumbUrl: URL
    let isPro: Bool
    let likeCount: Int
    let createdAt: Date?

    // Fields known to be empty today; keep optional-tolerant.
    let durationSeconds: Double?
    let fileSizeBytes: Int64?
    let resolution: String?

    var isCommunityPending: Bool { videoKey.hasPrefix("community-pending/") }
    var fileExtension: String { (videoKey as NSString).pathExtension.lowercased() } // "mp4" | "mov"
}

enum WallpaperCategory: String, CaseIterable {
    case anime = "Anime", cars = "Cars", others = "Others", nature = "Nature",
         heroes = "Heroes", dark = "Dark", gaming = "Gaming", space = "Space",
         abstract = "Abstract"
}

enum CatalogSort: String { case newest, popular }
```

Decoder config: `createdAt` uses fractional-second ISO-8601 with variable precision (`2026-10-01T09:10:45.38402+00:00`, `...07:41:04.767+00:00`). A stock `.iso8601` strategy fails on fractional seconds, so use a custom strategy:

```swift
extension JSONDecoder {
    static let macwall: JSONDecoder = {
        let d = JSONDecoder()
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = f.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                debugDescription: "Bad date: \(s)"))
        }
        return d
    }()
}
```

### 4.2 API client

```swift
import Foundation

actor MacWallCatalogClient {
    static let base = URL(string: "https://macwall.app/api/wallpapers")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchPage(page: Int = 1,
                   limit: Int = 60,                 // server cap is 60
                   category: WallpaperCategory? = nil,
                   query: String? = nil,
                   sort: CatalogSort? = nil) async throws -> CatalogPage {
        var c = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "page", value: "\(page)"),
                     URLQueryItem(name: "limit", value: "\(min(limit, 60))")]
        if let category { items.append(.init(name: "category", value: category.rawValue)) } // case-sensitive
        if let query, !query.isEmpty { items.append(.init(name: "q", value: query)) }      // NOT "search"
        if let sort { items.append(.init(name: "sort", value: sort.rawValue)) }
        c.queryItems = items

        var req = URLRequest(url: c.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("MyLiveWallpaperApp/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder.macwall.decode(CatalogPage.self, from: data)
    }

    /// Loads every page (≈14 requests at limit=60 for 829 items). Call rarely; cache the result.
    func fetchAll(category: WallpaperCategory? = nil) async throws -> [Wallpaper] {
        var out: [Wallpaper] = []
        var page = 1
        while true {
            let p = try await fetchPage(page: page, category: category)
            out += p.wallpapers
            if !p.hasMore { break }
            page += 1
        }
        return out.filter { !$0.isPro && !$0.isCommunityPending }
    }
}
```

Catalog caching: write the decoded array to `Application Support/<App>/catalog.json` with a timestamp; refresh at most every few hours or on user pull-to-refresh. This keeps load on the third-party backend minimal.

### 4.3 URL resolver

```swift
enum Quality { case original, max4K, web1280 }

struct VideoSourceResolver {
    static let cdn = URL(string: "https://cdn.macwall.app")!

    static func candidates(for w: Wallpaper, preferred: Quality = .original) -> [URL] {
        let original = cdn.appendingPathComponent(w.videoKey)
        let transform4K = URL(string:
            "https://cdn.macwall.app/cdn-cgi/media/mode=video,width=3840,fit=scale-down,audio=false/\(w.videoKey)")!
        let all: [(Quality, URL)] = [(.original, original), (.max4K, transform4K), (.web1280, w.videoUrl)]
        let start = all.firstIndex { $0.0 == preferred } ?? 0
        return Array(all[start...]).map(\.1)       // preferred first, then lower quality fallbacks
    }

    /// Returns the first URL that answers 2xx to a ranged GET of byte 0.
    static func firstReachable(_ urls: [URL], session: URLSession = .shared) async -> URL? {
        for url in urls {
            var req = URLRequest(url: url)
            req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            req.setValue("MyLiveWallpaperApp/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            if let (_, resp) = try? await session.data(for: req),
               let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) {
                return url
            }
        }
        return nil
    }
}
```

### 4.4 Local library layout

```
~/Library/Application Support/<YourApp>/Wallpapers/
    <wallpaper.id>/
        video.mp4 | video.mov
        thumb.jpg
        meta.json        // Wallpaper + sourceURL + downloadedAt + byteCount + pixel size + duration
```

```swift
struct LocalWallpaper: Codable, Identifiable {
    let wallpaper: Wallpaper
    let sourceURL: URL
    let downloadedAt: Date
    let byteCount: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: Double
    var id: String { wallpaper.id }
}

enum LibraryPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("<YourApp>/Wallpapers", isDirectory: true)
    }
    static func dir(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
}
```

Use a sanitized directory name (ids are slugs/UUIDs, but validate: `[A-Za-z0-9._-]+`) to avoid path traversal if the API ever returns odd values.

### 4.5 Download manager (save a chosen video for offline use)

Requirements: progress, cancel, resume after app relaunch, atomic move into place, validate the file is playable, and a small concurrency limit (2 at once).

```swift
import Foundation
import AVFoundation

@MainActor
final class WallpaperDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var progress: [String: Double] = [:]     // wallpaper.id -> 0...1
    @Published private(set) var library: [LocalWallpaper] = []

    private var session: URLSession!
    private var tasks: [Int: (wallpaper: Wallpaper, source: URL)] = [:]   // taskIdentifier -> info

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default          // use .background(withIdentifier:) if downloads must survive app quit
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.waitsForConnectivity = true
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        loadLibrary()
    }

    func isSaved(_ w: Wallpaper) -> Bool { library.contains { $0.id == w.id } }

    func save(_ w: Wallpaper, quality: Quality = .original) async {
        guard !isSaved(w), progress[w.id] == nil else { return }
        progress[w.id] = 0
        let urls = VideoSourceResolver.candidates(for: w, preferred: quality)
        guard let source = await VideoSourceResolver.firstReachable(urls) else {
            progress[w.id] = nil; return                   // surface an error to the UI
        }
        var req = URLRequest(url: source)
        req.setValue("MyLiveWallpaperApp/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: req)
        tasks[task.taskIdentifier] = (w, source)
        task.resume()
    }

    func cancel(_ w: Wallpaper) {
        for (id, info) in tasks where info.wallpaper.id == w.id {
            session.getAllTasks { $0.first { $0.taskIdentifier == id }?.cancel() }
        }
        progress[w.id] = nil
    }

    func remove(_ w: Wallpaper) {
        try? FileManager.default.removeItem(at: LibraryPaths.dir(w.id))
        library.removeAll { $0.id == w.id }
    }

    // MARK: URLSessionDownloadDelegate
    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                                didWriteData _: Int64, totalBytesWritten written: Int64,
                                totalBytesExpectedToWrite total: Int64) {
        guard total > 0 else { return }
        let id = t.taskIdentifier
        Task { @MainActor in
            if let w = self.tasks[id]?.wallpaper { self.progress[w.id] = Double(written) / Double(total) }
        }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                                didFinishDownloadingTo tmp: URL) {
        // The temp file is deleted when this method returns: move it synchronously.
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: tmp, to: staged)
        let id = t.taskIdentifier
        let status = (t.response as? HTTPURLResponse)?.statusCode ?? 0
        Task { @MainActor in await self.finish(taskID: id, staged: staged, status: status) }
    }

    nonisolated func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        guard e != nil else { return }
        let id = t.taskIdentifier
        Task { @MainActor in
            if let w = self.tasks[id]?.wallpaper { self.progress[w.id] = nil }
            self.tasks[id] = nil
        }
    }

    // MARK: Finalize
    private func finish(taskID: Int, staged: URL, status: Int) async {
        defer { tasks[taskID] = nil }
        guard let info = tasks[taskID] else { return }
        let w = info.wallpaper
        defer { progress[w.id] = nil }
        guard (200..<300).contains(status) else { try? FileManager.default.removeItem(at: staged); return }

        let dir = LibraryPaths.dir(w.id)
        let dest = dir.appendingPathComponent("video.\(w.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.moveItem(at: staged, to: dest)

            // Validate that it is a playable video and read real metadata.
            let asset = AVURLAsset(url: dest)
            let playable = try await asset.load(.isPlayable)
            guard playable, let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw URLError(.cannotDecodeContentData)
            }
            let size = try await track.load(.naturalSize)
            let duration = try await asset.load(.duration).seconds
            let bytes = (try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0

            // Save thumbnail for offline grid.
            if let (data, _) = try? await URLSession.shared.data(from: w.thumbUrl) {
                try? data.write(to: dir.appendingPathComponent("thumb.jpg"))
            }

            let local = LocalWallpaper(wallpaper: w, sourceURL: info.source, downloadedAt: .now,
                                       byteCount: bytes, pixelWidth: Int(size.width),
                                       pixelHeight: Int(size.height), duration: duration)
            try JSONEncoder().encode(local).write(to: dir.appendingPathComponent("meta.json"))
            library.append(local)
        } catch {
            try? FileManager.default.removeItem(at: dir)    // never leave a half-saved wallpaper
        }
    }

    private func loadLibrary() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: LibraryPaths.root,
                    includingPropertiesForKeys: nil)) ?? []
        library = dirs.compactMap {
            (try? Data(contentsOf: $0.appendingPathComponent("meta.json")))
                .flatMap { try? JSONDecoder().decode(LocalWallpaper.self, from: $0) }
        }
    }
}
```

Production notes for Claude Code to handle:

- Add a retry with exponential backoff (e.g. 3 attempts) and fall through to the next candidate URL on 403/404.
- If the file is HEVC/ProRes `.mov`, `AVURLAsset` plays it natively on macOS; no conversion is needed.
- Show size/duration in the UI after download (from real metadata, not the API).
- Mind disk usage: 4K loops can be tens of MB each. Add a "Storage" screen with per-item delete.
- For downloads that must continue after quitting the app, switch to `URLSessionConfiguration.background(withIdentifier:)` and handle `application(_:handleEventsForBackgroundURLSession:)`/app delegate callbacks; the `tasks` dictionary must then be rebuilt from `session.getAllTasks`.

### 4.6 Playing as a desktop wallpaper (looping, low power)

```swift
import AppKit
import AVFoundation

final class WallpaperWindowController {
    private var window: NSWindow?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    func play(fileURL: URL, on screen: NSScreen) {
        let item = AVPlayerItem(url: fileURL)
        let q = AVQueuePlayer()
        q.isMuted = true
        q.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: q, templateItem: item)
        player = q

        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                         backing: .buffered, defer: false, screen: screen)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isOpaque = true
        w.ignoresMouseEvents = true
        w.backgroundColor = .black

        let layer = AVPlayerLayer(player: q)
        layer.videoGravity = .resizeAspectFill
        let v = NSView(frame: screen.frame)
        v.wantsLayer = true
        layer.frame = v.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer?.addSublayer(layer)
        w.contentView = v
        w.orderFrontRegardless()
        window = w
        q.play()
    }

    func stop() { player?.pause(); window?.orderOut(nil); window = nil; looper = nil; player = nil }
}
```

Add: one controller per `NSScreen`, pause when on battery/low-power mode or when a full-screen app covers the desktop (`NSWorkspace` notifications + `NSWindow.occlusionState`), re-create on `NSApplication.didChangeScreenParametersNotification`, and relaunch-at-login via `SMAppService`.

### 4.7 Grid UI sketch (SwiftUI)

- `LazyVGrid` of cards: `AsyncImage(url: wallpaper.thumbUrl)` + name + category.
- Category chips from `WallpaperCategory.allCases`; search field → `q` parameter with ~300 ms debounce; sort picker → `newest | popular`.
- Infinite scroll: load the next `page` when the last card appears while `hasMore` is true.
- Card actions: **Preview** (stream `videoUrl`, the light 1280 px file, in an `AVPlayer`; do not download the full file for preview), **Save for offline** (calls `save`), **Set as wallpaper** (only enabled after saved), **Remove**.

---

## 5. Politeness & robustness (the API is undocumented)

- This is **not an official public API**. It can change shape or be rate-limited without notice. Decode defensively (optional fields, ignore unknown keys), and show a clear "catalog unavailable" state rather than crashing.
- Cache the catalog on disk; do not hit the API on every launch or on every keystroke.
- Limit to ≤2 concurrent downloads; use `limit=60` pages with a short pause between pages (e.g. 200–500 ms) when syncing all 829 items.
- Send a descriptive `User-Agent`.
- Keep a record (email/message) of the permission to use these videos, and credit the source in the app's About screen if requested by the owner.
- Do not scrape or rely on any endpoint other than those listed above (`/api/wallpapers`, `cdn.macwall.app`). The site also exposes checkout/analytics endpoints that this app must never touch.

---

## 6. Suggested implementation order

1. Models + `JSONDecoder.macwall`, then a unit test decoding a captured sample response.
2. `MacWallCatalogClient` + disk cache + a basic SwiftUI grid with thumbnails, categories, search, pagination.
3. `VideoSourceResolver` + run the verification checks (section 7) to decide the default quality.
4. `WallpaperDownloadManager` with progress UI and offline library.
5. `WallpaperWindowController` for looping playback, multi-display, power handling.
6. Storage management, error states, polish.

---

## 7. Verification checklist (run first, from the Mac)

```bash
# 1) API works
curl -s "https://macwall.app/api/wallpapers?limit=2" | jq '.total, .wallpapers[0].videoKey'

# 2) Is the ORIGINAL file downloadable? (check status, content-type, length, range support)
curl -sI "https://cdn.macwall.app/videos/ichigo-kurosaki-purple-aura.mp4"

# 3) Does a bigger transform work?
curl -sI "https://cdn.macwall.app/cdn-cgi/media/mode=video,width=3840,fit=scale-down,audio=false/videos/ichigo-kurosaki-purple-aura.mp4"

# 4) Known-good web version (1280px) for comparison
curl -sI "https://cdn.macwall.app/cdn-cgi/media/mode=video,width=1280,fit=scale-down,audio=false/videos/ichigo-kurosaki-purple-aura.mp4"

# 5) If 2) or 3) return 403, retry with browser-like headers to detect hotlink protection
curl -sI -H "Referer: https://macwall.app/" -H "User-Agent: Mozilla/5.0" \
  "https://cdn.macwall.app/videos/ichigo-kurosaki-purple-aura.mp4"

# 6) Download one file and inspect real resolution/codec/duration
curl -L -o /tmp/test.mp4 "https://cdn.macwall.app/videos/ichigo-kurosaki-purple-aura.mp4"
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate:format=duration,size /tmp/test.mp4
```

Decision rules based on the results:

- `#2` returns 200/206 → use **original** as the default quality (sharpest).
- `#2` fails but `#3` works → use the 3840-wide transform.
- Only `#4` works → use `videoUrl` (1280 px) and tell the owner that higher quality is not available from the CDN directly.
- If `#5` is needed to succeed, the CDN enforces hotlink protection: ask the owner whether he can get an official download endpoint or CDN access from MacWall instead of spoofing headers.

---

## 8. Known unknowns to report back to the owner

- Whether originals are public and what their resolution/codec/size are.
- Whether any items in the catalog are paid/Pro in the future (`isPro` is `false` for all 829 now; the app already filters `isPro == true`).
- Whether `community-pending/` items are moderated content; the app excludes them by default.
