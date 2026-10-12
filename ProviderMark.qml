import QtQuick
import QtQuick.Effects
import qs.Commons
import "Format.js" as Format

// A provider logo tinted to the theme. The bundled SVGs are white-filled
// Simple Icons marks; MultiEffect recolors them to `color` (the same technique
// the Omarchy tray uses for symbolic icons), so they follow every theme.
// Providers without a bundled mark fall back to a Nerd Font glyph.
Item {
  id: root

  property string provider: ""
  property color color: Color.foreground
  property string fontFamily: Style.font.family
  property real size: Style.font.iconLarge

  readonly property bool bundled: Format.hasMark(provider)
  readonly property bool svgReady: bundled && mark.status === Image.Ready

  implicitWidth: size
  implicitHeight: size

  Image {
    id: mark
    anchors.fill: parent
    visible: false
    layer.enabled: root.bundled
    source: root.bundled ? Qt.resolvedUrl("assets/" + root.provider + ".svg") : ""
    sourceSize.width: Math.round(root.size * Screen.devicePixelRatio)
    sourceSize.height: Math.round(root.size * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    smooth: true
  }

  MultiEffect {
    anchors.fill: mark
    source: mark
    visible: root.svgReady
    colorization: 1.0
    colorizationColor: root.color
  }

  Text {
    anchors.centerIn: parent
    visible: !root.svgReady
    textFormat: Text.PlainText
    text: Format.glyph(root.provider) || Format.glyph("user")
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.size
  }
}
