// Save locations and capture filenames for OmaSnapshot.
// Qt-free so it can be unit tested under node.

var PYTHON = "/usr/bin/python3"
var MKDIR = "/usr/bin/mkdir"
var MAX_PATH = 4096
var MAX_PLAIN = 200

function stripSlash(value) {
  var path = String(value || "")
  while (path.length > 1 && path.charAt(path.length - 1) === "/")
    path = path.slice(0, -1)
  return path
}

function expandHome(value, home) {
  var path = String(value || "")
  var root = String(home || "")
  if (!path) return ""
  if (path.indexOf("$HOME") === 0) return root + path.slice(5)
  if (path.charAt(0) === "~") return root + path.slice(1)
  return path
}

function firstPath(env, keys, fallback) {
  env = env || {}
  var home = env.HOME || ""
  for (var i = 0; i < keys.length; i++) {
    var raw = env[keys[i]]
    if (typeof raw === "string" && raw.length > 0)
      return stripSlash(expandHome(raw, home))
  }
  return stripSlash(home + fallback)
}

function picturesDir(env) {
  return firstPath(env, ["OMARCHY_SCREENSHOT_DIR", "XDG_PICTURES_DIR"], "/Pictures")
}

function videosDir(env) {
  return firstPath(env, ["OMARCHY_SCREENRECORD_DIR", "XDG_VIDEOS_DIR"], "/Videos")
}

function usableAbsPath(path) {
  var p = String(path || "")
  if (!p || p.charAt(0) !== "/" || p.length > MAX_PATH)
    return false
  if (p.indexOf("\0") !== -1 || p.indexOf("\r") !== -1 || p.indexOf("\n") !== -1)
    return false
  var parts = p.split("/")
  for (var i = 0; i < parts.length; i++) {
    if (i === 0 && parts[i] === "")
      continue
    if (!parts[i] || parts[i] === "." || parts[i] === "..")
      return false
  }
  return true
}

function pathInside(path, dir) {
  var p = stripSlash(String(path || ""))
  var d = stripSlash(String(dir || ""))
  if (!usableAbsPath(p) || !usableAbsPath(d))
    return false
  return p === d || p.indexOf(d + "/") === 0
}

function isCapturePath(kind, path, env) {
  var dir = kind === "video" ? videosDir(env) : picturesDir(env)
  return pathInside(path, dir)
}

function pad2(n) {
  n = Math.floor(Number(n) || 0)
  if (n < 0) n = 0
  return n < 10 ? "0" + n : String(n)
}

function captureNonce() {
  var n = Math.floor(Math.random() * 0x100000000)
  var s = n.toString(16)
  while (s.length < 8)
    s = "0" + s
  return s
}

function captureName(date, ext, nonce) {
  var y = date.getFullYear()
  var m = pad2(date.getMonth() + 1)
  var d = pad2(date.getDate())
  var h = pad2(date.getHours())
  var min = pad2(date.getMinutes())
  var s = pad2(date.getSeconds())
  var extra = nonce ? "-" + String(nonce) : ""
  return "omasnapshot-" + y + m + d + "-" + h + min + s + extra + "." + ext
}

function photoPath(env, date, nonce) {
  return picturesDir(env) + "/" + captureName(date, "jpg", nonce)
}

function videoPath(env, date, nonce) {
  return videosDir(env) + "/" + captureName(date, "mp4", nonce)
}

function fileUrl(path) {
  var value = String(path || "")
  if (value.indexOf("file:") === 0) return value
  return "file://" + value
}

function localPath(url) {
  var value = String(url || "")
  if (value.indexOf("file://") === 0) {
    var rest = value.slice(7)
    if (rest.indexOf("localhost/") === 0) rest = rest.slice(9)
    if (rest.charAt(0) !== "/") rest = "/" + rest
    try {
      return decodeURIComponent(rest)
    } catch (e) {
      return rest
    }
  }
  return value
}

function formatElapsed(ms) {
  var total = Math.max(0, Math.floor(Number(ms) / 1000) || 0)
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var seconds = total % 60
  if (hours > 0) return String(hours) + ":" + pad2(minutes) + ":" + pad2(seconds)
  return pad2(minutes) + ":" + pad2(seconds)
}

function plain(value, maxLen) {
  var limit = Number(maxLen)
  if (!isFinite(limit) || limit <= 0)
    limit = MAX_PLAIN
  var s = String(value || "")
  var out = ""
  for (var i = 0; i < s.length && out.length < limit; i++) {
    var c = s.charCodeAt(i)
    var ch = s.charAt(i)
    if (c < 32 || c === 127 || (c >= 0x80 && c <= 0x9f))
      continue
    if (c >= 0x202a && c <= 0x202e)
      continue
    if (c >= 0x2066 && c <= 0x2069)
      continue
    if (ch === "<" || ch === ">" || ch === "&")
      continue
    out += ch
  }
  return out
}

function toastMessage(kind, path) {
  var parts = String(path || "").split("/")
  var name = parts[parts.length - 1] || "capture"
  return "Saved " + plain(name, 80)
}

function displayPath(path, home) {
  var value = String(path || "")
  var root = String(home || "")
  if (root && value.indexOf(root) === 0) return "~" + value.slice(root.length)
  return value
}

function canTakePhoto(cameraActive, recording, ready) {
  return cameraActive === true && recording !== true && ready === true
}

function canToggleRecord(cameraActive, recording) {
  return cameraActive === true || recording === true
}

function escapeCloses(recording) {
  return recording !== true
}

function clampGamma(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  if (n < 0.5) return 0.5
  if (n > 2) return 2
  return Math.round(n * 20) / 20
}

function gammaIsNeutral(value) {
  return clampGamma(value) === 1
}

function gammaLabel(value) {
  return clampGamma(value).toFixed(2)
}

function helperCommand(helperPath, args) {
  if (!usableAbsPath(helperPath))
    return null
  var cmd = [PYTHON, "-I", "-S", helperPath]
  for (var i = 0; i < args.length; i++)
    cmd.push(String(args[i]))
  return cmd
}

function gammaCommand(helperPath, kind, path, gamma) {
  if (gammaIsNeutral(gamma))
    return null
  if (kind !== "photo" && kind !== "video")
    return null
  if (!usableAbsPath(path))
    return null
  return helperCommand(helperPath, ["gamma", kind, path, gammaLabel(gamma)])
}

function ensureDirCommand(dir) {
  if (!usableAbsPath(dir))
    return null
  return [MKDIR, "-p", "--", dir]
}

if (typeof module !== "undefined") {
  module.exports = {
    picturesDir: picturesDir,
    videosDir: videosDir,
    usableAbsPath: usableAbsPath,
    pathInside: pathInside,
    isCapturePath: isCapturePath,
    captureNonce: captureNonce,
    captureName: captureName,
    photoPath: photoPath,
    videoPath: videoPath,
    fileUrl: fileUrl,
    localPath: localPath,
    formatElapsed: formatElapsed,
    plain: plain,
    toastMessage: toastMessage,
    displayPath: displayPath,
    canTakePhoto: canTakePhoto,
    canToggleRecord: canToggleRecord,
    escapeCloses: escapeCloses,
    clampGamma: clampGamma,
    gammaIsNeutral: gammaIsNeutral,
    gammaLabel: gammaLabel,
    helperCommand: helperCommand,
    gammaCommand: gammaCommand,
    ensureDirCommand: ensureDirCommand
  }
}
