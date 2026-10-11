// medieval_core: the engine's translucent shader plus living water.
// Overrides res/shaders/translucent.glslf (pack resources come after the
// core). Water is recognised by the alpha of its texture (WATER_ALPHA in
// dev/gen_water_assets.py); glass, ice and everything else render unchanged.
//
// Depth: with the advanced render the G-buffer of the opaque pass is still
// bound (positions on unit 2, view space) while translucent blocks are drawn,
// so the water surface knows how much water lies behind it and turns dark
// and opaque with depth. Sampler bindings in GLSL 3.30 need the 420pack
// extension; without it (or with the classic render) water is just darker.
#if defined(ADVANCED_RENDER) && defined(GL_ARB_shading_language_420pack)
#extension GL_ARB_shading_language_420pack : require
#define MW_WATER_DEPTH
#endif
layout (location = 0) out vec4 f_color;

#include <world_fragment_header>

in vec4 a_torchLight;

uniform sampler2D u_texture0;
uniform vec3 u_sunDir;

// flags
uniform bool u_alphaClip;
uniform bool u_debugLights;
uniform bool u_debugNormals;

#include <shadows>

#define WATER_ALPHA (190.0 / 255.0)
#define WATER_ALPHA_EPS (2.5 / 255.0)

// overall tint of the water and the colour it fades to with depth
#define WATER_DARKEN 0.85
#define DEEP_COLOR vec3(0.025, 0.075, 0.095)
#define ABSORPTION 0.24         // per block of water the view crosses
#define FALLBACK_ALPHA 0.86

#ifdef MW_WATER_DEPTH
layout (binding = 2) uniform sampler2D u_mwPositions;   // TARGET_POSITIONS

// blocks of water between the surface fragment and the opaque scene
float water_thickness() {
    vec4 behind = texelFetch(u_mwPositions, ivec2(gl_FragCoord.xy), 0);
    float far = length(behind.xyz);
    if (far < 1e-4) {
        return 64.0;            // nothing drawn there: sky or unloaded chunks
    }
    return max(0.0, far - length(a_position));
}
#endif

// --- noise -------------------------------------------------------------------

// sin-free hash: stable for large world coordinates
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// value noise and its gradient in one go: (value, d/dx, d/dy)
vec3 value_noise_d(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    vec2 du = 6.0 * f * (1.0 - f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    float k = a - b - c + d;
    return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y,
                du.x * (b - a + k * u.y),
                du.y * (c - a + k * u.x));
}

// wave height 0..1 and its gradient over the surface: three layers drifting
// in different directions; the second and third are rotated so the pattern
// never lines up with blocks. Gradients are analytic (one noise per layer
// instead of three for finite differences).
vec3 ripple(vec2 p, float t) {
    const mat2 rot1 = mat2(0.80, 0.60, -0.60, 0.80);
    const mat2 rot2 = mat2(0.34, -0.94, 0.94, 0.34);
    vec3 n1 = value_noise_d(p * 1.1 + vec2(t * 0.31, t * 0.19));
    vec3 n2 = value_noise_d(rot1 * p * 2.3 + vec2(-t * 0.43, t * 0.27));
    vec3 n3 = value_noise_d(rot2 * p * 5.1 + vec2(t * 0.62, -t * 0.55));
    float h = n1.x * 0.5 + n2.x * 0.32 + n3.x * 0.18;
    vec2 g = n1.yz * (1.1 * 0.5)
           + transpose(rot1) * n2.yz * (2.3 * 0.32)
           + transpose(rot2) * n3.yz * (5.1 * 0.18);
    return vec3(h, g);
}

// --- light ------------------------------------------------------------------

// direction towards the sun, computed the way Skybox.cpp places it
vec3 sun_direction(float dayTime) {
    float sunAngle = (dayTime - 0.25) * PI2;
    float x = -cos(sunAngle + PI * 0.5) * radians(45.0);
    float y = sunAngle - PI * 0.5;
    return normalize(vec3(-cos(x) * sin(y), sin(x), -cos(x) * cos(y)));
}

