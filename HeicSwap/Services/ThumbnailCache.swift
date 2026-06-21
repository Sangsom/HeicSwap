//
//  ThumbnailCache.swift
//  HeicSwap
//
//  Backs the Convert queue grid (task 5.1): decodes a downscaled thumbnail for each queued
//  image and caches it by file URL so scrolling stays smooth and every original is decoded at
//  most once. The decode is an ImageIO downscale-on-load (same approach as the engine/PDFBuilder)
//  run off the main actor; results are held in an `NSCache` that the system can evict under
//  memory pressure. No network, ever — thumbnails come straight off the on-device original.
//

import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A shared, memory-pressure-aware cache of downscaled thumbnails keyed by the original's URL.
@MainActor
final class ThumbnailCache {

    /// App-wide cache. One instance keeps decodes shared across the queue and any future surface
    /// (e.g. the results sheet) that shows the same originals.
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, UIImage>()

    init(countLimit: Int = 256) {
        cache.countLimit = countLimit
    }

    /// The already-decoded thumbnail for `url`, if present — lets a cell render synchronously on
    /// re-appearance without flashing a placeholder.
    func cached(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Returns the thumbnail for `url`, decoding (off the main actor) and caching it on first
    /// request. `maxPixelSize` bounds the longest edge in pixels; pass the cell size × screen
    /// scale. Returns `nil` if the original can't be decoded.
    func thumbnail(for url: URL, maxPixelSize: Int) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }

        let image = await Task.detached(priority: .utility) {
            Self.decodeThumbnail(at: url, maxPixelSize: maxPixelSize)
        }.value

        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Decodes a downscaled thumbnail with ImageIO. `nonisolated` and pure so it runs off the main
    /// actor: `CGImageSourceCreateThumbnailAtIndex` downsamples on load (it never inflates the
    /// full-resolution bitmap), bakes in the orientation, and never upscales past the source.
    private nonisolated static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
