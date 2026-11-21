//
//  GlyphCache.swift
//  SwiftTerm
//
//  Caches rasterized glyphs for Metal rendering.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import Metal
import CoreGraphics
import CoreText

/// Key for buffer-cell glyphs. Uses the numeric cell code instead of a String
/// so full-frame rebuilds do not allocate and hash a string per cell.
struct GlyphKey: Hashable {
    let fontID: ObjectIdentifier
    let code: Int32
    let scale: CGFloat
}

/// Key for glyphs rasterized from arbitrary text (IME marked text), which has
/// no cell code to key on. This path is rare so string hashing is acceptable.
struct TextGlyphKey: Hashable {
    let fontID: ObjectIdentifier
    let text: String
    let scale: CGFloat
}

/// Information about a cached glyph
struct CachedGlyph {
    /// UV coordinates in the owning atlas
    let uvRect: CGRect
    /// Index of the atlas containing this glyph
    let atlasIndex: Int
    /// Bearing (offset from cell origin) in points
    let bearing: SIMD2<Float>
    /// Glyph size in points
    let size: SIMD2<Float>
    /// Rasterized size in texels, used for half-texel UV insets
    let texelSize: SIMD2<Int>
    /// True when the rasterized bitmap carries color (color-emoji fonts)
    let isColor: Bool
    /// Advance width in points
    let advance: Float
}

/// Cache for rasterized glyphs
class GlyphCache {
    /// The atlas(es) for storing glyphs
    private var atlases: [GlyphAtlas]

    /// Cached buffer-cell glyphs
    private var cache: [GlyphKey: CachedGlyph] = [:]

    /// Cached arbitrary-text glyphs (IME marked text)
    private var textCache: [TextGlyphKey: CachedGlyph] = [:]

    /// Lock for thread safety. Glyph work is main-thread confined today; the
    /// lock only guards against accidental off-main callers. It must never be
    /// re-entered: internal helpers are the `*Locked` variants.
    private let lock = NSLock()

    /// The Metal device
    private let device: MTLDevice

    /// Scale factor for the display
    private var scale: CGFloat

    /// Maximum number of atlases
    private let _maxAtlases: Int

    /// Invoked (on the caller's thread, while unlocked state is consistent)
    /// after the cache was reset because every atlas filled up. The renderer
    /// uses this to schedule a full rebuild so no glyph is silently dropped.
    var onCacheReset: (() -> Void)?

    /// Initialize a new glyph cache
    init(device: MTLDevice, scale: CGFloat, maxAtlases: Int = 4) {
        self.device = device
        self.scale = scale
        self._maxAtlases = maxAtlases
        self.atlases = [GlyphAtlas(device: device)]
    }

    /// Get or create a cached glyph for a terminal buffer cell.
    ///
    /// `resolve` is only evaluated on a cache miss, which keeps the per-cell
    /// cost of full-frame rebuilds down to a dictionary lookup.
    func getOrCreateGlyph(code: Int32, font: CTFont, resolve: () -> Character) -> CachedGlyph? {
        let key = GlyphKey(fontID: ObjectIdentifier(font), code: code, scale: scale)

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        let entry = makeEntryLocked(character: String(resolve()), font: font)
        if let entry {
            cache[key] = entry
        }
        lock.unlock()
        return entry
    }

    /// Get or create a cached glyph for an arbitrary string (IME marked text).
    func getOrCreateGlyph(text: String, font: CTFont) -> CachedGlyph? {
        let key = TextGlyphKey(fontID: ObjectIdentifier(font), text: text, scale: scale)

        lock.lock()
        if let cached = textCache[key] {
            lock.unlock()
            return cached
        }
        let entry = makeEntryLocked(character: text, font: font)
        if let entry {
            textCache[key] = entry
        }
        lock.unlock()
        return entry
    }

    /// Rasterize and upload a glyph, resetting the atlas set when all atlases
    /// are full. Caller must hold `lock`.
    private func makeEntryLocked(character: String, font: CTFont) -> CachedGlyph? {
        guard let rasterized = rasterizeText(character, font: font) else {
            return nil
        }
        defer { rasterized.deallocate() }

        if let entry = uploadEntryLocked(rasterized: rasterized, font: font) {
            return entry
        }

        // Every atlas is full: rebuild from scratch instead of dropping the
        // glyph. The reset invalidates all cached UVs, so the renderer must
        // rebuild its vertex caches before the next frame.
        if atlases.count >= _maxAtlases {
            atlases = [GlyphAtlas(device: device)]
            cache.removeAll()
            textCache.removeAll()
            onCacheReset?()

            if let entry = uploadEntryLocked(rasterized: rasterized, font: font) {
                return entry
            }
            return nil
        }

        let newAtlas = GlyphAtlas(device: device)
        atlases.append(newAtlas)
        return uploadEntryLocked(rasterized: rasterized, font: font)
    }

