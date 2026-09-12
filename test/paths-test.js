const assert = require("assert")
const Paths = require("../Paths.js")

const env = {
  HOME: "/home/colin",
  OMARCHY_SCREENSHOT_DIR: "",
  OMARCHY_SCREENRECORD_DIR: "",
  XDG_PICTURES_DIR: "",
  XDG_VIDEOS_DIR: ""
}

assert.strictEqual(Paths.picturesDir(env), "/home/colin/Pictures")
assert.strictEqual(Paths.videosDir(env), "/home/colin/Videos")

assert.strictEqual(
  Paths.picturesDir({ HOME: "/home/colin", OMARCHY_SCREENSHOT_DIR: "/shots" }),
  "/shots"
)
assert.strictEqual(
  Paths.videosDir({ HOME: "/home/colin", OMARCHY_SCREENRECORD_DIR: "/clips/" }),
  "/clips"
)

assert.strictEqual(
  Paths.picturesDir({ HOME: "/home/colin", XDG_PICTURES_DIR: "$HOME/Pictures" }),
  "/home/colin/Pictures"
)
assert.strictEqual(
  Paths.videosDir({ HOME: "/home/colin", XDG_VIDEOS_DIR: "~/Videos" }),
  "/home/colin/Videos"
)

const date = new Date(2026, 8, 12, 14, 5, 9)
assert.strictEqual(Paths.captureName(date, "jpg"), "omasnapshot-20260912-140509.jpg")
assert.strictEqual(Paths.captureName(date, "mp4"), "omasnapshot-20260912-140509.mp4")
assert.strictEqual(
  Paths.captureName(date, "jpg", "a1b2c3d4"),
  "omasnapshot-20260912-140509-a1b2c3d4.jpg"
)
assert.strictEqual(
  Paths.photoPath({ HOME: "/home/colin" }, date),
  "/home/colin/Pictures/omasnapshot-20260912-140509.jpg"
)
assert.strictEqual(
  Paths.videoPath({ HOME: "/home/colin" }, date, "deadbeef"),
  "/home/colin/Videos/omasnapshot-20260912-140509-deadbeef.mp4"
)

assert.match(Paths.captureNonce(), /^[0-9a-f]{8}$/)

assert.strictEqual(Paths.fileUrl("/home/colin/Videos/clip.mp4"), "file:///home/colin/Videos/clip.mp4")
assert.strictEqual(Paths.fileUrl("file:///tmp/a.jpg"), "file:///tmp/a.jpg")
assert.strictEqual(Paths.localPath("file:///home/colin/Videos/clip.mp4"), "/home/colin/Videos/clip.mp4")
assert.strictEqual(Paths.localPath("/tmp/a.jpg"), "/tmp/a.jpg")

assert.strictEqual(Paths.usableAbsPath("/home/colin/Pictures"), true)
assert.strictEqual(Paths.usableAbsPath("/home/colin/Pictures/omasnapshot-1.jpg"), true)
assert.strictEqual(Paths.usableAbsPath("/home/colin/../etc/passwd"), false)
assert.strictEqual(Paths.usableAbsPath("/home/colin/foo/./bar"), false)
assert.strictEqual(Paths.usableAbsPath("relative"), false)
assert.strictEqual(Paths.usableAbsPath("/tmp/a.jpg\n"), false)
assert.strictEqual(Paths.usableAbsPath("/foo//bar"), false)
assert.strictEqual(Paths.pathInside("/home/colin/Pictures/x.jpg", "/home/colin/Pictures"), true)
assert.strictEqual(Paths.pathInside("/home/colin/Pictures_evil/x.jpg", "/home/colin/Pictures"), false)
assert.strictEqual(Paths.pathInside("/home/colin/Pictures/../Videos/x.mp4", "/home/colin/Pictures"), false)
assert.strictEqual(
  Paths.isCapturePath("photo", "/home/colin/Pictures/omasnapshot-1.jpg", { HOME: "/home/colin" }),
  true
)
assert.strictEqual(
  Paths.isCapturePath("photo", "/tmp/omasnapshot-1.jpg", { HOME: "/home/colin" }),
  false
)

