import AppKit
import CoreImage
import ImageIO

/// A store's own addresses for a game's art, as its library lists them.
struct StoreArt: Hashable {
    var cover: URL?
    var hero: URL?
    var logo: URL?

    func url(_ kind: ArtKind) -> URL? {
        switch kind {
        case .cover: return cover
        case .hero: return hero
        case .logo: return logo
        }
    }
}

enum ArtKind: String {
    case cover, hero, logo

    var fileNames: [String] {
        switch self {
        // Newer games only ship the portrait cover as library_capsule.
        case .cover: return ["library_600x900_2x.jpg", "library_600x900.jpg", "library_capsule_2x.jpg", "library_capsule.jpg"]
        case .hero: return ["library_hero.jpg"]
        case .logo: return ["logo.png"]
        }
    }

    /// Covers are drawn 154 pt wide (231 tall, a little more when picked): kept at that size on a
    /// Retina screen rather than Steam's 1200×1800, a quarter of the memory per cover. Hero art
    /// fills the window, logos are small: both stay as they are.
    var maxPixelSize: Int? { self == .cover ? 640 : nil }
}

/// Home's stage backdrop, made once per game (ArtworkStore.stageBackdrop).
struct StageBackdrop {
    let image: NSImage
    let glow: NSColor
    let brightness: CGFloat
}

