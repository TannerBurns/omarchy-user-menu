.pragma library
.import "Marks.js" as Marks

// Pure formatting helpers for the user menu. No theme values live here:
// colors and fonts stay declarative bindings in QML so theme switches apply live.

var MINUTE = 60000
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR

// Nerd Font codepoints for the menu's own UI (JetBrainsMono Nerd Font ships all of these).
var GLYPHS = {
  user: 0xF0009,        // nf-md-account_circle
  key: 0xF0306,         // nf-md-key
  certificate: 0xF0124, // nf-md-certificate
  lock: 0xF033E,        // nf-md-lock
  lockOpen: 0xF033F,    // nf-md-lock_open
  fingerprint: 0xF0237, // nf-md-fingerprint
  logout: 0xF0343,      // nf-md-logout
  refresh: 0xF0450      // nf-md-refresh
}

// Providers whose marks are in neither Simple Icons nor Lobe Icons; everything
// else ships an SVG (see scripts/icons.tsv), and unknown ids get a puzzle piece.
var PROVIDER_GLYPHS = {
  slack: 0xF198,        // nf-fa-slack
  heroku: 0xE77B        // nf-dev-heroku
}
var PUZZLE = 0xF0431    // nf-md-puzzle

function glyph(name) {
  var cp = GLYPHS[name]
  return cp ? String.fromCodePoint(cp) : ""
}

function providerGlyph(provider) {
  return String.fromCodePoint(PROVIDER_GLYPHS[String(provider)] || PUZZLE)
}

// Providers with a bundled monochrome mark in assets/<id>.svg (generated list).
function hasMark(provider) {
  return Marks.MARKS.indexOf(String(provider)) >= 0
}

// "3h 19m", "2d 4h", "45m", "<1m". Suspend-safe as long as both ends are wall clock.
function duration(ms) {
  var n = Number(ms)
  if (!isFinite(n) || n < 0) return ""
  if (n < MINUTE) return "<1m"
  var d = Math.floor(n / DAY)
  var h = Math.floor((n % DAY) / HOUR)
  var m = Math.floor((n % HOUR) / MINUTE)
  if (d > 0) return d + "d" + (h > 0 ? " " + h + "h" : "")
  if (h > 0) return h + "h" + (m > 0 ? " " + m + "m" : "")
  return m + "m"
}

// Coarser form for expiry countdowns: "3d", "5h", "20m".
function shortDuration(ms) {
  var n = Number(ms)
  if (!isFinite(n) || n <= 0) return ""
  if (n >= DAY) return Math.round(n / DAY) + "d"
  if (n >= HOUR) return Math.round(n / HOUR) + "h"
  return Math.max(1, Math.round(n / MINUTE)) + "m"
}

function truncate(text, max) {
  var s = String(text || "")
  return s.length > max ? s.substring(0, max - 1) + "…" : s
}

function capitalize(text) {
  var s = String(text || "")
  return s.length ? s.charAt(0).toUpperCase() + s.substring(1) : s
}

function statusWord(account, nowMs) {
  if (!account) return ""
  switch (account.status) {
  case "connected": return "Connected"
  case "expiring":
    var left = account.expiresEpochMs ? shortDuration(account.expiresEpochMs - nowMs) : ""
    return left ? "Expires in " + left : "Expiring"
  case "expired": return "Expired"
  case "signed-out": return "Signed out"
  }
  return capitalize(account.status)
}

// "Autologin (SDDM)", "SSH from host", "Console", "Greeter (GDM)".
function loginMethod(session) {
  if (!session || !session.available) return ""
  if (session.remote) return session.remoteHost ? "SSH from " + session.remoteHost : "Remote"
  var g = String(session.greeter || "")
  var name = g === "login" ? "Console" : (g.length <= 4 ? g.toUpperCase() : capitalize(g))
  if (session.autologin) return name ? "Autologin (" + name + ")" : "Autologin"
  if (g === "login") return "Console"
  return name ? "Greeter (" + name + ")" : ""
}

function sessionKind(session) {
  if (!session || !session.available) return ""
  var parts = []
  if (session.type) parts.push(session.type === "x11" ? "X11" : capitalize(session.type))
  if (session.desktop) parts.push(session.desktop)
  return parts.join(" · ")
}

function seatLine(session) {
  if (!session || !session.available) return ""
  var parts = []
  if (session.seat) parts.push(session.seat)
  if (session.tty) parts.push(session.tty)
  else if (session.vt) parts.push("VT " + session.vt)
  return parts.join(" · ")
}

function adminGroup(groups) {
  var list = groups || []
  var wanted = ["wheel", "sudo", "admin"]
  for (var i = 0; i < wanted.length; i++) if (list.indexOf(wanted[i]) >= 0) return wanted[i]
  return ""
}

function parseList(raw) {
  if (raw === undefined || raw === null) return []
  var items = raw instanceof Array ? raw : String(raw).split(/[,\s]+/)
  return items.map(function(s) { return String(s).trim().toLowerCase() }).filter(function(s) { return s.length > 0 })
}

function toBool(value, fallback) {
  if (typeof value === "boolean") return value
  if (value === undefined || value === null) return fallback
  var s = String(value).trim().toLowerCase()
  if (s === "true" || s === "1" || s === "yes" || s === "on") return true
  if (s === "false" || s === "0" || s === "no" || s === "off") return false
  return fallback
}
