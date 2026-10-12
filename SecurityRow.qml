import QtQuick
import qs.Commons
import qs.Ui

// One line of the Keys & security card: glyph, label, state, and an optional
// setup button (e.g. "Generate" when no SSH key exists).
Item {
  id: root

  property string icon: ""
  property string label: ""
  property string value: ""
  property bool warn: false
  property string actionText: ""
  property string actionTooltip: ""
  property bool hasCursor: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal actionTriggered()
  signal actionHovered()

  readonly property color dim: Qt.darker(foreground, 1.4)

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(iconText.implicitHeight, labelText.implicitHeight, action.visible ? action.implicitHeight : 0)

  Text {
    id: iconText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(20)
    textFormat: Text.PlainText
    text: root.icon
    color: root.warn ? Color.urgent : root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.icon
  }

  Text {
    id: labelText
    anchors.left: iconText.right
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.label
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    anchors.left: labelText.right
    anchors.leftMargin: Style.space(10)
    anchors.right: action.visible ? action.left : parent.right
    anchors.rightMargin: action.visible ? Style.space(8) : 0
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignRight
    text: root.value
    color: root.warn ? Color.urgent : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideMiddle
  }

  Button {
    id: action
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.actionText !== ""
    text: root.actionText
    tooltipText: root.actionTooltip
    bordered: true
    hasCursor: root.hasCursor
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    horizontalPadding: Style.space(8)
    verticalPadding: Style.space(3)
    onClicked: root.actionTriggered()
    onHovered: function(isHovered) { if (isHovered) root.actionHovered() }
  }
}
