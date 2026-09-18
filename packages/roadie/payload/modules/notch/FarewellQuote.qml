import QtQuick

// Ambxst Roadie (drpezzer.roadie): the line the farewell shows.
//
// Always ONE line, whatever the screen: the quote is set at a size that suits
// the screen (2.6% of its height, less on a narrow or upright one) and, if it
// would not fit in 86% of the width at that size, at the largest size that
// does. It never wraps; a line so long it would need less than 6 px is elided.
// Pure on purpose -- no shell imports -- so it can be laid out in a test
// harness at any screen size.
Item {
    id: root

    property string quote: ""
    property string source: ""
    property bool showSource: false
    property color quoteColor: "white"
    property color sourceColor: "gray"
    property string fontFamily: ""
    // 0 = hidden, 1 = fully up (fade plus a short rise).
    property real reveal: 0

    readonly property real basePixelSize: Math.max(14, Math.round(Math.min(root.height * 0.026, root.width * 0.03)))
    readonly property real lineWidth: Math.round(root.width * 0.86)
    // What the fit settled on (for the source line, and for tests).
    readonly property real fittedPixelSize: quoteText.fontInfo.pixelSize
    readonly property int quoteLineCount: quoteText.lineCount
    readonly property real quoteContentWidth: quoteText.contentWidth
    readonly property bool quoteTruncated: quoteText.truncated

    Column {
        anchors.centerIn: parent
        width: root.lineWidth
        spacing: Math.round(root.fittedPixelSize * 0.55)
        opacity: root.reveal
        transform: Translate {
            y: (1 - root.reveal) * 14
        }

        Text {
            id: quoteText
            width: parent.width
            text: root.quote
            color: root.quoteColor
            font.family: root.fontFamily
            font.pixelSize: root.basePixelSize
            font.weight: Font.Medium
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 6
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: root.showSource && root.source !== ""
            width: parent.width
            text: root.source
            color: root.sourceColor
            font.family: root.fontFamily
            font.pixelSize: Math.max(9, Math.round(root.fittedPixelSize * 0.45))
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 2
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 6
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
