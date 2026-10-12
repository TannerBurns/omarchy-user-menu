import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Format.js" as Format

// tannerburns.user-menu: the logged-in user in the bar, and a menu with the
// session, the third-party accounts signed in on this machine, key/keyring
// status, and lock / log out.
//
// Keybinding: omarchy-shell shell toggle tannerburns.user-menu
Panel {
  id: root
  moduleName: "tannerburns.user-menu"
  // The shell's `shell toggle <id>` reaches the focused monitor's instance;
  // a per-instance IpcHandler would collide across monitors.
  manageIpc: false

  readonly property bool vertical: bar ? bar.vertical : false

  // ---------------------------------------------------------------- settings
  // The shell stores `omarchy bar set` values as strings and never applies the
  // manifest defaults, so every read coerces and carries its own fallback.

  readonly property var labelModes: ["username", "fullname", "hostname", "userhost", "none"]
  readonly property string labelMode: {
    var v = String(setting("label", "username")).trim().toLowerCase()
    return labelModes.indexOf(v) >= 0 ? v : "username"
  }
  readonly property bool showIcon: Format.toBool(setting("showIcon", true), true)
  readonly property bool showSignedOut: Format.toBool(setting("showSignedOut", true), true)
  readonly property bool confirmLogout: Format.toBool(setting("confirmLogout", true), true)
  readonly property var hiddenProviders: Format.parseList(setting("hiddenProviders", ""))

  // ---------------------------------------------------------------- identity

  readonly property string username: service.user ? service.user.username
    : (Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user")
  readonly property string hostName: service.user ? service.user.host : ""
  readonly property string fullName: service.user && service.user.fullName ? service.user.fullName : username
  readonly property string initials: service.user && service.user.initials ? service.user.initials : username.substring(0, 2).toUpperCase()
  readonly property string userHost: hostName !== "" ? username + "@" + hostName : username
  readonly property double loginEpochMs: service.session && service.session.loginEpochMs ? service.session.loginEpochMs : 0
  readonly property string loggedInFor: loginEpochMs > 0 ? Format.duration(service.nowMs - loginEpochMs) : ""

  readonly property var visibleAccounts: (service.accounts || []).filter(function(a) {
    if (root.hiddenProviders.indexOf(String(a.provider)) >= 0) return false
    return root.showSignedOut || a.status !== "signed-out"
  })

  // ---------------------------------------------------------------- bar label

  readonly property bool iconOnly: vertical || labelMode === "none"
  readonly property string labelText: {
    var t = labelMode === "fullname" ? fullName
      : labelMode === "hostname" ? (hostName || username)
      : labelMode === "userhost" ? userHost
      : username
    return Format.truncate(t, 24)
  }
  readonly property string barText: iconOnly
    ? (showIcon ? Format.glyph("user") : initials)
    : (showIcon ? Format.glyph("user") + " " : "") + labelText
  readonly property string tooltip: {
    var lines = [fullName + " (" + userHost + ")"]
    if (loggedInFor !== "") {
      var kind = Format.sessionKind(service.session)
      lines.push("Logged in " + loggedInFor + (kind !== "" ? " · " + kind : ""))
    }
    return lines.join("\n")
  }

  // Lets the bar's open-panel dot track the painted label, not the padded slot.
  readonly property real openPanelIndicatorWidth: iconOnly ? 0 : button.labelWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------------------- actions

  function refresh() { service.refreshAll() }

  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    var current = root.settings || {}
    for (var k in current) if (k !== "id") entry[k] = current[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cycleLabel() {
    var next = labelModes[(labelModes.indexOf(labelMode) + 1) % labelModes.length]
    persistSetting("label", next)
  }

  function lock() {
    root.close()
    Util.execArgv(["omarchy-system-lock"])
  }

  function logout() {
    root.close()
    Util.execArgv(["omarchy-system-logout"])
  }

  // Interactive setup runs in Omarchy's floating terminal. execArgv keeps the
  // command a single argument; the terminal wrapper runs it through a shell.
  function launchSetup(kind) {
    var email = service.user && service.user.git ? service.user.git.email : ""
    var comment = email !== "" ? email : root.userHost
    var cmd = kind === "ssh" ? "ssh-keygen -t ed25519 -C " + Util.shellQuote(comment)
      : kind === "gpg" ? "gpg --full-generate-key"
      : kind === "fingerprint" ? "omarchy-setup-security-fingerprint"
      : ""
    if (cmd === "") return
    root.close()
    Util.execArgv(["omarchy-launch-floating-terminal-with-presentation", cmd])
  }

  onOpenedChanged: if (opened) service.refreshAll()
  Component.onCompleted: service.refreshIdentity()

  ProbeService {
    id: service
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    fontSize: root.iconOnly && root.showIcon ? Style.bar.iconFont : Style.font.body
    horizontalMargin: 8.75
    tooltipText: root.tooltip
    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleLabel()
      else if (b === Qt.MiddleButton) service.refreshIdentity()
      else root.toggle()
    }
  }

  UserPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    host: root
    probe: service
  }
}
