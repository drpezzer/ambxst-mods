import QtQuick
import Caelestia.Config
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.services

// Text for the lockscreen composition. Sizes are set per item; the family comes
// from Tokens so it stays whatever Caelestia's own lockscreen uses (currently
// GoogleSansFlex) rather than being pinned here.
Text {
    renderType: Text.NativeRendering
    textFormat: Text.PlainText

    font.family: Tokens.font.body.small.family
    color: Colours.palette.m3primary

    Behavior on color {
        CAnim {}
    }
}
