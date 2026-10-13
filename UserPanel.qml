import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Format.js" as Format

// The dropdown: who you are, the session, signed-in accounts, keys & security,
// and lock / log out / refresh. Hero and footer stay pinned; the middle scrolls.
//
// Keys: Esc closes · Tab switches panels · j/k scroll · h/l move between
// buttons · Enter activates · r refreshes.
KeyboardPanel {
  id: panel

  property var host: null
  property var probe: null

  property bool cursorActive: false
  property string cursorKey: ""
  property bool pendingLogout: false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int gap: Style.space(12)

  readonly property var session: probe ? probe.session : null
  readonly property var security: probe ? probe.security : null
  readonly property double nowMs: probe ? probe.nowMs : Date.now()

  // ---------------------------------------------------------------- formatting

  function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
  }

  function stamp(epochMs) {
    if (!epochMs) return ""
    var d = new Date(epochMs)
    return Qt.formatDateTime(d, sameDay(d, new Date(nowMs)) ? "HH:mm" : "ddd d MMM, HH:mm")
  }

  // ---------------------------------------------------------------- security state

  readonly property var sshKeys: security && security.ssh ? security.ssh.keys : []
  readonly property var gpgKeys: security && security.gpg ? security.gpg.keys : []
  readonly property var keyring: security ? security.keyring : null
  readonly property var fingerprint: security ? security.fingerprint : null
  readonly property bool fingerprintNeedsSetup: !!fingerprint && fingerprint.reader === true && !(fingerprint.enrolled > 0)

  function keySummary(count, detail) {
    return count + (detail !== "" ? " · " + detail : "")
  }

  readonly property string sshValue: {
    if (!security) return "Checking…"
    if (sshKeys.length === 0) return "None"
    var k = sshKeys[0]
    var detail = k.type + (k.comment ? " (" + k.comment + ")" : "")
    return keySummary(sshKeys.length, detail)
  }

  readonly property string gpgValue: {
    if (!security) return "Checking…"
    if (gpgKeys.length === 0) return "None"
    return keySummary(gpgKeys.length, gpgKeys[0].uid || "")
  }

  readonly property string keyringValue: {
    if (!keyring) return "Checking…"
    if (!keyring.service) return "Not running"
    if (!keyring.collection) return "No default keyring"
    if (keyring.locked === true) return "Locked"
    if (keyring.locked === false) return "Unlocked"
    return "Unknown"
  }

  readonly property string fingerprintValue: {
    if (!fingerprint) return "Checking…"
    if (fingerprint.reader === false) return "No reader"
    if (fingerprint.enrolled > 0) return fingerprint.enrolled + " enrolled"
    if (fingerprint.reader === true) return "Not set up"
    return "Unknown"
  }

  // ---------------------------------------------------------------- cursor

  readonly property var cursorKeys: {
    var keys = []
    if (security && sshKeys.length === 0) keys.push("ssh")
    if (security && gpgKeys.length === 0) keys.push("gpg")
    if (fingerprintNeedsSetup) keys.push("fingerprint")
    return keys.concat(["lock", "logout", "refresh"])
  }

  function hasCursor(key) { return cursorActive && cursorKey === key }

  function hoverCursor(key) {
    cursorActive = true
    cursorKey = key
  }

  function moveCursor(dx) {
    if (!cursorActive || cursorKeys.indexOf(cursorKey) < 0) {
      hoverCursor("lock")
      return
    }
    var n = cursorKeys.length
    cursorKey = cursorKeys[(cursorKeys.indexOf(cursorKey) + dx + n) % n]
  }

  function activateCursor() {
    if (!cursorActive) { hoverCursor("lock"); return }
    trigger(cursorKey)
  }

  function trigger(key) {
    if (!host) return
    if (key === "lock") host.lock()
    else if (key === "logout") { if (host.confirmLogout) pendingLogout = true; else host.logout() }
    else if (key === "refresh") host.refresh()
    else host.launchSetup(key)
  }

  // j/k scroll the account list first (it is the part that grows), then the
  // whole body once the list is at its end or doesn't scroll.
  function scrollBy(dy) {
    var step = dy * Style.space(56)
    if (accountList.interactive) {
      var top = accountList.originY
      var bottom = accountList.originY + accountList.contentHeight - accountList.height
      var next = Math.max(top, Math.min(bottom, accountList.contentY + step))
      if (next !== accountList.contentY) {
        accountList.contentY = next
        return
      }
    }
    var max = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(max, flick.contentY + step))
  }

  onOpenChanged: {
    if (open) {
      cursorActive = false
      cursorKey = ""
      flick.contentY = 0
      accountList.positionViewAtBeginning()
    }
    pendingLogout = false
  }

  onPendingLogoutChanged: {
    if (pendingLogout) {
      // Start on Cancel so a double Enter can't end the session by accident.
      confirm.selectedIndex = 0
      confirmKeys.forceActiveFocus()
    } else {
      keyCatcher.forceActiveFocus()
    }
  }

  // ---------------------------------------------------------------- layout

  focusTarget: keyCatcher
  contentWidth: panel.fittedContentWidth(Style.space(360))
  // No fixed cap: fittedContentHeight already clamps to the screen, and the
  // middle section scrolls when the screen is shorter than the content.
  contentHeight: panel.fittedContentHeight(
    hero.implicitHeight + body.implicitHeight + footer.implicitHeight + gap * 4 + 2)

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: panel.pendingLogout
    onCloseRequested: if (panel.host) panel.host.close()
    onTabRequested: function(direction) { if (panel.host) panel.host.switchPanel(direction) }
    onMoveRequested: function(dx, dy) {
      if (dy !== 0) panel.scrollBy(dy)
      if (dx !== 0) panel.moveCursor(dx)
    }
    onActivateRequested: panel.activateCursor()
    onTextKey: function(t) { if ((t === "r" || t === "R") && panel.host) panel.host.refresh() }

    PanelHero {
      id: hero
      anchors.top: parent.top
      width: parent.width
      foreground: panel.fg
      fontFamily: panel.fontFamily
      title: panel.host ? panel.host.fullName : ""
      meta: panel.host ? panel.host.userHost : ""
      detail: panel.host && panel.host.loggedInFor !== "" ? "Logged in " + panel.host.loggedInFor : ""
      iconComponent: Component {
        Avatar {
          size: Style.space(44)
          source: panel.probe && panel.probe.user ? panel.probe.user.avatar : ""
          initials: panel.host ? panel.host.initials : ""
          foreground: panel.fg
          fontFamily: panel.fontFamily
        }
      }
    }

    PanelSeparator {
      id: topRule
      anchors.top: hero.bottom
      anchors.topMargin: panel.gap
      foreground: panel.fg
    }

    Flickable {
      id: flick
      anchors.top: topRule.bottom
      anchors.topMargin: panel.gap
      anchors.bottom: bottomRule.top
      anchors.bottomMargin: panel.gap
      width: parent.width
      contentWidth: width
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: body
        width: flick.width
        spacing: Style.space(16)

        // ---- Session
        Column {
          id: sessionSection
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "SESSION"
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }

          InfoRow {
            label: "Logged in since"
            value: panel.host ? panel.stamp(panel.host.loginEpochMs) : ""
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }
          InfoRow {
            label: "Session"
            value: Format.sessionKind(panel.session)
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }
          InfoRow {
            label: "Seat"
            value: Format.seatLine(panel.session)
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }
          InfoRow {
            label: "Login"
            value: Format.loginMethod(panel.session)
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }
          InfoRow {
            label: "System uptime"
            value: panel.session && panel.session.bootEpochMs ? Format.duration(panel.nowMs - panel.session.bootEpochMs) : ""
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }
          InfoRow {
            label: "Previous login"
            value: !panel.session ? ""
              : panel.session.previousLogin
                ? panel.stamp(panel.session.previousLogin.epochMs) + " · " + panel.session.previousLogin.tty
                : "—"
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }
          InfoRow {
            readonly property string group: panel.probe && panel.probe.user ? Format.adminGroup(panel.probe.user.groups) : ""
            label: "Administrator"
            value: !panel.probe || !panel.probe.user ? "" : (group !== "" ? "Yes · sudo (" + group + ")" : "No")
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }
        }

        // ---- Connected accounts
        Column {
          id: accountsSection
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            id: accountsHeader
            text: "CONNECTED ACCOUNTS"
            foreground: panel.fg
            fontFamily: panel.fontFamily
            bottomPadding: Style.space(2)
          }

          // Scrolls on its own so a long list doesn't stretch the menu: it shows
          // 5½ rows at most (the half row hints that there is more below), and
          // fewer on short screens so the rest of the menu still fits.
          ListView {
            id: accountList

            readonly property int rowSpacing: Style.space(4)
            readonly property real rowStride: rowMetrics.implicitHeight + rowSpacing
            readonly property real preferredHeight: rowStride * 5.5 - rowSpacing
            readonly property real minimumHeight: rowStride * 2.5 - rowSpacing
            // Room left on screen after everything else in the card.
            readonly property real screenBudget: panel.availableCardHeight - panel.verticalContentInset
              - hero.implicitHeight - footer.implicitHeight - panel.gap * 4 - 2
              - sessionSection.implicitHeight - securitySection.implicitHeight - body.spacing * 2
              - accountsHeader.implicitHeight - accountsSection.spacing
            readonly property real maxVisibleHeight: panel.availableCardHeight > 0
              ? Math.max(minimumHeight, Math.min(preferredHeight, screenBudget))
              : preferredHeight
            readonly property real scrollGutter: interactive ? Style.space(10) : 0

            width: parent.width
            height: Math.min(contentHeight, maxVisibleHeight)
            visible: count > 0
            clip: true
            spacing: rowSpacing
            interactive: contentHeight > height + 1
            boundsBehavior: Flickable.StopAtBounds
            model: panel.host ? panel.host.visibleAccounts : []
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: ProviderRow {
              required property var modelData
              width: accountList.width - accountList.scrollGutter
              account: modelData
              nowMs: panel.nowMs
              foreground: panel.fg
              fontFamily: panel.fontFamily
            }
          }

          // Never shown; sizes the list viewport from a real row so the cap
          // follows the theme's font sizes.
          ProviderRow {
            id: rowMetrics
            visible: false
            width: parent.width
            account: ({ provider: "github", name: "Provider", identity: "identity", plan: "Plan", status: "connected" })
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }

          Text {
            width: parent.width
            visible: !panel.host || panel.host.visibleAccounts.length === 0
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: panel.probe && !panel.probe.hasFull
              ? (panel.probe.error !== "" ? panel.probe.error : "Scanning…")
              : "No signed-in accounts found on this machine"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- Keys & security
        Column {
          id: securitySection
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "KEYS & SECURITY"
            foreground: panel.fg
            fontFamily: panel.fontFamily
          }

          BorderSurface {
            width: parent.width
            implicitHeight: securityColumn.implicitHeight + Style.space(10) * 2
            color: Style.normalFillFor(panel.fg, Color.accent)
            borderSpec: Border.controlSpec("normal", panel.fg, Color.accent)
            radius: Style.cornerRadius

            Column {
              id: securityColumn
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              SecurityRow {
                icon: Format.glyph("key")
                label: "SSH keys"
                value: panel.sshValue
                actionText: panel.security && panel.sshKeys.length === 0 ? "Generate" : ""
                actionTooltip: "Create an ed25519 key in a terminal"
                hasCursor: panel.hasCursor("ssh")
                foreground: panel.fg
                fontFamily: panel.fontFamily
                onActionTriggered: panel.trigger("ssh")
                onActionHovered: panel.hoverCursor("ssh")
              }
              SecurityRow {
                icon: Format.glyph("certificate")
                label: "GPG keys"
                value: panel.gpgValue
                actionText: panel.security && panel.gpgKeys.length === 0 ? "Generate" : ""
                actionTooltip: "Run gpg --full-generate-key in a terminal"
                hasCursor: panel.hasCursor("gpg")
                foreground: panel.fg
                fontFamily: panel.fontFamily
                onActionTriggered: panel.trigger("gpg")
                onActionHovered: panel.hoverCursor("gpg")
              }
              SecurityRow {
                icon: panel.keyring && panel.keyring.locked === false ? Format.glyph("lockOpen") : Format.glyph("lock")
                label: "Keyring"
                value: panel.keyringValue
                warn: !!panel.keyring && (!panel.keyring.service || !panel.keyring.collection)
                foreground: panel.fg
                fontFamily: panel.fontFamily
              }
              SecurityRow {
                icon: Format.glyph("fingerprint")
                label: "Fingerprint"
                value: panel.fingerprintValue
                actionText: panel.fingerprintNeedsSetup ? "Set up" : ""
                actionTooltip: "Enroll a fingerprint (omarchy setup security fingerprint)"
                hasCursor: panel.hasCursor("fingerprint")
                foreground: panel.fg
                fontFamily: panel.fontFamily
                onActionTriggered: panel.trigger("fingerprint")
                onActionHovered: panel.hoverCursor("fingerprint")
              }
            }
          }
        }
      }
    }

    PanelSeparator {
      id: bottomRule
      anchors.bottom: footer.top
      anchors.bottomMargin: panel.gap
      foreground: panel.fg
    }

    // ---- Footer
    Row {
      id: footer
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.space(6)

      readonly property real cellWidth: (width - spacing * 2) / 3

      Button {
        width: footer.cellWidth
        iconText: Format.glyph("lock")
        text: "Lock"
        tooltipText: "Lock the screen"
        iconSize: Style.font.title
        fontSize: Style.font.bodySmall
        foreground: panel.fg
        fontFamily: panel.fontFamily
        bordered: true
        hasCursor: panel.hasCursor("lock")
        onClicked: panel.trigger("lock")
        onHovered: function(h) { if (h) panel.hoverCursor("lock") }
      }
      Button {
        width: footer.cellWidth
        iconText: Format.glyph("logout")
        text: "Log out"
        tooltipText: "Close windows and end the session"
        iconSize: Style.font.title
        fontSize: Style.font.bodySmall
        foreground: panel.fg
        accent: Color.urgent
        fontFamily: panel.fontFamily
        bordered: true
        hasCursor: panel.hasCursor("logout")
        onClicked: panel.trigger("logout")
        onHovered: function(h) { if (h) panel.hoverCursor("logout") }
      }
      Button {
        width: footer.cellWidth
        iconText: Format.glyph("refresh")
        iconSpinning: !!panel.probe && panel.probe.loading
        text: "Refresh"
        tooltipText: "Re-scan accounts and keys (r)"
        iconSize: Style.font.title
        fontSize: Style.font.bodySmall
        foreground: panel.fg
        fontFamily: panel.fontFamily
        bordered: true
        hasCursor: panel.hasCursor("refresh")
        onClicked: panel.trigger("refresh")
        onHovered: function(h) { if (h) panel.hoverCursor("refresh") }
      }
    }
  }

  // ---- Log out confirmation (same focus hand-off as Omarchy's power menu)
  Item {
    id: confirmKeys
    anchors.fill: parent
    visible: confirm.opened
    Keys.onPressed: function(event) { event.accepted = confirm.handleKey(event) }

    ConfirmDialog {
      id: confirm
      anchors.fill: parent
      opened: panel.pendingLogout
      message: "Log out now? Open windows will be closed."
      confirmText: "Log out"
      foreground: panel.fg
      fontFamily: panel.fontFamily
      onCanceled: panel.pendingLogout = false
      onConfirmed: {
        panel.pendingLogout = false
        if (panel.host) panel.host.logout()
      }
    }
  }
}
