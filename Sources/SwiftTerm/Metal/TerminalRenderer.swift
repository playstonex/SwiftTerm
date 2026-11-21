//
//  TerminalRenderer.swift
//  SwiftTerm
//
//  Metal renderer for terminal content.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import Metal
import MetalKit
import CoreText
import simd

/// Renders terminal content using Metal
public class TerminalRenderer: NSObject, MTKViewDelegate {
    /// Fallback shader source, kept in sync with Shaders.metal. Used when the
    /// toolchain did not embed a compiled default library for the package.
    private static let fallbackShaderSource = """
        #include <metal_stdlib>
        #include <simd/simd.h>

        using namespace metal;

        struct TerminalVertex {
            float2 position;
            float2 uv;
            float4 fgColor;
            float4 bgColor;
            float flags;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
            float4 fgColor;
            float4 bgColor;
            float flags;
        };

        struct VertexUniforms {
            float4x4 projectionMatrix;
        };

        vertex VertexOut terminal_vertex(
            device const TerminalVertex* vertices [[buffer(0)]],
            constant VertexUniforms& uniforms [[buffer(1)]],
            uint vid [[vertex_id]])
        {
            VertexOut out;
            out.position = uniforms.projectionMatrix * float4(vertices[vid].position, 0.0, 1.0);
            out.uv = vertices[vid].uv;
            out.fgColor = vertices[vid].fgColor;
            out.bgColor = vertices[vid].bgColor;
            out.flags = vertices[vid].flags;
            return out;
        }

        fragment float4 background_fragment(VertexOut in [[stage_in]]) {
            return in.bgColor;
        }

        fragment float4 glyph_fragment(
            VertexOut in [[stage_in]],
            texture2d<float> atlas [[texture(0)]],
            sampler atlasSampler [[sampler(0)]])
        {
            float4 glyphColor = atlas.sample(atlasSampler, in.uv);
            return float4(in.fgColor.rgb, glyphColor.a * in.fgColor.a);
        }

        fragment float4 color_glyph_fragment(
            VertexOut in [[stage_in]],
            texture2d<float> atlas [[texture(0)]],
            sampler atlasSampler [[sampler(0)]])
        {
            float4 glyphColor = atlas.sample(atlasSampler, in.uv);
            float alpha = glyphColor.a;
            if (alpha <= 0.0001) {
                return float4(0.0, 0.0, 0.0, 0.0);
            }
            return float4(glyphColor.rgb / alpha, alpha);
        }

        fragment float4 decoration_fragment(VertexOut in [[stage_in]]) {
            return in.fgColor;
        }
        """

    /// The Metal device
    public let device: MTLDevice

    /// The command queue
    public let commandQueue: MTLCommandQueue

    /// Pipeline states for the render passes
    private var backgroundPipelineState: MTLRenderPipelineState?
    private var glyphPipelineState: MTLRenderPipelineState?
    private var colorGlyphPipelineState: MTLRenderPipelineState?
    private var decorationPipelineState: MTLRenderPipelineState?

    /// Sampler state for texture sampling
    private var samplerState: MTLSamplerState?

    /// The cell renderer
    let cellRenderer: TerminalCellRenderer

    /// Round-robin upload arenas replacing per-frame MTLBuffer allocation.
    /// Three slots keep at least three frames of GPU reads in flight safe.
    private var arenas: [MTLBuffer] = []
    private var arenaSlot = 0
    private var arenaWriteOffset = 0

    /// Projection matrix
    private var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4

    /// The terminal being rendered
    public weak var terminal: Terminal?

    /// Owning view, used to schedule redraws (glyph-cache resets, blink).
    weak var metalView: MetalTerminalView?

    /// Font set for rendering
    var fontSet: FontSet?
    private var lastFontID: ObjectIdentifier?

    /// Cell dimension
    public var cellDimension: CGSize = .zero

    /// Selection service
    internal weak var selection: SelectionService?

    /// Scale factor
    public var scale: CGFloat = 1.0

    private var lastRenderedCols: Int = -1
    private var lastRenderedRows: Int = -1
    private var lastRenderedYDisp: Int = -1
    private var rowCache: [CachedRowVertices] = []
    private var cachedSelectionVertices: [TerminalVertex] = []
    private var cursorOverlays: (on: CursorOverlay, off: CursorOverlay)?
    private var cachedMarkedTextVertices = CachedRowVertices()
    private var dirtyRows = IndexSet()
    private var needsFullRebuild = true
    private var needsSelectionRebuild = true
    private var needsCursorRebuild = true
    private var needsMarkedTextRebuild = true
    private var markedTextOverlay: MarkedTextOverlay?

