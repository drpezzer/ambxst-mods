#version 440
// Icon ramp tint for the Ambxst tinted-icons mod.
// Luminance-mapped palette tint, ported from Iconicul by dvrkxed
// (https://codeberg.org/dvrkxed/iconicul, MIT). The pixel's Lab lightness is
// remapped onto the palette's lightness range, the palette anchors are blended
// with a Gaussian window in Lab, and the result's chroma is scaled by how
// saturated the source pixel was, so anti-aliased greys stay neutral instead
// of picking up whichever hue sits at that lightness.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D paletteTexture;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float paletteSize;
    float texWidth;
    float texHeight;
} ubuf;

const float SOFTNESS = 8.0;          // Gaussian sigma in Lab L units
const float REFERENCE_CHROMA = 60.0; // "fully saturated" reference for the chroma scale

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
    return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

float labF(float t) {
    return t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0;
}

float labFInv(float t) {
    float c = t * t * t;
    return c > 0.008856 ? c : (t - 16.0 / 116.0) / 7.787;
}

vec3 srgbToLab(vec3 c) {
    vec3 l = vec3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
    float x = (0.4124564 * l.r + 0.3575761 * l.g + 0.1804375 * l.b) / 0.95047;
    float y = (0.2126729 * l.r + 0.7151522 * l.g + 0.0721750 * l.b);
    float z = (0.0193339 * l.r + 0.1191920 * l.g + 0.9503041 * l.b) / 1.08883;
    float fx = labF(x), fy = labF(y), fz = labF(z);
    return vec3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz));
}

vec3 labToSrgb(vec3 lab) {
    float fy = (lab.x + 16.0) / 116.0;
    float fx = lab.y / 500.0 + fy;
    float fz = fy - lab.z / 200.0;
    float x = labFInv(fx) * 0.95047;
    float y = labFInv(fy);
    float z = labFInv(fz) * 1.08883;
    vec3 l = vec3(
         3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
        -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
         0.0556434 * x - 0.2040259 * y + 1.0572252 * z);
    l = clamp(l, 0.0, 1.0);
    return vec3(linearToSrgb(l.r), linearToSrgb(l.g), linearToSrgb(l.b));
}

vec3 paletteLab(int i) {
    float u = (float(i) + 0.5) / ubuf.paletteSize;
    return srgbToLab(texture(paletteTexture, vec2(u, 0.5)).rgb);
}

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    if (tex.a < 0.002) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 src = srgbToLab(tex.rgb / tex.a); // un-premultiply first
    int size = int(ubuf.paletteSize);

    // Palette lightness range, so the full 0-100 source range spreads across
    // whatever range the scheme actually has and shading is never collapsed.
    float minL = 100.0, maxL = 0.0;
    for (int i = 0; i < 64; i++) {
        if (i >= size) break;
        float l = paletteLab(i).x;
        minL = min(minL, l);
        maxL = max(maxL, l);
    }
    float remapped = minL + (maxL - minL) * clamp(src.x / 100.0, 0.0, 1.0);

    // Soft blend of every anchor, weighted by closeness in lightness.
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    vec3 nearest = vec3(50.0, 0.0, 0.0);
    float nearestD = 1e9;
    for (int i = 0; i < 64; i++) {
        if (i >= size) break;
        vec3 p = paletteLab(i);
        float dl = remapped - p.x;
        float w = exp(-0.5 * (dl / SOFTNESS) * (dl / SOFTNESS));
        acc += p * w;
        wsum += w;
        if (abs(dl) < nearestD) { nearestD = abs(dl); nearest = p; }
    }
    vec3 outLab = wsum < 1e-6 ? nearest : acc / wsum;

    // Keep the source pixel's own neutrality: greys stay grey at the new lightness.
    float chroma = length(src.yz);
    float chromaFactor = clamp(chroma / REFERENCE_CHROMA, 0.0, 1.0);
    outLab.yz *= chromaFactor;

    vec3 rgb = labToSrgb(outLab);
    fragColor = vec4(rgb * tex.a, tex.a) * ubuf.qt_Opacity;
}
