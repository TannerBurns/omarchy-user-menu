import QtQuick
import Quickshell
import Quickshell.Io

// Runs bin/user-menu-probe and holds what it reported. Nothing polls in the
// background: the widget asks for identity once at load and for everything
// each time the menu opens. The clock below only advances "now" so durations
// tick while the menu is visible.
Item {
  id: svc
  visible: false

  property var user: null
  property var session: null
  property var accounts: []
  property var security: null
  property var errors: []
  property bool hasFull: false
  property string error: ""
  property double nowMs: Date.now()
  property bool fullQueued: false
  // Fictional data for screenshots (the widget's `demo` setting).
  property bool demo: false

  readonly property var extraArgs: demo ? ["--demo"] : []

  readonly property bool loading: identityProc.running || fullProc.running

  readonly property string probePath: {
    var url = String(Qt.resolvedUrl("bin/user-menu-probe"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  function tick() { nowMs = Date.now() }

  onDemoChanged: {
    refreshIdentity()
    refreshAll()
  }

  function refreshIdentity() {
    if (!identityProc.running) identityProc.running = true
  }

  function refreshAll() {
    tick()
    if (fullProc.running) { fullQueued = true; return }
    fullProc.running = true
  }

  function ingest(text) {
    var doc
    try {
      doc = JSON.parse(text)
    } catch (e) {
      error = "The probe returned unreadable output"
      return
    }
    if (!doc || doc.schemaVersion !== 1) {
      error = "Unsupported probe output"
      return
    }
    if (doc.error) {
      error = doc.error === "redaction-guard" ? "Probe output withheld by the redaction guard" : "The probe failed"
      return
    }
    error = ""
    if (doc.user) user = doc.user
    if (doc.session) session = doc.session
    if (doc.accounts) { accounts = doc.accounts; hasFull = true }
    if (doc.security) security = doc.security
    if (doc.errors) errors = doc.errors
    tick()
  }

  // The outer timeout bounds the whole run; each provider inside has its own.
  Process {
    id: identityProc
    command: ["timeout", "-k", "2", "10", "bash", svc.probePath, "--section", "user,session"].concat(svc.extraArgs)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: svc.ingest(text)
    }
  }

  Process {
    id: fullProc
    command: ["timeout", "-k", "2", "20", "bash", svc.probePath].concat(svc.extraArgs)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: svc.ingest(text)
    }
    onExited: function(exitCode) {
      if (svc.fullQueued) {
        svc.fullQueued = false
        Qt.callLater(svc.refreshAll)
      }
    }
  }

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: svc.tick()
  }
}
