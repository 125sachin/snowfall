/// Metal Shading Language source, compiled at runtime with `MTLDevice.makeLibrary(source:)`.
/// (Embedded rather than shipped as .metal files so the app builds without the optional
/// Metal Toolchain component; see docs/BUILDING.md.)
enum ShaderSource {
    static let particles = """
    #include <metal_stdlib>
    using namespace metal;

    struct ParticleInstance { float2 position; float radius; float rotation; float opacity; float seed; };
    struct ViewUniforms { float2 origin; float2 size; };
    struct ParticleOut { float4 position [[position]]; float2 uv; float opacity; float seed; float radius; float rot; };

    vertex ParticleOut particle_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                       constant ParticleInstance *inst [[buffer(0)]],
                                       constant ViewUniforms &u [[buffer(1)]]) {
        const float2 corners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
        ParticleInstance p = inst[iid];
        float2 c = corners[vid];
        float extent = p.radius * 1.5 + 0.75;
        float2 local = p.position - u.origin + c * extent;
        ParticleOut o;
        o.position = float4((local / u.size) * 2.0 - 1.0, 0.0, 1.0);
        o.uv = c * (extent / p.radius);
        o.opacity = p.opacity; o.seed = p.seed; o.radius = p.radius; o.rot = p.rotation;
        return o;
    }

    static float segDist(float2 p, float2 a, float2 b) {
        float2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * h);
    }

    // Snow crystal: six-fold symmetric. The plane is folded into one 30-degree wedge so only a
    // single arm (along +x) and its branches are described; the fold mirrors it into all six arms.
    fragment float4 particle_fragment(ParticleOut in [[stage_in]], texture2d<float> crystal [[texture(0)]],
                                      constant float &contrast [[buffer(0)]]) {
        const float3 outlineColor = float3(0.36, 0.50, 0.74);   // cool blue edge for light backgrounds
        if (in.seed >= 2.0) {                         // steam puff: soft, warm-white, no crystal
            float rr = length(in.uv);
            float a = smoothstep(1.0, 0.0, rr) * in.opacity * 0.75;
            return float4(mix(float3(1.0, 0.96, 0.92), float3(0.72, 0.78, 0.88), contrast) * a, a);
        }
        float spin = in.rot + in.seed * 6.2831;
        float cs = cos(spin), sn = sin(spin);
        float2 uv = float2(in.uv.x * cs - in.uv.y * sn, in.uv.x * sn + in.uv.y * cs);
        float r = length(uv);

        if (in.radius < 1.7) {                       // too small to resolve: soft dot
            float a = smoothstep(1.0, 0.35, r) * in.opacity;
            return float4(mix(float3(1.0), float3(0.60, 0.72, 0.92), contrast * 0.75) * a, a);
        }

        float aa = max(fwidth(r), 0.03);

        // Half of all flakes use the bundled SVG artwork (white mask) instead.
        if (is_null_texture(crystal) == false && in.radius >= 1.7 && fract(in.seed * 5.71) < 0.5) {
            constexpr sampler smp(filter::linear, mip_filter::linear, address::clamp_to_zero);
            float2 tuv = float2(uv.x, -uv.y) * 0.5 + 0.5;
            float m = crystal.sample(smp, tuv).a;
            float a2 = clamp(pow(m, 0.55) * 1.35, 0.0, 1.0) * in.opacity;   // thin strokes: keep them solid when minified
            float3 c2 = mix(float3(1.0), float3(0.88, 0.94, 1.0), smoothstep(0.3, 1.0, r));
            // Light backdrop: a blurred, grown copy of the mask behind the shape forms a soft cool outline.
            float grown = clamp(crystal.sample(smp, tuv, level(1.5)).a * 3.4, 0.0, 1.0) * in.opacity;
            float aEdge = max(a2, grown);
            float4 plain = float4(c2 * a2, a2);
            float4 outlined = float4(c2 * a2 + outlineColor * aEdge * (1.0 - a2), a2 + aEdge * (1.0 - a2));
            return mix(plain, outlined, contrast);
        }

        const float sector = 1.0471976;              // 60 degrees
        float ang = fmod(atan2(uv.y, uv.x) + 6.2831853, sector);
        ang = min(ang, sector - ang);                // 0..30 degrees from the nearest arm axis
        float2 q = float2(cos(ang), sin(ang)) * r;   // arm lies along +x

        // Bold six-armed flake with round-capped strokes: a long arm plus two outward-angled
        // side branches per arm (mirrored into all six arms by the fold).
        const float w = 0.105;                       // stroke half-width
        const float2 dir = float2(0.7071068, 0.7071068);
        float d = segDist(q, float2(0.0, 0.0), float2(0.90, 0.0)) - w;
        d = min(d, segDist(q, float2(0.36, 0.0), float2(0.36, 0.0) + dir * 0.30) - w * 0.92);
        d = min(d, segDist(q, float2(0.62, 0.0), float2(0.62, 0.0) + dir * 0.23) - w * 0.92);

        float a = clamp((1.0 - smoothstep(-aa, aa, d)) * 1.15, 0.0, 1.0) * in.opacity;
        float aEdge = clamp((1.0 - smoothstep(-aa, aa, d - 0.085)) * 1.1, 0.0, 1.0) * in.opacity;
        // Icy shading: bright core, cooler blue toward the tips.
        float3 col = mix(float3(1.0), float3(0.88, 0.94, 1.0), smoothstep(0.3, 1.0, r));
        // Faint cool halo so crystals stay visible over white windows.
        float halo = 0.22 * (1.0 - smoothstep(0.0, 0.22, max(d, 0.0))) * (1.0 - a) * in.opacity;
        float4 plain = float4(col * a + float3(0.38, 0.5, 0.68) * halo, a + halo);
        float4 outlined = float4(col * a + outlineColor * aEdge * (1.0 - a), a + aEdge * (1.0 - a));
        return mix(plain, outlined, contrast);
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

    struct SpriteUniforms { float2 center; float2 size; float rotation; float alpha; };
    struct SpriteOut { float4 position [[position]]; float2 uv; float alpha; };

    vertex SpriteOut sprite_vertex(uint vid [[vertex_id]],
                                   constant SpriteUniforms &s [[buffer(0)]],
                                   constant ViewUniforms &u [[buffer(1)]]) {
        const float2 corners[4] = { float2(-0.5,-0.5), float2(0.5,-0.5), float2(-0.5,0.5), float2(0.5,0.5) };
        float2 c = corners[vid];
        float cs = cos(s.rotation), sn = sin(s.rotation);
        float2 p = c * s.size;
        p = float2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
        float2 local = s.center + p - u.origin;
        SpriteOut o;
        o.position = float4((local / u.size) * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(c.x + 0.5, 0.5 - c.y);
        o.alpha = s.alpha;
        return o;
    }

    fragment float4 sprite_fragment(SpriteOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler smp(filter::linear, address::clamp_to_edge);
        return tex.sample(smp, in.uv) * in.alpha;   // premultiplied
    }
    """

