import QtQuick

// roadie: an Image with rounded corners and no layer. The Image itself is the
// shader's texture (an Image is a texture provider), so there is no hidden
// ShaderEffectSource like the one Quickshell's ClippingRectangle builds, which
// is what the recurring stacking-order crash finds freed.
// Image.PreserveAspectCrop is done in the shader.
Item {
    id: root
    property alias source: img.source
    property alias status: img.status
    property alias image: img
    property real radius: 0
    property bool mipmap: true

    Image {
        id: img
        anchors.fill: parent
        visible: false
        mipmap: root.mipmap
        smooth: true
    }

    ShaderEffect {
        anchors.fill: parent
        visible: img.status === Image.Ready && width > 0 && height > 0
        property variant source: img
        property real itemWidth: width
        property real itemHeight: height
        property real radius: root.radius
        readonly property real texW: Math.max(1, img.implicitWidth)
        readonly property real texH: Math.max(1, img.implicitHeight)
        readonly property real fit: Math.max(width / texW, height / texH)
        property real cropX: fit > 0 ? Math.min(1, width / (texW * fit)) : 1
        property real cropY: fit > 0 ? Math.min(1, height / (texH * fit)) : 1
        fragmentShader: "roadie_roundclip.frag.qsb"
    }
}
