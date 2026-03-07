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

/// Key for looking up cached glyphs
struct GlyphKey: Hashable {
    let fontID: ObjectIdentifier
    let text: String
    let scale: CGFloat

    init(font: CTFont, text: String, scale: CGFloat) {
        self.fontID = ObjectIdentifier(font)
        self.text = text
        self.scale = scale
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fontID)
        hasher.combine(text)
        hasher.combine(scale)
    }

    static func == (lhs: GlyphKey, rhs: GlyphKey) -> Bool {
        return lhs.fontID == rhs.fontID && lhs.text == rhs.text && lhs.scale == rhs.scale
    }
}

/// Information about a cached glyph
struct CachedGlyph {
    /// UV coordinates in the atlas
    let uvRect: CGRect
    /// Index of the atlas containing this glyph
    let atlasIndex: Int
    /// Bearing (offset from origin)
    let bearing: SIMD2<Float>
    /// Size of the glyph
    let size: SIMD2<Float>
    /// Advance width
    let advance: Float
}

/// Cache for rasterized glyphs
class GlyphCache {
    /// The atlas(es) for storing glyphs
    private var atlases: [GlyphAtlas]

    /// The glyph cache
    private var cache: [GlyphKey: CachedGlyph] = [:]

    /// Lock for thread safety
    private let lock = NSLock()

    /// The Metal device
    private let device: MTLDevice

    /// The command queue for uploads
    private let commandQueue: MTLCommandQueue

    /// Scale factor for the display
    private let scale: CGFloat

    /// Maximum number of atlases
    private let _maxAtlases: Int

    /// Initialize a new glyph cache
    init(device: MTLDevice, commandQueue: MTLCommandQueue, scale: CGFloat, maxAtlases: Int = 4) {
        self.device = device
        self.commandQueue = commandQueue
        self.scale = scale
        self._maxAtlases = maxAtlases
        self.atlases = [GlyphAtlas(device: device)]
    }

    /// Get or create a cached glyph for a character
    /// - Parameters:
    ///   - character: The character to cache
    ///   - font: The font to use
    ///   - commandBuffer: Optional command buffer for uploads
    /// - Returns: The cached glyph info, or nil if caching failed
    func getOrCreateGlyph(character: Character, font: CTFont, commandBuffer: MTLCommandBuffer? = nil) -> CachedGlyph? {
        let string = String(character)
        let key = GlyphKey(font: font, text: string, scale: scale)

        lock.lock()
        defer { lock.unlock() }

        // Check cache first
        if let cached = cache[key] {
            return cached
        }

        // Rasterize the rendered text for the character. This preserves fallback fonts and composed scalars.
        guard let rasterized = rasterizeText(string, font: font) else {
            return nil
        }

        // Free the data when done
        defer { rasterized.deallocate() }

        // Find space in an atlas
        let width = rasterized.width
        let height = rasterized.height

        for (index, atlas) in atlases.enumerated() {
            if let rect = atlas.allocate(width: width, height: height) {
                // Upload to atlas
                let buffer = commandBuffer ?? commandQueue.makeCommandBuffer()
                guard let cb = buffer else { return nil }

                atlas.upload(pixelData: rasterized.data, width: width, height: height, bytesPerRow: rasterized.bytesPerRow, at: rect, commandBuffer: cb)

                let cachedGlyph = CachedGlyph(
                    uvRect: atlas.uvRect(for: rect),
                    atlasIndex: index,
                    bearing: SIMD2<Float>(Float(rasterized.origin.x), Float(rasterized.origin.y)),
                    size: SIMD2<Float>(Float(CGFloat(width) / scale), Float(CGFloat(height) / scale)),
                    advance: Float(rasterized.advance)
                )

                cache[key] = cachedGlyph

                if commandBuffer == nil {
                    cb.commit()
                }

                return cachedGlyph
            }
        }

        // Try to create a new atlas if we haven't reached the limit
        if atlases.count < _maxAtlases {
            let newAtlas = GlyphAtlas(device: device)
            atlases.append(newAtlas)

            if let rect = newAtlas.allocate(width: width, height: height) {
                let buffer = commandBuffer ?? commandQueue.makeCommandBuffer()
                guard let cb = buffer else { return nil }

                newAtlas.upload(pixelData: rasterized.data, width: width, height: height, bytesPerRow: rasterized.bytesPerRow, at: rect, commandBuffer: cb)

                let cachedGlyph = CachedGlyph(
                    uvRect: newAtlas.uvRect(for: rect),
                    atlasIndex: atlases.count - 1,
                    bearing: SIMD2<Float>(Float(rasterized.origin.x), Float(rasterized.origin.y)),
                    size: SIMD2<Float>(Float(CGFloat(width) / scale), Float(CGFloat(height) / scale)),
                    advance: Float(rasterized.advance)
                )

                cache[key] = cachedGlyph

                if commandBuffer == nil {
                    cb.commit()
                }

                return cachedGlyph
            }
        }

        return nil
    }

    /// Rasterized glyph data
    struct RasterizedGlyph {
        let width: Int
        let height: Int
        let data: UnsafeMutableRawPointer
        let bytesPerRow: Int
        let origin: CGPoint
        let advance: CGFloat

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
        // Use grayscale antialiasing for clean alpha blending in the shader
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

        return RasterizedGlyph(
            width: width,
            height: height,
            data: data,
            bytesPerRow: bytesPerRow,
            origin: origin,
            advance: advance
        )
    }

    /// Clear the cache
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        atlases = [GlyphAtlas(device: device)]
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