assert.strictEqual(Paths.formatElapsed(0), "00:00")
assert.strictEqual(Paths.formatElapsed(1000), "00:01")
assert.strictEqual(Paths.formatElapsed(65000), "01:05")
assert.strictEqual(Paths.formatElapsed(3600000), "1:00:00")
assert.strictEqual(Paths.formatElapsed(-5), "00:00")

assert.strictEqual(
  Paths.toastMessage("photo", "/home/colin/Pictures/omasnapshot-20260912-140509.jpg"),
  "Saved omasnapshot-20260912-140509.jpg"
)
assert.strictEqual(
  Paths.toastMessage("photo", "/home/colin/Pictures/<img src=x>.jpg"),
  "Saved img src=x.jpg"
)
assert.strictEqual(Paths.plain("hello\nworld<script>", 80), "helloworldscript")
assert.strictEqual(Paths.plain("<img src=\"http://127.0.0.1/x\">", 80), 'img src="http://127.0.0.1/x"')
assert.strictEqual(
  Paths.displayPath("/home/colin/Pictures/x.jpg", "/home/colin"),
  "~/Pictures/x.jpg"
)

assert.strictEqual(Paths.canTakePhoto(true, false, true), true)
assert.strictEqual(Paths.canTakePhoto(true, true, true), false)
assert.strictEqual(Paths.canTakePhoto(false, false, true), false)
assert.strictEqual(Paths.canTakePhoto(true, false, false), false)
assert.strictEqual(Paths.canToggleRecord(true, false), true)
assert.strictEqual(Paths.canToggleRecord(false, false), false)
assert.strictEqual(Paths.escapeCloses(false), true)
assert.strictEqual(Paths.escapeCloses(true), false)

assert.strictEqual(Paths.clampGamma(1), 1)
assert.strictEqual(Paths.clampGamma("1.5"), 1.5)
assert.strictEqual(Paths.clampGamma(0.1), 0.5)
assert.strictEqual(Paths.clampGamma(9), 2)
assert.strictEqual(Paths.clampGamma("nope"), 1)
assert.strictEqual(Paths.clampGamma(1.04), 1.05)
assert.strictEqual(Paths.gammaIsNeutral(1), true)
assert.strictEqual(Paths.gammaIsNeutral(1.5), false)
assert.strictEqual(Paths.gammaLabel(1.5), "1.50")
assert.strictEqual(Paths.gammaCommand("/opt/plugin/bin/omasnapshot.py", "photo", "/tmp/a.jpg", 1), null)
assert.deepStrictEqual(
  Paths.gammaCommand("/opt/plugin/bin/omasnapshot.py", "photo", "/home/colin/Pictures/a.jpg", 1.5),
  ["/usr/bin/python3", "-I", "-S", "/opt/plugin/bin/omasnapshot.py", "gamma", "photo", "/home/colin/Pictures/a.jpg", "1.50"]
)
assert.strictEqual(
  Paths.gammaCommand("/opt/plugin/bin/omasnapshot.py", "photo", "/home/colin/../etc/passwd", 1.5),
  null
)
assert.deepStrictEqual(
  Paths.ensureDirCommand("/home/colin/Pictures"),
  ["/usr/bin/mkdir", "-p", "--", "/home/colin/Pictures"]
)
assert.strictEqual(Paths.ensureDirCommand("/home/colin/../Pictures"), null)
assert.deepStrictEqual(
  Paths.helperCommand("/opt/plugin/bin/omasnapshot.py", ["read-settings"]),
  ["/usr/bin/python3", "-I", "-S", "/opt/plugin/bin/omasnapshot.py", "read-settings"]
)
assert.strictEqual(Paths.helperCommand("omasnapshot.py", ["read-settings"]), null)

console.log("paths-test ok")
