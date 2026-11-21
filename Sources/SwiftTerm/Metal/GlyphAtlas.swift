//
//  GlyphAtlas.swift
//  SwiftTerm
//
//  Metal glyph atlas for caching rasterized glyphs.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import Metal
import MetalKit
import CoreGraphics
import CoreText

/// Pure shelf-packing policy for the glyph atlas, extracted from the Metal
/// type so the allocation behavior can be unit tested without a GPU.
struct ShelfAllocator {
    /// Top-left corner of the allocated slot, in atlas texel coordinates.
    struct Allocation: Equatable {
        let x: Int
        let y: Int
    }

    private struct Shelf {
        let y: Int
        let height: Int
        var currentX: Int
    }

    private var shelves: [Shelf] = []
    /// Total height consumed by shelves so far.
    private(set) var usedY = 0
    /// Atlas edge length in texels.
    let size: Int
    /// Transparent padding kept around every glyph to avoid bleeding.
    let padding: Int

    init(size: Int, padding: Int = 1) {
        self.size = size
        self.padding = padding
    }

    /// Reserve a slot for a glyph of the given texel dimensions, or nil when
    /// the glyph does not fit or the atlas is full.
    mutating func allocate(width: Int, height: Int) -> Allocation? {
        let paddedWidth = width + padding * 2
        let paddedHeight = height + padding * 2
        guard paddedWidth <= size, paddedHeight <= size else { return nil }

        // First shelf tall enough that still has horizontal room.
        for i in shelves.indices {
            if shelves[i].height >= paddedHeight, shelves[i].currentX + paddedWidth <= size {
                let allocation = Allocation(x: shelves[i].currentX + padding, y: shelves[i].y + padding)
                shelves[i].currentX += paddedWidth
                return allocation
            }
        }

        guard usedY + paddedHeight <= size else { return nil }
        let allocation = Allocation(x: padding, y: usedY + padding)
        shelves.append(Shelf(y: usedY, height: paddedHeight, currentX: paddedWidth))
        usedY += paddedHeight
        return allocation
    }

    mutating func removeAll() {
        shelves.removeAll()
        usedY = 0
    }
}

/// A texture atlas for storing rasterized glyphs
class GlyphAtlas {
    /// The Metal device
    let device: MTLDevice

    /// The atlas texture
    var texture: MTLTexture?

    /// Atlas edge length in texels
    let size: Int

    /// Shelf allocator managing space in the atlas
    private var allocator: ShelfAllocator

    /// Lock for thread safety. All glyph work is confined to the main thread
    /// today; the lock only guards against accidental off-main callers.
    private let lock = NSLock()

    /// Configuration for the atlas
    struct Configuration {
        /// Default atlas size (2048x2048 is typical)
        static let defaultSize = 2048

        /// Padding around glyphs in texels
        static let padding = 1
    }

    /// Initialize a new glyph atlas
    init(device: MTLDevice, size: Int = Configuration.defaultSize) {
        self.device = device
        self.size = size
        self.allocator = ShelfAllocator(size: size, padding: Configuration.padding)

        createTexture()
    }

    /// Create the Metal texture.
    ///
    /// `shared` storage allows direct CPU uploads but is unsupported for
    /// textures on Macs with discrete GPUs, where `managed` is required.
    /// The atlas is only ever sampled, so `renderTarget` usage is not needed
    /// (and is not legal in combination with `shared` storage on iOS).
    private func createTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        #if os(macOS)
        // `shared` allows direct CPU uploads but is unsupported for textures
        // on Macs with discrete GPUs, where `managed` is required.
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        #else
        // iOS/visionOS devices always have unified memory.
        descriptor.storageMode = .shared
        #endif

        texture = device.makeTexture(descriptor: descriptor)
    }

    /// Allocate space in the atlas
    /// - Returns: The rect where the glyph should be placed, or nil if no space
    func allocate(width: Int, height: Int) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }

        guard let allocation = allocator.allocate(width: width, height: height) else { return nil }
        return CGRect(
            x: CGFloat(allocation.x),
            y: CGFloat(allocation.y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }

    /// Reset the allocator so the atlas can be refilled from the top.
    ///
    /// Stale texels are harmless: after a reset the owning cache drops every
    /// entry and each drawn glyph is re-rasterized and re-uploaded into a
    /// freshly allocated slot before its UVs are ever sampled.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        allocator.removeAll()
    }

    /// Upload glyph pixel data to the atlas.
    ///
    /// CPU-side `replace(region:)` is safe for the current append-only usage
    /// pattern: uploads happen before the frame's commands are encoded, and
    /// `clear()`/re-use paths rebuild all cached UVs before the next draw.
    func upload(pixelData: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, at rect: CGRect) {
        guard let texture = texture else { return }

        let region = MTLRegionMake2D(Int(rect.origin.x), Int(rect.origin.y), width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: pixelData, bytesPerRow: bytesPerRow)
    }

    /// Get the UV coordinates for a rect in the atlas
    /// - Returns: Normalized UV coordinates in atlas texture space
    func uvRect(for rect: CGRect) -> CGRect {
        let sizeF = CGFloat(size)
        return CGRect(
            x: rect.origin.x / sizeF,
            y: rect.origin.y / sizeF,
            width: rect.width / sizeF,
            height: rect.height / sizeF
        )
    }
}
#endif
