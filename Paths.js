// Save locations and capture filenames for OmaSnapshot.
// Qt-free so it can be unit tested under node.

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

function pad2(n) {
  n = Math.floor(Number(n) || 0)
  if (n < 0) n = 0
  return n < 10 ? "0" + n : String(n)
}

function captureName(date, ext) {
  var y = date.getFullYear()
  var m = pad2(date.getMonth() + 1)
  var d = pad2(date.getDate())
  var h = pad2(date.getHours())
  var min = pad2(date.getMinutes())
  var s = pad2(date.getSeconds())
  return "omasnapshot-" + y + m + d + "-" + h + min + s + "." + ext
}

function photoPath(env, date) {
  return picturesDir(env) + "/" + captureName(date, "jpg")
}

function videoPath(env, date) {
  return videosDir(env) + "/" + captureName(date, "mp4")
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

function toastMessage(kind, path) {
  var parts = String(path || "").split("/")
  var name = parts[parts.length - 1] || "capture"
  return "Saved " + name
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

function gammaApplyCommand(kind, path, gamma) {
  if (gammaIsNeutral(gamma)) return null
  var source = String(path || "")
  if (!source) return null
  var tmp = kind === "video" ? source + ".gamma-tmp.mp4" : source + ".gamma-tmp.jpg"
  var vf = "eq=gamma=" + String(clampGamma(gamma))
  var script = kind === "video"
    ? 'ffmpeg -y -hide_banner -loglevel error -i "$1" -vf "$2" -c:a copy "$3" && mv -f "$3" "$1"'
    : 'ffmpeg -y -hide_banner -loglevel error -i "$1" -vf "$2" -q:v 2 "$3" && mv -f "$3" "$1"'
  return ["bash", "-c", script, "omasnapshot-gamma", source, vf, tmp]
}

if (typeof module !== "undefined") {
  module.exports = {
    picturesDir: picturesDir,
    videosDir: videosDir,
    captureName: captureName,
    photoPath: photoPath,
    videoPath: videoPath,
    fileUrl: fileUrl,
    localPath: localPath,
    formatElapsed: formatElapsed,
    toastMessage: toastMessage,
    displayPath: displayPath,
    canTakePhoto: canTakePhoto,
    canToggleRecord: canToggleRecord,
    escapeCloses: escapeCloses,
    clampGamma: clampGamma,
    gammaIsNeutral: gammaIsNeutral,
    gammaLabel: gammaLabel,
    gammaApplyCommand: gammaApplyCommand
  }
}
