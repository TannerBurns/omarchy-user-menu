import QtQuick
import qs.Commons
import qs.Ui
import "Format.js" as Format

// One connected-account row. Display-only: hover shows where the identity
// came from and any expiry, nothing is clickable.
Item {
  id: row

  property var account: ({})
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property double nowMs: Date.now()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property bool signedOut: account.status === "signed-out"
  readonly property bool warn: account.status === "expiring" || account.status === "expired"
  readonly property color statusColor: account.status === "connected" ? Color.accent
    : account.status === "expired" ? Color.urgent
    : account.status === "expiring" ? Util.alpha(Color.urgent, 0.7)
    : dim

  readonly property string detailText: account.identity || account.note || account.source || ""
  readonly property string tooltipText: {
    var lines = []
    if (account.source) lines.push("Source: " + account.source)
    if (account.note && account.note !== detailText) lines.push(account.note)
    if (account.expiresEpochMs) {
      var verb = account.expiresEpochMs > nowMs ? "Expires " : "Expired "
      lines.push(verb + Qt.formatDateTime(new Date(account.expiresEpochMs), "ddd d MMM yyyy, HH:mm"))
    }
    return lines.join("\n")
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(mark.implicitHeight, labels.implicitHeight) + Style.space(8)

  ProviderMark {
    id: mark
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    provider: row.account.provider || ""
    color: row.signedOut ? row.dim : row.foreground
    fontFamily: row.fontFamily
    size: Style.font.iconLarge
  }

  Column {
    id: labels
    anchors.left: mark.right
    anchors.leftMargin: Style.space(10)
    anchors.right: status.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        id: nameText
        textFormat: Text.PlainText
        text: row.account.name || ""
        color: row.signedOut ? row.dim : row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        width: Math.min(implicitWidth, parent.width - (planChip.visible ? planChip.width + parent.spacing : 0))
        elide: Text.ElideRight
      }

      BorderSurface {
        id: planChip
        visible: (row.account.plan || "") !== ""
        anchors.verticalCenter: nameText.verticalCenter
        width: planText.implicitWidth + Style.space(8)
        height: planText.implicitHeight + Style.space(2)
        color: "transparent"
        borderSpec: Border.controlSpec("normal", row.foreground, Color.accent)
        radius: Style.cornerRadius

        Text {
          id: planText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: row.account.plan || ""
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      text: row.detailText
      color: row.dim
      font.family: row.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }
  }

  // Shape and word, never color alone: some themes set accent == foreground.
  Row {
    id: status
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(5)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7)
      height: width
      radius: width / 2
      color: row.signedOut ? "transparent" : row.statusColor
      border.width: row.signedOut ? Math.max(1, Style.space(1)) : 0
      border.color: row.dim
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Format.statusWord(row.account, row.nowMs)
      color: row.warn ? Color.urgent : row.dim
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }

  PanelToolTip {
    visible: hover.containsMouse && row.tooltipText !== ""
    text: row.tooltipText
    fontFamily: row.fontFamily
  }
}
