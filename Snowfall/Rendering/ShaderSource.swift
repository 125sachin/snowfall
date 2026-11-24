/// Metal Shading Language source, compiled at runtime with `MTLDevice.makeLibrary(source:)`.
/// (Embedded rather than shipped as .metal files so the app builds without the optional
/// Metal Toolchain component; see docs/BUILDING.md.)
enum ShaderSource {
    static let particles = """
    #include <metal_stdlib>
    using namespace metal;

    struct ParticleInstance { float2 position; float radius; float rotation; float opacity; float seed; };
    struct ViewUniforms { float2 origin; float2 size; };
    struct ParticleOut { float4 position [[position]]; float2 uv; float opacity; float seed; float radius; };

    vertex ParticleOut particle_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                       constant ParticleInstance *inst [[buffer(0)]],
                                       constant ViewUniforms &u [[buffer(1)]]) {
        const float2 corners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
        ParticleInstance p = inst[iid];
        float2 c = corners[vid];
        float extent = p.radius * 1.7 + 0.75;
        float2 local = p.position - u.origin + c * extent;
        ParticleOut o;
        o.position = float4((local / u.size) * 2.0 - 1.0, 0.0, 1.0);
        o.uv = c * (extent / p.radius);
        o.opacity = p.opacity; o.seed = p.seed; o.radius = p.radius;
        return o;
    }

    fragment float4 particle_fragment(ParticleOut in [[stage_in]]) {
        float cs = cos(in.seed * 6.2831), sn = sin(in.seed * 6.2831);
        float2 uv = float2(in.uv.x * cs - in.uv.y * sn, in.uv.x * sn + in.uv.y * cs);
        uv.x *= 1.0 + 0.18 * sin(in.seed * 40.0);                 // slight per-flake ellipse
        float r = length(uv);
        if (in.radius > 2.4) {                                      // large flakes: faint six-lobed edge
            r += 0.10 * cos(6.0 * atan2(uv.y, uv.x)) * smoothstep(0.3, 0.9, r);
        }
        float a = smoothstep(1.0, 0.4, r) * in.opacity;
        float3 body = mix(float3(1.0), float3(0.80, 0.88, 0.98), smoothstep(0.35, 1.0, r) * 0.55);
        // Faint cool halo so flakes stay visible over white windows.
        float halo = 0.16 * smoothstep(1.7, 0.85, r) * (1.0 - a) * in.opacity;
        float3 haloColor = float3(0.40, 0.50, 0.66);
        return float4(body * a + haloColor * halo, a + halo);
    }

    struct DebugRect { float4 rect; float4 color; };
    struct DebugOut { float4 position [[position]]; float4 color; };

    vertex DebugOut debug_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                 constant DebugRect *rects [[buffer(0)]],
                                 constant ViewUniforms &u [[buffer(1)]]) {
        const float2 corners[4] = { float2(0,0), float2(1,0), float2(0,1), float2(1,1) };
        DebugRect r = rects[iid];
        float2 local = r.rect.xy - u.origin + corners[vid] * r.rect.zw;
        DebugOut o;
        o.position = float4((local / u.size) * 2.0 - 1.0, 0.0, 1.0);
        o.color = r.color;
        return o;
    }

    fragment float4 debug_fragment(DebugOut in [[stage_in]]) {
        return float4(in.color.rgb * in.color.a, in.color.a);
    }
    """

    static let surface = """
    #include <metal_stdlib>
    using namespace metal;

    struct ViewUniforms { float2 origin; float2 size; };
    struct SurfaceUniforms { float minX; float baseY; float binWidth; uint binCount; uint heightOffset; float maxDepth; };
    struct SurfaceOut { float4 position [[position]]; float shade; float alpha; };

    static float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }

    vertex SurfaceOut surface_vertex(uint vid [[vertex_id]],
                                     constant float *heights [[buffer(0)]],
                                     constant SurfaceUniforms &s [[buffer(1)]],
                                     constant ViewUniforms &u [[buffer(2)]]) {
        // Two bands per column (body, soft fringe), 6 vertices each.
        const uint corner[6] = { 0, 1, 2, 2, 1, 3 };
        uint col = vid / 12, k = vid % 12, band = k / 6;
        uint c = corner[k % 6];
        uint xi = c & 1, yi = c >> 1;
        uint edge = col + xi;
        uint iL = edge == 0 ? 0 : edge - 1;
        uint iR = min(edge, s.binCount - 1);
        float h = 0.5 * (heights[s.heightOffset + iL] + heights[s.heightOffset + iR]);
        // Irregular silhouette: deterministic per-edge wobble that scales with depth.
        h = max(0.0, h + (hash11(float(edge) + s.minX * 0.013) - 0.5) * min(1.6, h * 0.18));
        float y = s.baseY;
        float alpha = 1.0, shade = 0.0;
        if (band == 0) { y += yi == 1 ? h : 0.0; shade = float(yi); }
        else { y += h + (yi == 1 ? 1.8 : 0.0); shade = 1.0; alpha = yi == 1 ? 0.0 : 1.0; }
        alpha *= smoothstep(0.02, 0.5, h);
        float2 local = float2(s.minX + float(edge) * s.binWidth, y) - u.origin;
        SurfaceOut o;
        o.position = float4((local / u.size) * 2.0 - 1.0, 0.0, 1.0);
        o.shade = shade; o.alpha = alpha;
        return o;
    }

    fragment float4 surface_fragment(SurfaceOut in [[stage_in]]) {
        float3 c = mix(float3(0.80, 0.86, 0.94), float3(1.0), in.shade);
        float a = in.alpha * 0.97;
        return float4(c * a, a);
    }
    """
}
