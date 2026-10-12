import QtQuick
import QtQuick.Effects
import qs.Commons

// Circular avatar: ~/.face (or AccountsService icon) when one exists,
// otherwise the user's initials on an accent-tinted disc.
Item {
  id: root

  property string source: ""
  property string initials: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real size: Style.space(44)

  readonly property bool hasImage: source !== "" && photo.status === Image.Ready

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    anchors.fill: parent
    visible: !root.hasImage
    radius: width / 2
    color: Util.alpha(Color.accent, 0.16)
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(Color.accent, 0.6)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.initials
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.size * 0.38)
      font.bold: true
    }
  }

  Image {
    id: photo
    anchors.fill: parent
    visible: false
    layer.enabled: true
    source: root.source !== "" ? Util.fileUrl(root.source) : ""
    sourceSize.width: Math.round(root.size * 2)
    sourceSize.height: Math.round(root.size * 2)
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    smooth: true
  }

  Rectangle {
    id: circleMask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    radius: width / 2
    color: "white"
  }

  MultiEffect {
    anchors.fill: parent
    visible: root.hasImage
    source: photo
    maskEnabled: true
    maskSource: circleMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
  }
}
