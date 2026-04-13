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
    /// Metal shader source code (compiled at runtime for Swift Package Manager compatibility)
    private static let shaderSource = """
        #include <metal_stdlib>
        #include <simd/simd.h>

        using namespace metal;

        struct VertexUniforms {
            float4x4 projectionMatrix;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
            float4 fgColor;
            float4 bgColor;
            float flags;
        };

        struct TerminalVertex {
            float2 position;
            float2 uv;
            float4 fgColor;
            float4 bgColor;
            float flags;
        };

        vertex VertexOut background_vertex(
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

        float3 srgb_to_linear(float3 srgb) {
            float3 linear;
            for (int i = 0; i < 3; i++) {
                if (srgb[i] <= 0.04045) {
                    linear[i] = srgb[i] / 12.92;
                } else {
                    linear[i] = pow((srgb[i] + 0.055) / 1.055, 2.4);
                }
            }
            return linear;
        }

        float3 linear_to_srgb(float3 linear) {
            float3 srgb;
            for (int i = 0; i < 3; i++) {
                float rgb = max(1.055 * linear[i] - 0.055, 0.0);
                srgb[i] = min(rgb, 1.0);
            }
            return srgb;
        }

        vertex VertexOut glyph_vertex(
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

        fragment float4 glyph_fragment(
            VertexOut in [[stage_in]],
            texture2d<float> atlas [[texture(0)]],
            sampler atlasSampler [[sampler(0)]])
        {
            float4 glyphColor = atlas.sample(atlasSampler, in.uv);
            float alpha = glyphColor.a;
            // Output true text color with alpha so Metal hardware blending blends it over the background and selection
            return float4(in.fgColor.rgb, alpha * in.fgColor.a);
        }

        vertex VertexOut decoration_vertex(
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

        fragment float4 decoration_fragment(VertexOut in [[stage_in]]) {
            return in.fgColor;
        }

        """

    /// The Metal device
    public let device: MTLDevice

    /// The command queue
    public let commandQueue: MTLCommandQueue

    /// Pipeline states for different render passes
    private var backgroundPipelineState: MTLRenderPipelineState?
    private var glyphPipelineState: MTLRenderPipelineState?
    private var decorationPipelineState: MTLRenderPipelineState?

    /// Sampler state for texture sampling
    private var samplerState: MTLSamplerState?

    /// The cell renderer
    let cellRenderer: TerminalCellRenderer

    /// Vertex buffers (double-buffered)
    private var vertexBuffers: [MTLBuffer] = []

    /// Current vertex buffer index
    private var currentVertexBufferIndex: Int = 0

    /// Projection matrix
    private var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4

    /// The terminal being rendered
    public weak var terminal: Terminal?

    /// Font set for rendering
    var fontSet: FontSet?

    /// Cell dimension
    public var cellDimension: CGSize = .zero

    /// Selection service
    internal weak var selection: SelectionService?

    /// Scale factor
    public var scale: CGFloat = 1.0

    private var dirtyRect: CGRect? = nil
    private var lastRenderedCols: Int = -1
    private var lastRenderedRows: Int = -1
    private var lastRenderedYDisp: Int = -1
    private var rowCache: [CachedRowVertices] = []
    private var cachedSelectionVertices: [TerminalVertex] = []
    private var cachedCursorVertices: [TerminalVertex] = []
    private var dirtyRows = IndexSet()
    private var needsFullRebuild = true
    private var needsSelectionRebuild = true
    private var needsCursorRebuild = true

    /// Controls cursor visibility for blinking animation
    public var cursorVisible: Bool = true

    /// Selection highlight color propagated to the cell renderer
    public var selectionColor: SIMD4<Float> {
        get { cellRenderer.selectionColor }
        set { cellRenderer.selectionColor = newValue }
    }

    private var frameCount: Int = 0
    private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var frameTimes: [CFTimeInterval] = []

    /// Edge smoothness for anti-aliasing (0.0-1.0 range)
    public var edgeSmoothness: Float = 0.1

    /// Enable sRGB/gamma corrected color blending
    public var enableColorCorrection: Bool = true

    /// Use scissor test for dirty rectangle optimization
    public var useDirtyRectOptimization: Bool = true

    /// Whether to use bright colors for bold
    public var useBrightColors: Bool = true

    /// Performance metrics
    public var frameRate: Double = 0.0
    public var averageFrameTime: CFTimeInterval = 0.0

    /// Enable performance profiling
    public var enableProfiling: Bool = false

    /// Initialize a new terminal renderer
    init?(device: MTLDevice, terminal: Terminal, fontSet: FontSet, cellDimension: CGSize, scale: CGFloat) {
        self.device = device
        self.terminal = terminal
        self.fontSet = fontSet
        self.cellDimension = cellDimension
        self.scale = scale

        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue

        // Create cell renderer
        self.cellRenderer = TerminalCellRenderer(device: device, commandQueue: commandQueue, scale: scale)

        super.init()

        // Create pipeline states
        createPipelineStates()

        // Create sampler state
        createSamplerState()

        // Create vertex buffers
        createVertexBuffers()
    }

    /// Create the sampler state for texture sampling
    private func createSamplerState() {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: descriptor)
    }

    /// Create the pipeline states
    private func createPipelineStates() {
        // Compile shaders from source to ensure they work with Swift Package Manager
        let library: MTLLibrary?
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            print("TerminalRenderer: Failed to compile shaders: \(error)")
            return
        }

        guard let library = library else {
            print("TerminalRenderer: Failed to create shader library")
            return
        }

        // Background pipeline
        let backgroundDescriptor = MTLRenderPipelineDescriptor()
        backgroundDescriptor.label = "Background Pipeline"
        backgroundDescriptor.vertexFunction = library.makeFunction(name: "background_vertex")
        backgroundDescriptor.fragmentFunction = library.makeFunction(name: "background_fragment")
        backgroundDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        backgroundDescriptor.colorAttachments[0].isBlendingEnabled = true
        backgroundDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        backgroundDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        do {
            backgroundPipelineState = try device.makeRenderPipelineState(descriptor: backgroundDescriptor)
        } catch {
            print("TerminalRenderer: Failed to create background pipeline state: \(error)")
        }

        // Glyph pipeline
        let glyphDescriptor = MTLRenderPipelineDescriptor()
        glyphDescriptor.label = "Glyph Pipeline"
        glyphDescriptor.vertexFunction = library.makeFunction(name: "glyph_vertex")
        glyphDescriptor.fragmentFunction = library.makeFunction(name: "glyph_fragment")
        glyphDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        glyphDescriptor.colorAttachments[0].isBlendingEnabled = true
        glyphDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glyphDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        do {
            glyphPipelineState = try device.makeRenderPipelineState(descriptor: glyphDescriptor)
        } catch {
            print("TerminalRenderer: Failed to create glyph pipeline state: \(error)")
        }

        // Decoration pipeline
        let decorationDescriptor = MTLRenderPipelineDescriptor()
        decorationDescriptor.label = "Decoration Pipeline"
        decorationDescriptor.vertexFunction = library.makeFunction(name: "decoration_vertex")
        decorationDescriptor.fragmentFunction = library.makeFunction(name: "decoration_fragment")
        decorationDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        decorationDescriptor.colorAttachments[0].isBlendingEnabled = true
        decorationDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        decorationDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        do {
            decorationPipelineState = try device.makeRenderPipelineState(descriptor: decorationDescriptor)
        } catch {
            print("TerminalRenderer: Failed to create decoration pipeline state: \(error)")
        }

    }

    /// Create vertex buffers
    private func createVertexBuffers() {
        // Create initial buffers
        for _ in 0..<3 {
            if let buffer = device.makeBuffer(length: 1024 * 1024, options: .storageModeShared) {
                vertexBuffers.append(buffer)
            }
        }
    }

    /// Update projection matrix for the given size
    public func updateProjectionMatrix(size: CGSize) {
        // Create an orthographic projection matrix
        // Origin at top-left, Y pointing down
        let left: Float = 0
        let right: Float = Float(size.width)
        let top: Float = 0
        let bottom: Float = Float(size.height)
        let near: Float = -1
        let far: Float = 1

        projectionMatrix = matrix_float4x4(
            SIMD4<Float>(2.0 / (right - left), 0, 0, 0),
            SIMD4<Float>(0, 2.0 / (top - bottom), 0, 0),
            SIMD4<Float>(0, 0, -2.0 / (far - near), 0),
            SIMD4<Float>(
                -(right + left) / (right - left),
                -(top + bottom) / (top - bottom),
                -(far + near) / (far - near),
                1
            )
        )
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateProjectionMatrix(size: view.bounds.size)
    }

    public func draw(in view: MTKView) {
        guard let terminal = terminal,
              let fontSet = fontSet,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        updateProjectionMatrix(size: view.bounds.size)

        rebuildCachesIfNeeded(terminal: terminal, fontSet: fontSet, commandBuffer: commandBuffer)
        let builder = composeCachedFrame()

        // Debug: log render state for diagnosing invisible pasted text
        #if DEBUG
        let debugFgColor = terminal.foregroundColor
        let debugBgColor = terminal.backgroundColor
        NSLog("[SwiftTerm] draw(in:) glyphs=%d bgVerts=%d fg(r=%d,g=%d,b=%d) bg(r=%d,g=%d,b=%d)",
              builder.glyphVertices.count, builder.backgroundVertices.count,
              debugFgColor.red, debugFgColor.green, debugFgColor.blue,
              debugBgColor.red, debugBgColor.green, debugBgColor.blue)
        #endif

        guard let descriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            // No drawable available — caches were already rebuilt but the frame was not
            // presented.  Schedule a retry on the next display cycle so the content
            // doesn't remain stale (e.g. invisible pasted text).
            (view as? MetalTerminalView)?.setTerminalNeedsDisplay()
            return
        }

        // Clear with terminal background color
        let bgColor = terminal.backgroundColor
        let clearR = Double(bgColor.red) / 65535.0
        let clearG = Double(bgColor.green) / 65535.0
        let clearB = Double(bgColor.blue) / 65535.0
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: clearR, green: clearG, blue: clearB, alpha: 1.0)
        descriptor.colorAttachments[0].loadAction = .clear

        var uniforms = VertexUniforms(projectionMatrix: projectionMatrix)

        func createVertexBuffer(_ vertices: [TerminalVertex]) -> MTLBuffer? {
            guard !vertices.isEmpty else { return nil }
            let size = vertices.count * MemoryLayout<TerminalVertex>.stride
            return device.makeBuffer(bytes: vertices, length: size, options: .storageModeShared)
        }

        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 1)

        // Draw backgrounds
        if !builder.backgroundVertices.isEmpty, let pipelineState = backgroundPipelineState,
           let vertexBuffer = createVertexBuffer(builder.backgroundVertices) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: builder.backgroundVertices.count)
        }

        // Draw selection
        if !builder.selectionVertices.isEmpty, let pipelineState = backgroundPipelineState,
           let vertexBuffer = createVertexBuffer(builder.selectionVertices) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: builder.selectionVertices.count)
        }

        // Draw glyphs
        if !builder.glyphVertices.isEmpty, let pipelineState = glyphPipelineState,
           let vertexBuffer = createVertexBuffer(builder.glyphVertices) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            if let texture = cellRenderer.glyphCache.atlasTexture(at: 0) {
                renderEncoder.setFragmentTexture(texture, index: 0)
            }
            if let sampler = samplerState {
                renderEncoder.setFragmentSamplerState(sampler, index: 0)
            }
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: builder.glyphVertices.count)
        }

        // Draw decorations
        if !builder.decorationVertices.isEmpty, let pipelineState = decorationPipelineState,
           let vertexBuffer = createVertexBuffer(builder.decorationVertices) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: builder.decorationVertices.count)
        }

        // Draw cursor
        if !builder.cursorVertices.isEmpty, let pipelineState = decorationPipelineState,
           let vertexBuffer = createVertexBuffer(builder.cursorVertices) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: builder.cursorVertices.count)
        }

        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }

    private func calculateDirtyRect() -> CGRect? {
        guard let terminal = terminal else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(cellDimension.width) * CGFloat(terminal.cols), height: CGFloat(cellDimension.height) * CGFloat(terminal.rows))
        guard let rect = dirtyRect else {
            return nil
        }
        return CGRectIntersection(bounds, rect)
    }

    /// Update the terminal and font references
    func update(terminal: Terminal, fontSet: FontSet, cellDimension: CGSize, scale: CGFloat) {
        let scaleChanged = self.scale != scale
        self.terminal = terminal
        self.fontSet = fontSet
        self.cellDimension = cellDimension
        self.scale = scale
        cellRenderer.scale = scale
        if scaleChanged {
            cellRenderer.glyphCache.updateScale(scale)
        }
        // Reset cached dimensions to force full redraw
        lastRenderedCols = -1
        lastRenderedRows = -1
        lastRenderedYDisp = -1
        needsFullRebuild = true
    }

    /// Clear cached data
    public func clearCache() {
        cellRenderer.clearCache()
        rowCache.removeAll()
        cachedSelectionVertices.removeAll()
        cachedCursorVertices.removeAll()
        lastRenderedYDisp = -1
        needsFullRebuild = true
        needsSelectionRebuild = true
        needsCursorRebuild = true
    }

    func markAllDirty(reason: String = "markAllDirty") {
        needsFullRebuild = true
        needsSelectionRebuild = true
        needsCursorRebuild = true
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
    }

    func markSelectionDirty() {
        needsSelectionRebuild = true
    }

    func markCursorDirty() {
        needsCursorRebuild = true
    }

    /// Set cursor visibility for blinking animation
    public func setCursorVisible(_ visible: Bool) {
        cursorVisible = visible
        needsCursorRebuild = true
    }

    private func rebuildCachesIfNeeded(terminal: Terminal, fontSet: FontSet, commandBuffer: MTLCommandBuffer) {
        let rows = terminal.rows
        let cols = terminal.cols
        let yDisp = terminal.displayBuffer.yDisp

        if needsFullRebuild || rowCache.count != rows || lastRenderedCols != cols || lastRenderedRows != rows || lastRenderedYDisp != yDisp {
            rowCache = Array(repeating: CachedRowVertices(), count: rows)
            dirtyRows = rows > 0 ? IndexSet(integersIn: 0..<rows) : IndexSet()
            needsFullRebuild = false
            lastRenderedCols = cols
            lastRenderedRows = rows
            lastRenderedYDisp = yDisp
            needsSelectionRebuild = true
            needsCursorRebuild = true
        }

        cellRenderer.prepareFrame(terminal: terminal)

        if !dirtyRows.isEmpty {
            for row in dirtyRows {
                rowCache[row] = cellRenderer.buildRowVertices(
                    terminal: terminal,
                    fontSet: fontSet,
                    cellDimension: cellDimension,
                    row: row,
                    commandBuffer: commandBuffer
                )
            }
            self.dirtyRows.removeAll()
        }

        if needsSelectionRebuild {
            cachedSelectionVertices = cellRenderer.buildSelectionVertices(
                terminal: terminal,
                cellDimension: cellDimension,
                selection: selection
            )
            needsSelectionRebuild = false
        }
        if needsCursorRebuild {
            cachedCursorVertices = cellRenderer.buildCursorVertices(
                terminal: terminal,
                cellDimension: cellDimension
            )
            // Apply cursor visibility for blinking animation
            if !cursorVisible {
                cachedCursorVertices = []
            }
            needsCursorRebuild = false
        }
    }

    private func composeCachedFrame() -> VertexBufferBuilder {
        let builder = VertexBufferBuilder()
        builder.selectionVertices = cachedSelectionVertices
        builder.cursorVertices = cachedCursorVertices

        for row in rowCache {
            builder.backgroundVertices.append(contentsOf: row.backgroundVertices)
            builder.glyphVertices.append(contentsOf: row.glyphVertices)
            builder.decorationVertices.append(contentsOf: row.decorationVertices)
        }

        return builder
    }
}

/// Uniforms for vertex shaders
struct VertexUniforms {
    var projectionMatrix: matrix_float4x4
}
#endif