/// Loads game art in this order: memory → own disk cache → Steam's cache inside the bottle → Steam CDN.
/// After the first run everything comes from disk, so the launcher works offline.
actor ArtworkStore {
    static let shared = ArtworkStore()

    private let memory = NSCache<NSString, NSImage>()
    private let backdrops = NSCache<NSString, Box>()
    private var backdropTasks: [String: Task<StageBackdrop?, Never>] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let cacheDir: URL

    /// Art already fetched, one file per game and kind ("steam.570_cover").
    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightforge/Artwork", isDirectory: true)
    }

    init() {
        cacheDir = Self.cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memory.countLimit = 400
        // Decoded pixels, not files: a whole library of covers stays well within this.
        memory.totalCostLimit = 300 * 1024 * 1024
        backdrops.countLimit = 30  // about 2 MB each
    }

    func image(for game: Game, kind: ArtKind) async -> NSImage? {
        let key = "\(game.gameID.key)_\(kind.rawValue)"
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let running = inflight[key] { return await running.value }

        let dir = cacheDir
        let task = Task<NSImage?, Never> {
            await Self.load(game: game, kind: kind, cacheDir: dir, key: key)
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image)) }
        return image
    }

    /// Home's stage behind its covers: the game's key art (else its cover) blurred once, at about
    /// window size, and kept in the cache – never blurred live over the window, which would cost the
    /// battery and the graphics power games need. With it the colour the cover gives off, for the
    /// light under it, and how bright the cover is, so a bright one is dimmed beside the text.
    func stageBackdrop(for game: Game) async -> StageBackdrop? {
        let key = "\(game.gameID.key)_stage"
        if let cached = backdrops.object(forKey: key as NSString) { return cached.value }
        // The stage and the backdrop ask at once: one of them makes it.
        if let running = backdropTasks[key] { return await running.value }
        let task = Task<StageBackdrop?, Never> { await makeStageBackdrop(for: game, key: key) }
        backdropTasks[key] = task
        let backdrop = await task.value
        backdropTasks[key] = nil
        return backdrop
    }

    private func makeStageBackdrop(for game: Game, key: String) async -> StageBackdrop? {
        let file = cacheDir.appendingPathComponent(key + ".jpg")
        var blurred = (try? Data(contentsOf: file)).flatMap(Self.cgImage)
        if blurred == nil {
            var art = await image(for: game, kind: .hero)
            if art == nil { art = await image(for: game, kind: .cover) }
            guard let source = art?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let made = Self.blurred(source) else { return nil }
            Self.writeJPEG(made, to: file)
            blurred = made
        }
        guard let blurred else { return nil }
        let cover = await image(for: game, kind: .cover)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let light = Self.light(of: cover ?? blurred)
        let backdrop = StageBackdrop(image: NSImage(cgImage: blurred, size: NSSize(width: blurred.width, height: blurred.height)),
                                     glow: light.glow, brightness: light.brightness)
        backdrops.setObject(Box(backdrop), forKey: key as NSString)
        return backdrop
    }

    private final class Box: NSObject {
        let value: StageBackdrop
        init(_ value: StageBackdrop) { self.value = value }
    }

    /// Core Image on the GPU, made once; only used to make backdrops.
    private static let images = CIContext(options: [.cacheIntermediates: false])

    /// About 30 pt of blur on the window, at a width that's plenty for something this soft.
    static func blurred(_ source: CGImage, width: CGFloat = 1024, sigma: Double = 20) -> CGImage? {
        var image = CIImage(cgImage: source)
        let scale = min(1, width / max(image.extent.width, 1))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent.integral
        let soft = image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        return images.createCGImage(soft, from: extent)
    }

    /// The cover's average colour, saturated a little for the light, and its brightness (0…1).
    static func light(of image: CGImage) -> (glow: NSColor, brightness: CGFloat) {
        let input = CIImage(cgImage: image)
        var pixel = [UInt8](repeating: 0, count: 4)
        if let average = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)])?.outputImage {
            images.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                          format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        let (r, g, b) = (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
        let average = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        let glow = NSColor(hue: average.hueComponent, saturation: min(1, average.saturationComponent * 1.4 + 0.1),
                           brightness: 0.9, alpha: 1)
        return (glow, 0.2126 * r + 0.7152 * g + 0.0722 * b)
    }

    private static func cgImage(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    private static func cost(of image: NSImage) -> Int {
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
        return max(pixels.width * pixels.height * 4, 1)
    }

    /// An image from file data, scaled down to `kind`'s size when it's larger.
    static func decode(_ data: Data, kind: ArtKind) -> NSImage? {
        guard let maxSize = kind.maxPixelSize, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Steam adds art to games now and then; a "nothing there" from a week ago is asked again.
    private static let missingLifetime: TimeInterval = 7 * 24 * 3600

    private static func load(game: Game, kind: ArtKind, cacheDir: URL, key: String) async -> NSImage? {
        let fm = FileManager.default
        let cached = cacheDir.appendingPathComponent(key)
        let missingMarker = cacheDir.appendingPathComponent(key + ".missing")

        if let data = try? Data(contentsOf: cached), let image = decode(data, kind: kind) { return image }

        // Steam's own cache first – it can gain art after a "missing" marker was written.
        if let local = localFile(game: game, kind: kind),
           let data = try? Data(contentsOf: local),
           let image = decode(data, kind: kind) {
            try? data.write(to: cached)
            try? fm.removeItem(at: missingMarker)
            return image
        }
        if let written = (try? fm.attributesOfItem(atPath: missingMarker.path))?[.modificationDate] as? Date {
            guard Date().timeIntervalSince(written) > missingLifetime else { return nil }
            try? fm.removeItem(at: missingMarker)
        }

        let urls = remoteURLs(game: game, kind: kind)
        // No address at all (a store that lists none for it): nothing to remember as missing.
        var everythingWas404 = !urls.isEmpty
        for url in urls {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let image = decode(data, kind: kind) {
                    try? data.write(to: cached)
                    return image
                }
                if status != 404 && status != 403 { everythingWas404 = false }
            } catch {
                everythingWas404 = false // offline – try again next time
            }
        }

        // Steam has no such art for this game: remember that and stop asking.
        if everythingWas404 { fm.createFile(atPath: missingMarker.path, contents: nil) }
        return nil
    }

    private static func localFile(game: Game, kind: ArtKind) -> URL? {
        guard game.provider == .steam else { return nil }
        let fm = FileManager.default
        let cache = game.steamRoot.appendingPathComponent("appcache/librarycache", isDirectory: true)

        // Older Steam: flat files like 1245620_library_600x900.jpg
        for name in kind.fileNames {
            let flat = cache.appendingPathComponent("\(game.appID)_\(name)")
            if fm.fileExists(atPath: flat.path) { return flat }
        }

        // Newer Steam: one folder per app, files sometimes in hashed subfolders
        let dir = cache.appendingPathComponent("\(game.appID)", isDirectory: true)
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let files = enumerator.compactMap { $0 as? URL }
        for name in kind.fileNames {
            if let hit = files.first(where: { $0.lastPathComponent == name }) { return hit }
        }
        return nil
    }

    private static func remoteURLs(game: Game, kind: ArtKind) -> [URL] {
        guard let appID = game.gameID.steamAppID else { return game.art?.url(kind).map { [$0] } ?? [] }
        let bases = [
            "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/",
            "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/",
        ]
        return kind.fileNames.flatMap { name in bases.compactMap { URL(string: $0 + name) } }
    }
}