    private struct MarkedTextOverlay {
        let text: String
        let selectedLocation: Int
        let selectedLength: Int
    }

    /// Controls cursor visibility for blinking animation
    public var cursorVisible: Bool = true

    /// Set while a frame should only repaint the cursor cell (blink toggle
    /// on an otherwise clean frame).
    private var blinkOnlyFramePending = false

    /// Selection highlight color propagated to the cell renderer
    public var selectionColor: SIMD4<Float> {
        get { cellRenderer.selectionColor }
        set { cellRenderer.selectionColor = newValue }
    }

    /// Block cursor fill / text colors propagated to the cell renderer
    public var caretColor: SIMD4<Float> {
        get { cellRenderer.caretColor }
        set { cellRenderer.caretColor = newValue }
    }

    public var caretTextColor: SIMD4<Float> {
        get { cellRenderer.caretTextColor }
        set { cellRenderer.caretTextColor = newValue }
    }

    /// Whether bold text also uses the bright palette entries
    public var useBrightColors: Bool {
        get { cellRenderer.useBrightColors }
        set { cellRenderer.useBrightColors = newValue }
    }

    /// Top inset used to keep live content below translucent chrome.
    var topContentInset: CGFloat = 0

    /// Bottom inset used to keep live content above translucent chrome while
    /// still allowing manually scrolled content to pass behind it.
    var bottomContentInset: CGFloat = 0

    /// Initialize a new terminal renderer
    init?(device: MTLDevice, terminal: Terminal, fontSet: FontSet, cellDimension: CGSize, scale: CGFloat) {
        self.device = device
        self.terminal = terminal
        self.fontSet = fontSet
        self.lastFontID = ObjectIdentifier(fontSet.normal)
        self.cellDimension = cellDimension
        self.scale = scale

        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue

        // Create cell renderer
        self.cellRenderer = TerminalCellRenderer(device: device, scale: scale)

        super.init()

        cellRenderer.glyphCache.onCacheReset = { [weak self] in
            self?.handleGlyphCacheReset()
        }

        // Create pipeline states
        createPipelineStates()

        // Create sampler state
        createSamplerState()

        // Create vertex arenas
        createArenas()
    }

    /// Every cached glyph was invalidated (all atlases filled up); rebuild all
    /// vertex caches before the next frame so no cell is silently skipped.
    private func handleGlyphCacheReset() {
        markAllDirty(reason: "glyphCacheReset")
        metalView?.setTerminalNeedsDisplay()
    }

