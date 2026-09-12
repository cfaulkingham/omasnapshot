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
  Paths.photoPath({ HOME: "/home/colin" }, date),
  "/home/colin/Pictures/omasnapshot-20260912-140509.jpg"
)
assert.strictEqual(
  Paths.videoPath({ HOME: "/home/colin" }, date),
  "/home/colin/Videos/omasnapshot-20260912-140509.mp4"
)

assert.strictEqual(Paths.fileUrl("/home/colin/Videos/clip.mp4"), "file:///home/colin/Videos/clip.mp4")
assert.strictEqual(Paths.fileUrl("file:///tmp/a.jpg"), "file:///tmp/a.jpg")
assert.strictEqual(Paths.localPath("file:///home/colin/Videos/clip.mp4"), "/home/colin/Videos/clip.mp4")
assert.strictEqual(Paths.localPath("/tmp/a.jpg"), "/tmp/a.jpg")

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
assert.strictEqual(Paths.gammaApplyCommand("photo", "/tmp/a.jpg", 1), null)
assert.deepStrictEqual(
  Paths.gammaApplyCommand("photo", "/tmp/a.jpg", 1.5),
  ["bash", "-c", 'ffmpeg -y -hide_banner -loglevel error -i "$1" -vf "$2" -q:v 2 "$3" && mv -f "$3" "$1"', "omasnapshot-gamma", "/tmp/a.jpg", "eq=gamma=1.5", "/tmp/a.jpg.gamma-tmp.jpg"]
)
assert.deepStrictEqual(
  Paths.gammaApplyCommand("video", "/tmp/a.mp4", 0.5),
  ["bash", "-c", 'ffmpeg -y -hide_banner -loglevel error -i "$1" -vf "$2" -c:a copy "$3" && mv -f "$3" "$1"', "omasnapshot-gamma", "/tmp/a.mp4", "eq=gamma=0.5", "/tmp/a.mp4.gamma-tmp.mp4"]
)
assert.ok(Paths.gammaApplyCommand("photo", "/tmp/a.jpg", 1.5)[6].endsWith(".jpg"))
assert.ok(Paths.gammaApplyCommand("video", "/tmp/a.mp4", 0.5)[6].endsWith(".mp4"))

console.log("paths-test ok")
