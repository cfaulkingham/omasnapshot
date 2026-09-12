![OmaSnapshot — Take a photo. Record a video. Stay on the desktop. Webcam overlay for Omarchy.](preview.png)

# OmaSnapshot

Take a photo or record a video with your webcam from a floating Omarchy overlay.

Opening the overlay starts the camera immediately (including via
`omarchy-shell shell toggle`). The microphone is used only while a video
is recording.

Gamma other than 1.00 is written into saved files with `/usr/bin/ffmpeg`.
Without ffmpeg, captures still save and the overlay shows "Could not apply
gamma".

## Install

From this folder while developing:

```sh
./install.sh
```

That copies the plugin into `~/.config/omarchy/plugins/`, enables it, adds
**Trigger → Capture → Camera** to the Omarchy menu (when a webcam is present),
and binds **Super+Alt+C**. Super+Shift+C is already Calendar.

`./install.sh` edits `~/.config/hypr/bindings.lua` and
`~/.config/omarchy/extensions/omarchy-menu.jsonc` inside uniquely marked
blocks. It reloads Hyprland and rolls those files back if `hyprctl configerrors`
reports a problem. It refuses symlinks at those paths.

From a public repository:

```sh
omarchy plugin add https://github.com/cfaulkingham/omasnapshot.git --enable
./install.sh --desktop-only
```

`omarchy plugin add` does not run `install.sh`. Use `--desktop-only` for the
menu row and keybind after a git install, or add them by hand from the snippets
below. Gamma post-processing needs the `ffmpeg` package
(`omarchy pkg add ffmpeg` or `pacman -S ffmpeg`).

## Usage

- Open with Super+Alt+C, the Capture menu, or:

```sh
omarchy-shell shell toggle io.github.cfaulkingham.omasnapshot '{}'
```

- **Space** or the shutter takes a photo
- **R** or the red button starts and stops a video (microphone on while recording)
- **[** / **]** or the Gamma slider darken or lighten midtones. Right-click the slider (or double-click the label) to reset to 1.00. The same look is applied to saved photos and videos when ffmpeg is installed
- **Esc** or a click outside the card stops a recording if one is running, otherwise closes the overlay
- Live preview is mirrored; saved files are not
- Photos go to `$XDG_PICTURES_DIR` (usually `~/Pictures`)
- Videos go to `$XDG_VIDEOS_DIR` (usually `~/Videos`)

Override those folders with `OMARCHY_SCREENSHOT_DIR` and
`OMARCHY_SCREENRECORD_DIR`, the same variables Omarchy screenshots and
screen recordings use.

Gamma is stored at `~/.local/state/omasnapshot/settings.json`.

## Manual desktop integration

Menu (`~/.config/omarchy/extensions/omarchy-menu.jsonc`):

```jsonc
"trigger.capture.camera": {
  "icon": "󰄀",
  "label": "Camera",
  "description": "Take a photo or record a video with the webcam",
  "when": "omarchy-hw-webcam",
  "action": "omarchy-shell shell toggle io.github.cfaulkingham.omasnapshot '{}'"
}
```

Keybind (`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + ALT + C", "OmaSnapshot", "omarchy-shell shell toggle io.github.cfaulkingham.omasnapshot '{}'")
```

## Remove

```sh
./install.sh --remove-desktop
omarchy plugin remove io.github.cfaulkingham.omasnapshot
```

`--remove-desktop` deletes only the marked menu row and Super+Alt+C bind.
`omarchy plugin remove` deletes the plugin files.

These stay on disk until you delete them yourself:

- `~/.local/state/omasnapshot/settings.json` (gamma)
- Photos and videos already saved under Pictures/Videos (or the OMARCHY_* directories)

If you run `omarchy plugin remove` without `--remove-desktop`, the menu row and
keybind remain until you run `./install.sh --remove-desktop` or delete those
marked blocks by hand.

## Test

```sh
node test/paths-test.js
/usr/bin/python3 -I -S -B test/helper-test.py
omarchy plugin validate "$PWD"
qmllint -I "$OMARCHY_PATH/shell" Overlay.qml CameraSession.qml
```
