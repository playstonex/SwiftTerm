//
//  Shaders.metal
//  SwiftTerm
//
//  Metal shaders for terminal rendering.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Vertex structure for terminal rendering
struct TerminalVertex {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float4 fgColor [[attribute(2)]];
    float4 bgColor [[attribute(3)]];
    float flags [[attribute(4)]];  // 0=normal, 1=cursor, 2=selection
};

// Vertex output
struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 fgColor;
    float4 bgColor;
    float flags;
};

// Uniforms for vertex shader
struct VertexUniforms {
    float4x4 projectionMatrix;
};

// Vertex shader for background quads
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

// Fragment shader for background quads
fragment float4 background_fragment(VertexOut in [[stage_in]])
{
    return in.bgColor;
}

// Vertex shader for glyph quads
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

// Fragment shader for glyph quads
fragment float4 glyph_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]],
    sampler atlasSampler [[sampler(0)]])
{
    float4 glyphColor = atlas.sample(atlasSampler, in.uv);
    // Use the glyph as a mask with foreground color
    return float4(in.fgColor.rgb, glyphColor.a * in.fgColor.a);
}

// Vertex shader for decoration quads (underline, strikethrough)
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

// Fragment shader for decoration quads
fragment float4 decoration_fragment(VertexOut in [[stage_in]])
{
    return in.fgColor;
}

// Vertex shader for cursor
vertex VertexOut cursor_vertex(
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

// Fragment shader for cursor
fragment float4 cursor_fragment(VertexOut in [[stage_in]])
{
    return in.bgColor;
}

// Vertex shader for selection
vertex VertexOut selection_vertex(
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

// Fragment shader for selection
fragment float4 selection_fragment(VertexOut in [[stage_in]])
{
    return in.bgColor;
}