    /// Create the sampler state for texture sampling
    private func createSamplerState() {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: descriptor)
    }

    private func loadShaderLibrary() -> MTLLibrary? {
        // Shaders.metal is the single source of truth. SwiftPM compiles it
        // into the package resource bundle's default.metallib, so prefer that
        // and fall back to a runtime compile only when no library was embedded.
        if let library = try? device.makeDefaultLibrary(bundle: Bundle(for: TerminalRenderer.self)),
           library.makeFunction(name: "terminal_vertex") != nil {
            return library
        }
        if let library = try? device.makeDefaultLibrary(),
           library.makeFunction(name: "terminal_vertex") != nil {
            return library
        }
        do {
            return try device.makeLibrary(source: Self.fallbackShaderSource, options: nil)
        } catch {
            print("TerminalRenderer: Failed to compile shaders: \(error)")
            return nil
        }
    }

    /// Create the pipeline states
    private func createPipelineStates() {
        guard let library = loadShaderLibrary() else {
            print("TerminalRenderer: No shader library available")
            return
        }

        func makePipeline(label: String, vertex: String, fragment: String) -> MTLRenderPipelineState? {
            guard let vertexFunction = library.makeFunction(name: vertex),
                  let fragmentFunction = library.makeFunction(name: fragment) else {
                print("TerminalRenderer: Shader function not found: \(vertex) / \(fragment)")
                return nil
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                print("TerminalRenderer: Failed to create \(label) pipeline state: \(error)")
                return nil
            }
        }

        backgroundPipelineState = makePipeline(label: "Background Pipeline", vertex: "terminal_vertex", fragment: "background_fragment")
        glyphPipelineState = makePipeline(label: "Glyph Pipeline", vertex: "terminal_vertex", fragment: "glyph_fragment")
        colorGlyphPipelineState = makePipeline(label: "Color Glyph Pipeline", vertex: "terminal_vertex", fragment: "color_glyph_fragment")
        decorationPipelineState = makePipeline(label: "Decoration Pipeline", vertex: "terminal_vertex", fragment: "decoration_fragment")
    }

    /// Create the round-robin vertex upload arenas
    private func createArenas() {
        arenas = (0..<3).compactMap { _ in
            device.makeBuffer(length: 1 << 20, options: .storageModeShared)
        }
    }

    /// Advance to the next arena slot for this frame.
    private func beginArenaFrame() {
        guard !arenas.isEmpty else { return }
        arenaSlot = (arenaSlot + 1) % arenas.count
        arenaWriteOffset = 0
    }

    private struct ArenaSlice {
        let buffer: MTLBuffer
        let offset: Int
        let vertexCount: Int
    }

    /// Copy vertices into the current arena, growing it when needed.
    private func appendToArena(_ vertices: [TerminalVertex]) -> ArenaSlice? {
        guard !vertices.isEmpty, !arenas.isEmpty else { return nil }

        let stride = MemoryLayout<TerminalVertex>.stride
        let byteCount = vertices.count * stride
        var offset = (arenaWriteOffset + 255) & ~255
        var buffer = arenas[arenaSlot]

        if offset + byteCount > buffer.length {
            let newLength = max(byteCount, buffer.length * 2)
            guard let grown = device.makeBuffer(length: newLength, options: .storageModeShared) else {
                return nil
            }
            arenas[arenaSlot] = grown
            buffer = grown
            offset = 0
        }

        vertices.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(buffer.contents() + offset, base, byteCount)
            }
        }
        arenaWriteOffset = offset + byteCount
        return ArenaSlice(buffer: buffer, offset: offset, vertexCount: vertices.count)
    }

    /// Update projection matrix for the given size.
    ///
    /// `yOffset` shifts content down by the top content inset; it replaces
    /// the old per-vertex offset pass.
    public func updateProjectionMatrix(size: CGSize, yOffset: CGFloat = 0) {
        // Create an orthographic projection matrix
        // Origin at top-left, Y pointing down
        let left: Float = 0
        let right: Float = Float(size.width)
        let top: Float = 0
        let bottom: Float = Float(size.height)
        let near: Float = -1
        let far: Float = 1
        let yScale = 2.0 / (top - bottom)

        projectionMatrix = matrix_float4x4(
            SIMD4<Float>(2.0 / (right - left), 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, -2.0 / (far - near), 0),
            SIMD4<Float>(
                -(right + left) / (right - left),
                -(top + bottom) / (top - bottom) + yScale * Float(yOffset),
                -(far + near) / (far - near),
                1
            )
        )
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // draw() recomputes the projection (with content offset) every frame.
    }

    public func draw(in view: MTKView) {
        guard let terminal = terminal,
              let fontSet = fontSet else {
            return
        }

        let contentOffset = contentRenderOffsetY()
        updateProjectionMatrix(size: view.bounds.size, yOffset: contentOffset)

        // Blink fast path: only the cursor visibility flipped since the last
        // frame. Caches are already valid, so skip the (cheap but pointless)
        // rebuild pass and reuse the composed base frame.
        //
        // Note the frame is still fully redrawn with loadAction .clear:
        // partial .load-style updates are unsound here because CAMetalLayer
        // rotates through a pool of drawables, and a stale pooled drawable
        // would flash old screen content.
        let skipRebuilds = blinkOnlyFramePending && canDrawBlinkOnlyFrame
        blinkOnlyFramePending = false

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        if !skipRebuilds {
            rebuildCachesIfNeeded(terminal: terminal, fontSet: fontSet)
        }

        guard let descriptor = view.currentRenderPassDescriptor else {
            metalView?.setTerminalNeedsDisplay()
            return
        }

        // Set clear color from terminal background BEFORE creating the encoder
        let bgColor = terminal.backgroundColor
        let clearR = Double(bgColor.red) / 65535.0
        let clearG = Double(bgColor.green) / 65535.0
        let clearB = Double(bgColor.blue) / 65535.0
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: clearR, green: clearG, blue: clearB, alpha: 1.0)
        descriptor.colorAttachments[0].loadAction = .clear

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            metalView?.setTerminalNeedsDisplay()
            return
        }

        var uniforms = VertexUniforms(projectionMatrix: projectionMatrix)
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 1)

        beginArenaFrame()
        let base = currentComposedBase()

        // Draw backgrounds
        drawSolidList(renderEncoder, base.background, pipeline: backgroundPipelineState)

        // Draw selection
        drawSolidList(renderEncoder, base.selection, pipeline: backgroundPipelineState)

        // Draw glyphs (batched per atlas texture and monochrome/color)
        drawGlyphBuckets(renderEncoder, base.glyphBuckets)

        // Draw decorations (underline / strikethrough / marked-text marks)
        drawSolidList(renderEncoder, base.decorations, pipeline: decorationPipelineState)

        // Draw the cursor cell: background quad then the glyph on top
        if let overlay = currentCursorOverlay {
            drawSolidList(renderEncoder, overlay.quads, pipeline: decorationPipelineState)
            drawGlyphBuckets(renderEncoder, overlay.glyphBuckets)
        }

        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }

    private var canDrawBlinkOnlyFrame: Bool {
        !needsFullRebuild && dirtyRows.isEmpty && !needsSelectionRebuild
            && markedTextOverlay == nil && !(selection?.active ?? false)
    }

    private var currentCursorOverlay: CursorOverlay? {
        guard let overlays = cursorOverlays else { return nil }
        return cursorVisible ? overlays.on : overlays.off
    }

    private func drawSolidList(
        _ encoder: MTLRenderCommandEncoder,
        _ vertices: [TerminalVertex],
        pipeline: MTLRenderPipelineState?
    ) {
        guard !vertices.isEmpty, let pipeline, let slice = appendToArena(vertices) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(slice.buffer, offset: slice.offset, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: slice.vertexCount)
    }

    private func drawGlyphBuckets(_ encoder: MTLRenderCommandEncoder, _ buckets: GlyphBucketList) {
        guard let sampler = samplerState else { return }

        for bucket in buckets.buckets where !bucket.vertices.isEmpty {
            let pipeline = bucket.key.isColor ? colorGlyphPipelineState : glyphPipelineState
            guard let pipeline, let slice = appendToArena(bucket.vertices) else {
                continue
            }
            guard let texture = cellRenderer.glyphCache.atlasTexture(at: bucket.key.atlasIndex) else {
                continue
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(slice.buffer, offset: slice.offset, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: slice.vertexCount)
        }
    }

    /// Update the terminal and font references
    func update(terminal: Terminal, fontSet: FontSet, cellDimension: CGSize, scale: CGFloat) {
        let scaleChanged = self.scale != scale
        let fontChanged = lastFontID != ObjectIdentifier(fontSet.normal)
        self.terminal = terminal
        self.fontSet = fontSet
        self.lastFontID = ObjectIdentifier(fontSet.normal)
        self.cellDimension = cellDimension
        self.scale = scale
        cellRenderer.scale = scale
        if scaleChanged {
            cellRenderer.glyphCache.updateScale(scale)
        }
        if fontChanged {
            // A different font rasterizes every glyph differently; drop the
            // old atlas entries instead of leaking them until an atlas reset.
            cellRenderer.clearCache()
        }
        // Reset cached dimensions to force full redraw
        lastRenderedCols = -1
        lastRenderedRows = -1
        lastRenderedYDisp = -1
        needsFullRebuild = true
        needsMarkedTextRebuild = true
        composedBaseDirty = true
    }

    /// Drop cached vertex data (rows, selection, cursor, marked text) but keep
    /// the rasterized glyph atlas. Color and alternate-buffer switches only
    /// need this level.
    public func clearVertexCaches() {
        rowCache.removeAll()
        cachedSelectionVertices.removeAll()
        cursorOverlays = nil
        cachedMarkedTextVertices = CachedRowVertices()
        lastRenderedYDisp = -1
        needsFullRebuild = true
        needsSelectionRebuild = true
        needsCursorRebuild = true
        needsMarkedTextRebuild = true
        composedBase = nil
        composedBaseDirty = true
    }

    /// Clear cached data, including the glyph atlas (font or scale changed)
    public func clearCache() {
        clearVertexCaches()
        cellRenderer.clearCache()
    }

    func markAllDirty(reason: String = "markAllDirty") {
        needsFullRebuild = true
        needsSelectionRebuild = true
        needsCursorRebuild = true
        needsMarkedTextRebuild = true
    }

    func markDirtyViewportRows(startY: Int, endY: Int, terminal: Terminal) {
        let visibleStart = max(0, startY)
        let visibleEnd = min(terminal.rows - 1, endY)
        guard visibleStart <= visibleEnd else { return }
        markDirtyRows(visibleStart...visibleEnd)
    }

    func markDirtyViewportRows(_ rows: IndexSet, terminal: Terminal) {
        guard !rows.isEmpty else { return }
        var validRows = IndexSet()
        for row in rows where row >= 0 && row < terminal.rows {
            validRows.insert(row)
        }
        guard !validRows.isEmpty else { return }
        dirtyRows.formUnion(validRows)
        needsCursorRebuild = true
        needsMarkedTextRebuild = true
    }

    func markDirtyBufferRows(startY: Int, endY: Int, terminal: Terminal) {
        let visibleStart = max(0, startY - terminal.displayBuffer.yDisp)
        let visibleEnd = min(terminal.rows - 1, endY - terminal.displayBuffer.yDisp)
        guard visibleStart <= visibleEnd else { return }
        markDirtyRows(visibleStart...visibleEnd)
    }

    private func markDirtyRows(_ range: ClosedRange<Int>) {
        dirtyRows.insert(integersIn: range)
        needsCursorRebuild = true
        needsMarkedTextRebuild = true
    }

    func markSelectionDirty() {
        needsSelectionRebuild = true
    }

    func markCursorDirty() {
        needsCursorRebuild = true
        needsMarkedTextRebuild = true
    }

    /// Toggle cursor visibility for the blinking animation. When the rest of
    /// the frame is clean this only swaps the cached overlay and reuses the
    /// composed base, so a blink costs an arena upload and a GPU redraw —
    /// no row rebuilds and no cache invalidation.
    public func setCursorVisible(_ visible: Bool) {
        cursorVisible = visible
        if cursorOverlays != nil && canDrawBlinkOnlyFrame {
            blinkOnlyFramePending = true
        } else {
            needsCursorRebuild = true
        }
        metalView?.setTerminalNeedsDisplay()
    }

    func setMarkedTextOverlay(_ text: String?, selectedRange: NSRange) {
        let newOverlay: MarkedTextOverlay?
        if let text, !text.isEmpty {
            let textLength = (text as NSString).length
            let location = max(0, min(selectedRange.location, textLength))
            let length = max(0, min(selectedRange.length, textLength - location))
            newOverlay = MarkedTextOverlay(text: text, selectedLocation: location, selectedLength: length)
        } else {
            newOverlay = nil
        }

        let isSameOverlay = markedTextOverlay?.text == newOverlay?.text
            && markedTextOverlay?.selectedLocation == newOverlay?.selectedLocation
            && markedTextOverlay?.selectedLength == newOverlay?.selectedLength
        guard !isSameOverlay else { return }

        markedTextOverlay = newOverlay
        needsMarkedTextRebuild = true
        needsCursorRebuild = true
    }

    private func rebuildCachesIfNeeded(terminal: Terminal, fontSet: FontSet) {
        let rows = renderedRowCount(for: terminal)
        let cols = terminal.cols
        let yDisp = terminal.displayBuffer.yDisp
        var baseChanged = false

        if needsFullRebuild || rowCache.count != rows || lastRenderedCols != cols || lastRenderedRows != rows || lastRenderedYDisp != yDisp {
            rowCache = Array(repeating: CachedRowVertices(), count: rows)
            dirtyRows = rows > 0 ? IndexSet(integersIn: 0..<rows) : IndexSet()
            needsFullRebuild = false
            lastRenderedCols = cols
            lastRenderedRows = rows
            lastRenderedYDisp = yDisp
            needsSelectionRebuild = true
            needsCursorRebuild = true
            needsMarkedTextRebuild = true
        }

        if !dirtyRows.isEmpty {
            // Iterate over a copy: building a row can trigger a glyph-cache
            // reset that marks additional rows dirty for the next frame.
            let rowsToBuild = dirtyRows
            for row in rowsToBuild {
                guard row < rowCache.count else { continue }
                rowCache[row] = cellRenderer.buildRowVertices(
                    terminal: terminal,
                    fontSet: fontSet,
                    cellDimension: cellDimension,
                    row: row
                )
            }
            dirtyRows.subtract(rowsToBuild)
            baseChanged = true
        }

        if needsSelectionRebuild {
            cachedSelectionVertices = cellRenderer.buildSelectionVertices(
                terminal: terminal,
                cellDimension: cellDimension,
                selection: selection
            )
            needsSelectionRebuild = false
            baseChanged = true
        }
        if needsCursorRebuild {
            if markedTextOverlay != nil {
                cursorOverlays = nil
            } else {
                cursorOverlays = cellRenderer.buildCursorOverlay(
                    terminal: terminal,
                    fontSet: fontSet,
                    cellDimension: cellDimension
                )
            }
            needsCursorRebuild = false
        }

        if needsMarkedTextRebuild {
            if let markedTextOverlay {
                cachedMarkedTextVertices = cellRenderer.buildMarkedTextVertices(
                    terminal: terminal,
                    fontSet: fontSet,
                    cellDimension: cellDimension,
                    text: markedTextOverlay.text,
                    selectedLocation: markedTextOverlay.selectedLocation,
                    selectedLength: markedTextOverlay.selectedLength
                )
            } else {
                cachedMarkedTextVertices = CachedRowVertices()
            }
            needsMarkedTextRebuild = false
            baseChanged = true
        }

        if baseChanged {
            composedBaseDirty = true
        }
    }

    /// The frame minus the cursor overlay. Cached until any row, selection or
    /// marked-text cache changes, so blink toggles and cursor moves reuse it.
    private struct ComposedBase {
        var background: [TerminalVertex] = []
        var selection: [TerminalVertex] = []
        var glyphBuckets = GlyphBucketList()
        var decorations: [TerminalVertex] = []
    }

    private var composedBase: ComposedBase?
    private var composedBaseDirty = true

    private func currentComposedBase() -> ComposedBase {
        if composedBase == nil || composedBaseDirty {
            var base = ComposedBase()
            base.selection = cachedSelectionVertices

            for row in rowCache {
                base.background.append(contentsOf: row.backgroundVertices)
                base.glyphBuckets.merge(row.glyphBuckets)
                base.decorations.append(contentsOf: row.decorationVertices)
            }
            base.glyphBuckets.merge(cachedMarkedTextVertices.glyphBuckets)
            base.decorations.append(contentsOf: cachedMarkedTextVertices.decorationVertices)

            composedBase = base
            composedBaseDirty = false
        }
        return composedBase ?? ComposedBase()
    }

    private func contentRenderOffsetY() -> CGFloat {
        guard cellDimension.height > 0 else {
            return topContentInset
        }

        var offset = topContentInset
        if topContentInset > 0, let terminal {
            let buffer = terminal.displayBuffer
            let rowsAwayFromBottom = max(0, buffer.yBase - buffer.yDisp)
            offset -= min(topContentInset, CGFloat(rowsAwayFromBottom) * cellDimension.height)
        }
        return max(0, offset)
    }

    private func renderedRowCount(for terminal: Terminal) -> Int {
        let rows = terminal.rows
        guard rows > 0, cellDimension.height > 0 else {
            return rows
        }

        let buffer = terminal.displayBuffer
        let rowsAwayFromBottom = max(0, buffer.yBase - buffer.yDisp)
        guard rowsAwayFromBottom > 0 else {
            return rows
        }

        let availableRows = max(0, buffer.lines.count - buffer.yDisp)
        let maxExtraRows = max(0, availableRows - rows)
        guard maxExtraRows > 0 else {
            return rows
        }

        let releasedTopInset = topContentInset - contentRenderOffsetY()
        let extraPixelDepth = max(0, releasedTopInset + bottomContentInset)
        let requestedExtraRows = Int(ceil(extraPixelDepth / cellDimension.height))
        let extraRows = min(rowsAwayFromBottom, maxExtraRows, max(0, requestedExtraRows))
        return rows + extraRows
    }
}

/// Uniforms for vertex shaders
struct VertexUniforms {
    var projectionMatrix: matrix_float4x4
}
#endif
