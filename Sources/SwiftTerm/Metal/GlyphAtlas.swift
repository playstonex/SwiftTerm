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

/// A texture atlas for storing rasterized glyphs
class GlyphAtlas {
    /// The Metal device
    let device: MTLDevice

    /// The atlas texture
    var texture: MTLTexture?

    /// Atlas size
    let size: Int

    /// Shelf allocator for managing space
    private var shelves: [Shelf] = []

    /// Current Y position for new shelves
    private var currentY: Int = 0

    /// Lock for thread safety
    private let lock = NSLock()

    /// A shelf in the atlas for allocating glyph slots
    struct Shelf {
        let y: Int
        let height: Int
        var currentX: Int
        let width: Int
    }

    /// Configuration for the atlas
    struct Configuration {
        /// Default atlas size (2048x2048 is typical)
        static let defaultSize = 2048

        /// Minimum shelf height
        static let minShelfHeight = 8

        /// Padding around glyphs
        static let padding = 1
    }

    /// Initialize a new glyph atlas
    init(device: MTLDevice, size: Int = Configuration.defaultSize) {
        self.device = device
        self.size = size

        createTexture()
    }

    /// Create the Metal texture
    private func createTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        // Use shared storage mode to allow direct CPU uploads
        descriptor.storageMode = .shared

        guard let newTexture = device.makeTexture(descriptor: descriptor) else { return }
        texture = newTexture

        // Clear the texture to transparent black
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        let totalBytes = size * bytesPerRow

        guard let clearData = malloc(totalBytes) else { return }
        defer { free(clearData) }
        memset(clearData, 0, totalBytes)

        let region = MTLRegionMake2D(0, 0, size, size)
        newTexture.replace(region: region, mipmapLevel: 0, withBytes: clearData, bytesPerRow: bytesPerRow)
    }

    /// Allocate space in the atlas
    /// - Parameters:
    ///   - width: Width needed
    ///   - height: Height needed
    /// - Returns: The rect where the glyph should be placed, or nil if no space
    func allocate(width: Int, height: Int) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }

        let paddedWidth = width + Configuration.padding * 2
        let paddedHeight = height + Configuration.padding * 2

        // Try to find an existing shelf
        for i in 0..<shelves.count {
            let shelf = shelves[i]
            if shelf.height >= paddedHeight && shelf.currentX + paddedWidth <= size {
                let rect = CGRect(
                    x: CGFloat(shelf.currentX + Configuration.padding),
                    y: CGFloat(shelf.y + Configuration.padding),
                    width: CGFloat(width),
                    height: CGFloat(height)
                )
                shelves[i].currentX += paddedWidth
                return rect
            }
        }

        // Create a new shelf
        if currentY + paddedHeight > size {
            return nil // No more space
        }

        let newShelf = Shelf(
            y: currentY,
            height: paddedHeight,
            currentX: paddedWidth,
            width: size
        )
        shelves.append(newShelf)

        let rect = CGRect(
            x: CGFloat(Configuration.padding),
            y: CGFloat(currentY + Configuration.padding),
            width: CGFloat(width),
            height: CGFloat(height)
        )

        currentY += paddedHeight

        return rect
    }

    /// Clear the atlas and reset allocation
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        shelves.removeAll()
        currentY = 0

        // Recreate texture to clear contents
        createTexture()
    }

    /// Upload glyph pixel data to the atlas
    /// - Parameters:
    ///   - pixelData: The raw pixel data (RGBA, premultiplied last)
    ///   - width: Width of the glyph
    ///   - height: Height of the glyph
    ///   - bytesPerRow: Bytes per row in the pixel data
    ///   - rect: The location in the atlas
    ///   - commandBuffer: The command buffer (not used for shared storage)
    func upload(pixelData: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, at rect: CGRect, commandBuffer: MTLCommandBuffer) {
        guard let texture = texture else { return }

        // For shared storage, use synchronous replaceRegion
        let region = MTLRegionMake2D(Int(rect.origin.x), Int(rect.origin.y), width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: pixelData, bytesPerRow: bytesPerRow)
    }

    /// Get the UV coordinates for a rect in the atlas
    /// - Parameter rect: The rect in the atlas
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