    /// Allocate atlas space for the rasterized glyph and upload it.
    /// Caller must hold `lock`.
    private func uploadEntryLocked(rasterized: RasterizedGlyph, font: CTFont) -> CachedGlyph? {
        let width = rasterized.width
        let height = rasterized.height

        for (index, atlas) in atlases.enumerated() {
            if let rect = atlas.allocate(width: width, height: height) {
                atlas.upload(
                    pixelData: rasterized.data,
                    width: width,
                    height: height,
                    bytesPerRow: rasterized.bytesPerRow,
                    at: rect
                )
                return entry(
                    for: rasterized,
                    atlasIndex: index,
                    rect: rect,
                    isColor: rasterized.isColor
                )
            }
        }
        return nil
    }

    private func entry(
        for rasterized: RasterizedGlyph,
        atlasIndex: Int,
        rect: CGRect,
        isColor: Bool
    ) -> CachedGlyph {
        let atlas = atlases[atlasIndex]
        return CachedGlyph(
            uvRect: atlas.uvRect(for: rect),
            atlasIndex: atlasIndex,
            bearing: SIMD2<Float>(Float(rasterized.origin.x), Float(rasterized.origin.y)),
            size: SIMD2<Float>(Float(CGFloat(rasterized.width) / scale), Float(CGFloat(rasterized.height) / scale)),
            texelSize: SIMD2<Int>(rasterized.width, rasterized.height),
            isColor: isColor,
            advance: Float(rasterized.advance)
        )
    }

    /// Rasterized glyph data
    struct RasterizedGlyph {
        let width: Int
        let height: Int
        let data: UnsafeMutableRawPointer
        let bytesPerRow: Int
        let origin: CGPoint
        let advance: CGFloat
        /// True when the bitmap contains saturated color (color-emoji fonts)
        let isColor: Bool

        func deallocate() {
            data.deallocate()
        }
    }

    /// Rasterize a character string to raw pixel data.
    private func rasterizeText(_ text: String, font: CTFont) -> RasterizedGlyph? {
        let padding: CGFloat = 1.0
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .excludeTypographicLeading])

        if bounds.isNull || bounds.isEmpty {
            bounds = CGRect(x: 0, y: -descent, width: max(advance, CTFontGetSize(font) * 0.6), height: ascent + descent)
        }

        let leftInset = min(0, bounds.minX)
        let drawWidth = max(advance, bounds.maxX) - leftInset
        let drawHeight = max(1, ascent + descent)

        let width = Int(ceil((drawWidth + padding * 2) * scale))
        let height = Int(ceil((drawHeight + padding * 2) * scale))

        guard width > 0 && height > 0 && width < 500 && height < 500 else {
            print("GlyphCache: Invalid glyph size for \(text.debugDescription): \(width)x\(height)")
            return nil
        }

        let bytesPerRow = width * 4
        guard let data = calloc(height, bytesPerRow) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            free(data)
            return nil
        }

        // Draw white glyphs into the alpha channel.
        // Use grayscale antialiasing for clean alpha blending in the shader.
        context.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        // Use grayscale antialiasing (not subpixel) for correct alpha blending
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelQuantizeFonts(true)
        context.setAllowsFontSubpixelQuantization(true)

        // CoreText draws in a Y-up coordinate system; flip once here, then keep atlas UV unflipped.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        let drawX = ((padding - leftInset) * scale).rounded() / scale
        let drawY = ((padding + descent) * scale).rounded() / scale
        context.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, context)

        let cellHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        let topOffset = max(-padding, floor((cellHeight - drawHeight) / 2.0) - padding)
        let origin = CGPoint(x: leftInset - padding, y: topOffset)

        let isColor = Self.containsColor(data: data, width: width, height: height, bytesPerRow: bytesPerRow)

        return RasterizedGlyph(
            width: width,
            height: height,
            data: data,
            bytesPerRow: bytesPerRow,
            origin: origin,
            advance: advance,
            isColor: isColor
        )
    }

    /// Detects color bitmaps (emoji): monochrome glyphs are drawn white, so
    /// any pixel whose channels spread beyond the threshold proves color.
    private static func containsColor(data: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) -> Bool {
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let threshold: UInt8 = 24
        for row in 0..<height {
            let base = pixels + row * bytesPerRow
            for col in 0..<width {
                let offset = col * 4
                let a = base[offset + 3]
                if a == 0 { continue }
                let r = base[offset]
                let g = base[offset + 1]
                let b = base[offset + 2]
                let maxValue = max(r, g, b)
                let minValue = min(r, g, b)
                if maxValue > minValue, maxValue &- minValue > threshold {
                    return true
                }
            }
        }
        return false
    }

    /// Clear the cache
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        textCache.removeAll()
        atlases = [GlyphAtlas(device: device)]
    }

    /// Update the display scale factor, clearing the cache if it changed
    func updateScale(_ newScale: CGFloat) {
        guard newScale != scale else { return }
        scale = newScale
        clear()
    }

    /// Get the atlas texture at the given index
    func atlasTexture(at index: Int) -> MTLTexture? {
        guard index < atlases.count else { return nil }
        return atlases[index].texture
    }

    /// Get the number of atlases
    var atlasCount: Int {
        return atlases.count
    }

    /// Get the atlas size
    var atlasSize: Int {
        return atlases.first?.size ?? GlyphAtlas.Configuration.defaultSize
    }

    /// Maximum number of atlases allowed
    var maxAtlases: Int {
        return _maxAtlases
    }
}
#endif
