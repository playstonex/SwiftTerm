//
//  Shaders.metal
//  SwiftTerm
//
//  Metal shaders for terminal rendering.
//
//  This file is the single source of truth for the terminal shaders. It is
//  compiled by Swift Package Manager on Apple platforms and loaded through
//  `device.makeDefaultLibrary()`. TerminalRenderer keeps a runtime-source
//  fallback (kept in sync with this file) for toolchains that do not embed a
//  default library.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Vertex structure for terminal rendering. Must match the Swift
// `TerminalVertex` layout in VertexBufferBuilder.swift: float2 position,
// float2 uv, float4 fg, float4 bg, float flags -> 56 byte stride.
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

// Shared vertex shader for every terminal render pass.
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

// Opaque color fill for background and selection quads.
fragment float4 background_fragment(VertexOut in [[stage_in]])
{
    return in.bgColor;
}

// Monochrome glyph: sample the alpha mask and tint it with the cell's
// foreground color. The atlas stores grayscale coverage in alpha only.
fragment float4 glyph_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]],
    sampler atlasSampler [[sampler(0)]])
{
    float4 glyphColor = atlas.sample(atlasSampler, in.uv);
    return float4(in.fgColor.rgb, glyphColor.a * in.fgColor.a);
}

// Color glyph (emoji and other color-bitmap font glyphs): the atlas stores
// premultiplied RGBA, so unpremultiply before the standard source-alpha
// blending used by every other pass.
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

// Solid fill for underline / strikethrough / cursor quads.
fragment float4 decoration_fragment(VertexOut in [[stage_in]])
{
    return in.fgColor;
}
