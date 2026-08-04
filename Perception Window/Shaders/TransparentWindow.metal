#include <metal_stdlib>
using namespace metal;

struct WindowVertex {
    float2 position;
    float2 cameraUV;
    float valid;
    float padding;
};

struct WindowVertexOut {
    float4 position [[position]];
    float2 cameraUV;
    float valid;
};

struct FullscreenUniforms {
    float3x3 inverseDisplayTransform;
    float2 parallaxOffset;
    float2 viewportSize;
    float windowMagnification;
    float padding;
};

vertex WindowVertexOut transparentWindowVertex(
    uint vid [[vertex_id]],
    constant WindowVertex *vertices [[buffer(0)]],
    constant ushort *indices [[buffer(1)]]
) {
    WindowVertex in = vertices[indices[vid]];
    WindowVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.cameraUV = in.cameraUV;
    out.valid = in.valid;
    return out;
}

fragment float4 transparentWindowFragment(
    WindowVertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]]
) {
    if (in.valid < 0.5) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    return cameraTexture.sample(textureSampler, in.cameraUV);
}

struct FullscreenVertexOut {
    float4 position [[position]];
};

vertex float4 transparentWindowFullscreenVertex(uint vid [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0),
    };

    return float4(positions[vid], 0.0, 1.0);
}

fragment float4 transparentWindowFullscreenFragment(
    float4 position [[position]],
    constant FullscreenUniforms &uniforms [[buffer(0)]],
    texture2d<float> cameraTexture [[texture(0)]]
) {
    // ARKit displayTransform expects UIKit-normalized view coords (origin upper-left).
    float2 viewNorm = position.xy / uniforms.viewportSize;
    float3 mapped = uniforms.inverseDisplayTransform * float3(viewNorm, 1.0);
    float mag = max(uniforms.windowMagnification, 1.0);
    float2 cameraUV = (mapped.xy - 0.5) / mag + 0.5;
    cameraUV += uniforms.parallaxOffset * mag;

    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    return cameraTexture.sample(textureSampler, clamp(cameraUV, 0.0, 1.0));
}
