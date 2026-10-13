// roadie: rounded-corner clip for notification icons, sampled straight from
// the Image's own texture. Stands in for Quickshell's ClippingRectangle there,
// whose hidden layer source is the object the recurring
// updateChildWindowStackingOrder crash finds already freed.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float itemWidth;
    float itemHeight;
    float radius;
    // Image.PreserveAspectCrop: the share of the texture shown on each axis.
    float cropX;
    float cropY;
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 size = vec2(ubuf.itemWidth, ubuf.itemHeight);
    vec2 hs = size * 0.5;
    float r = min(ubuf.radius, min(hs.x, hs.y));
    vec2 q = abs(qt_TexCoord0 * size - hs) - (hs - vec2(r));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float a = clamp(0.5 - d, 0.0, 1.0);
    vec2 uv = vec2(0.5) + (qt_TexCoord0 - vec2(0.5)) * vec2(ubuf.cropX, ubuf.cropY);
    fragColor = texture(source, uv) * a * ubuf.qt_Opacity;
}
