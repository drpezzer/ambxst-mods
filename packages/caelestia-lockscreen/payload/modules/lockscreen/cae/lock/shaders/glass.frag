// Liquid-glass refraction, ported from HyprGlass (src/Shaders.hpp) to Qt's
// shader dialect so the lockscreen card can match the glass on Hyprland
// windows. HyprGlass hooks renderLayer and window decorations, neither of which
// Hyprland uses for session-lock surfaces, so the plugin cannot reach the lock.
//
// Differences from upstream: no mask path (that exists for layer surfaces
// compositing their own content), and no UV padding (the source texture here is
// exactly the card's region of the wallpaper, not a padded FBO).
//
// Build: qsb --qt6 -o glass.frag.qsb glass.frag

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;
    vec2 fullSize;
    vec4 tintColor;
    float roundingPower;
    float edgeThickness;
    float refractionStrength;
    float chromaticAberration;
    float lensDistortion;
    float fresnelStrength;
    float specularStrength;
    float glassOpacity;
    float brightness;
    float contrast;
    float saturation;
    float vibrancy;
    float vibrancyDarkness;
    float adaptiveDim;
    float adaptiveBoost;
};

layout(binding = 1) uniform sampler2D source;

vec4 sampleBlurred(vec2 uv) {
    return texture(source, clamp(uv, 0.001, 0.999));
}

float lpNorm(vec2 v, float p) {
    return pow(pow(abs(v.x), p) + pow(abs(v.y), p), 1.0 / p);
}

float getRoundedBoxSDF(vec2 uv, float r) {
    vec2 p = (uv - 0.5) * fullSize;
    vec2 halfSize = fullSize * 0.5;
    float clampedR = min(r, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + clampedR;
    return min(max(q.x, q.y), 0.0) + lpNorm(max(q, vec2(0.0)), roundingPower) - clampedR;
}

// Pixel-space direction toward the card centre. On straight edges the
// perpendicular distance dominates, giving an approximately edge-normal
// direction; at corners it follows the diagonal.
vec2 refractionDir(vec2 uv) {
    vec2 toCenterPx = (vec2(0.5) - uv) * fullSize;
    float len = length(toCenterPx);
    return len > 0.1 ? toCenterPx / len : vec2(0.0);
}

void main() {
    vec2 uv = qt_TexCoord0;

    float cornerSdf = getRoundedBoxSDF(uv, radius);
    if (cornerSdf > 0.0)
        discard;

    float cornerAlpha = 1.0 - smoothstep(-1.5, 0.5, cornerSdf);
    if (cornerAlpha < 0.001)
        discard;

    float minDim = min(fullSize.x, fullSize.y);
    float bezelWidthPx = edgeThickness * minDim;

    // 1.0 at the boundary, decaying exponentially inward.
    float edgeProximity = exp(cornerSdf / bezelWidthPx);
    vec2 inwardDir = refractionDir(uv);

    // Offset sampling inward at the edges, like looking through the curved
    // thick edge of a glass slab: compresses what is already behind the card
    // without reaching past its boundary.
    float refractionPx = refractionStrength * 50.0;
    float refractionMag = edgeProximity * refractionPx;
    vec2 baseOffset = inwardDir * refractionMag / fullSize;

    // Blue refracts further than red, giving spectral fringing on the curl.
    float chromaSpread = chromaticAberration * 0.35;
    vec2 offsetR = baseOffset * (1.0 - chromaSpread);
    vec2 offsetG = baseOffset;
    vec2 offsetB = baseOffset * (1.0 + chromaSpread);

    // Subtle dome magnification across the flat interior, faded out near the
    // edges so it does not fight the refraction.
    vec2 domeUV = vec2(0.0);
    if (lensDistortion > 0.001) {
        vec2 c = (uv - 0.5) * 2.0;
        vec2 dGrad = vec2(-4.0 * c.x * (1.0 - c.y * c.y), -4.0 * c.y * (1.0 - c.x * c.x));
        float lensMaxPx = lensDistortion * minDim * 0.006;
        float lensFade = 1.0 - edgeProximity;
        domeUV = dGrad * lensMaxPx * lensFade / fullSize;
    }

    vec3 color;
    vec2 uvR = uv + offsetR + domeUV;
    vec2 uvG = uv + offsetG + domeUV;
    vec2 uvB = uv + offsetB + domeUV;

    if (chromaticAberration > 0.001 && edgeProximity > 0.01) {
        color.r = sampleBlurred(uvR).r;
        color.g = sampleBlurred(uvG).g;
        color.b = sampleBlurred(uvB).b;
    } else {
        color = sampleBlurred(uvG).rgb;
    }

    float blurredLum = dot(color, vec3(0.2126, 0.7152, 0.0722));

    color = mix(vec3(blurredLum), color, saturation);

    // Maps the blur-compressed luminance range onto [0,1] so the adaptive
    // terms differentiate regions visibly.
    float lumCurve = smoothstep(0.25, 0.55, blurredLum);

    color *= brightness * (1.0 - adaptiveDim * lumCurve);
    color += vec3(adaptiveBoost * (1.0 - lumCurve) * 0.5);
    color = mix(vec3(0.5), color, contrast);

    float currentLum = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float sat = max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b));
    float darkFactor = 1.0 - vibrancyDarkness * (1.0 - blurredLum);
    color = mix(vec3(currentLum), color, 1.0 + vibrancy * sat * darkFactor);

    color = mix(color, tintColor.rgb, tintColor.a);

    if (fresnelStrength > 0.001) {
        float fresnel = edgeProximity * edgeProximity * fresnelStrength * 0.15;
        color += vec3(1.0) * fresnel;
    }

    if (specularStrength > 0.001) {
        float topBias = pow(max(1.0 - uv.y, 0.0), 2.0);
        float spec = topBias * edgeProximity * edgeProximity * specularStrength * 0.08;
        color += vec3(1.0, 0.99, 0.97) * spec;
    }

    {
        float bottomBias = pow(uv.y, 2.0);
        float shadow = bottomBias * edgeProximity * edgeProximity * 0.06;
        color *= 1.0 - shadow;
    }

    // Qt's scene graph expects premultiplied alpha.
    float glassA = glassOpacity * cornerAlpha * qt_Opacity;
    fragColor = vec4(color * glassA, glassA);
}