// shadow: calc_shadow() result, 1.0 without shadows, 0.5 in full shade
vec4 shade_water(vec4 texColor, vec3 baseLight, float shadow) {
    vec3 world = a_modelpos.xyz;
    vec2 p = mod(world.xz, 4096.0);
    float t = u_timer;
    vec3 normal = normalize(a_realnormal);
    vec3 color = texColor.rgb * WATER_DARKEN;
    float alpha = texColor.a;
    // how much of the view is swallowed by the water (top surface only:
    // falling sheets would turn opaque against the far landscape)
    float absorb = 0.0;
    if (normal.y > 0.5) {
#ifdef MW_WATER_DEPTH
        absorb = 1.0 - exp(-water_thickness() * ABSORPTION);
#else
        alpha = max(alpha, FALLBACK_ALPHA);
#endif
    }
    // ripples fade out with distance (they would only shimmer there)
    float detail = clamp(1.0 - (a_distance - 24.0) / 48.0, 0.0, 1.0);

    vec3 n = normal;
    float h;
    if (abs(normal.y) > 0.5) {
        if (detail > 0.0) {
            // surface (from above or below): normal from the height field
            vec3 r = ripple(p, t);
            h = r.x;
            float strength = 0.4 * detail;
            n = normalize(vec3(-r.y * strength, 1.0, -r.z * strength)) * sign(normal.y);
        } else {
            // far away only the broad swell is left (flat normal)
            h = value_noise(p * 1.1 + vec2(t * 0.31, t * 0.19)) * 0.5 + 0.25;
        }
    } else {
        // sides: streaks running down, like a thin falling sheet
        vec2 side = vec2(dot(world.xz, vec2(-normal.z, normal.x)), world.y);
        h = value_noise(vec2(side.x * 4.0, side.y * 0.7 + t * 2.6)) * 0.6 +
            value_noise(vec2(side.x * 9.0, side.y * 1.6 + t * 4.1)) * 0.4;
    }
    // crests lighter, troughs darker
    color *= 1.0 + (h - 0.5) * 0.6 * mix(0.4, 1.0, detail);

    color *= baseLight;
    color = mix(color, DEEP_COLOR * baseLight, absorb);
    alpha = mix(alpha, 0.98, absorb);

    // glints: Blinn-Phong on the rippled normal, broken up by fine noise
    vec3 sun = sun_direction(u_dayTime);
    float intensity = clamp(sun.y * 4.0, 0.0, 1.0);
    vec3 light = sun;
    vec3 tint = mix(vec3(1.0, 0.62, 0.35), vec3(1.0, 0.96, 0.88), clamp(sun.y * 2.5, 0.0, 1.0));
    if (sun.y < 0.0) {
        // the moon is opposite to the sun: dim, cold glints
        light = -sun;
        intensity = clamp(-sun.y * 4.0, 0.0, 1.0) * 0.25;
        tint = vec3(0.7, 0.8, 1.0);
    }
    vec3 view = normalize(u_cameraPos - world);
    vec3 halfway = normalize(light + view);
    float spec = pow(max(dot(n, halfway), 0.0), 260.0) * 1.6;
    spec += pow(max(dot(n, halfway), 0.0), 30.0) * 0.1;
    if (detail > 0.0) {
        float sparkle = smoothstep(0.45, 0.95, value_noise(p * 9.0 + vec2(t * 1.7, -t * 1.3)));
        spec *= mix(1.0, 0.4 + 1.4 * sparkle, detail);
    }
    // no glints in the shade, under a roof or below the surface
    float sky = clamp(dot(a_skyLight, vec3(0.333)) * 1.5, 0.0, 1.0);
    float facing = normal.y > 0.5 ? 1.0 : (normal.y < -0.5 ? 0.0 : 0.25);
    spec *= intensity * sky * facing;
    spec *= mix(0.35, 1.0, clamp(shadow * 2.0 - 1.0, 0.0, 1.0));

    color += tint * spec;
    alpha = min(1.0, alpha + spec * 0.5);
    return vec4(color, alpha);
}

void main() {
    vec4 texColor = texture(u_texture0, a_texCoord);
    float alpha = texColor.a;
    if (u_alphaClip) {
        if (alpha < 0.2f)
            discard;
        alpha = 1.0;
    } else {
        if (alpha < 0.002f)
            discard;
    }
    if (u_debugLights)
        texColor.rgb = u_debugNormals ? (a_normal * 0.5 + 0.5) : vec3(1.0);

    float shadow = calc_shadow(a_modelpos, a_realnormal, length(a_position));
    vec3 baseLight = min(vec3(1.0), a_torchLight.rgb + a_skyLight * shadow);

    if (!u_debugLights && abs(texColor.a - WATER_ALPHA) < WATER_ALPHA_EPS) {
        f_color = shade_water(texColor, baseLight, shadow);
        alpha = f_color.a;
    } else {
        f_color = texColor;
        f_color.rgb *= baseLight;
    }

    vec3 fogColor = texture(u_skybox, a_dir).rgb;
    f_color = mix(f_color, vec4(fogColor, 1.0), a_fog);
    f_color.a = alpha;
}