    static let surface = """
    #include <metal_stdlib>
    using namespace metal;

    struct ViewUniforms { float2 origin; float2 size; };
    struct SurfaceUniforms { float minX; float baseY; float binWidth; uint binCount; uint heightOffset; float maxDepth; float cornerRadius; float contrast; };
    struct SurfaceOut { float4 position [[position]]; float shade; float alpha; float contrast; };

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
        // Rounded window corners: the base follows a quarter circle at each end.
        float width = float(s.binCount) * s.binWidth;
        float r = min(s.cornerRadius, width * 0.5);
        if (r > 0.0) {
            float lx = float(edge) * s.binWidth;
            float d = clamp(min(lx, width - lx), 0.0, r);
            y -= r - sqrt(max(0.0, r * r - (r - d) * (r - d)));
        }
        float alpha = 1.0, shade = 0.0;
        if (band == 0) { y += yi == 1 ? h : 0.0; shade = float(yi); }
        else { y += h + (yi == 1 ? 1.8 : 0.0); shade = 2.0; alpha = yi == 1 ? 0.0 : 1.0; }   // shade 2 = soft rim
        alpha *= smoothstep(0.02, 0.5, h);
        float2 local = float2(s.minX + float(edge) * s.binWidth, y) - u.origin;
        SurfaceOut o;
        o.position = float4((local / u.size) * 2.0 - 1.0, 0.0, 1.0);
        o.shade = shade; o.alpha = alpha; o.contrast = s.contrast;
        return o;
    }

    fragment float4 surface_fragment(SurfaceOut in [[stage_in]]) {
        float3 body = mix(float3(0.80, 0.86, 0.94), float3(0.64, 0.74, 0.90), in.contrast);   // bluer on light backgrounds
        float3 top = mix(float3(1.0), float3(0.97, 0.985, 1.0), in.contrast);
        float3 rim = mix(float3(1.0), float3(0.40, 0.54, 0.78), in.contrast);                  // cool outline along the top
        float3 c = in.shade > 1.5 ? rim : mix(body, top, in.shade);
        float a = in.alpha * 0.97;
        return float4(c * a, a);
    }
    """
}
