import QtQuick
import Quickshell
import qs.Ui

// Bar button for the overlay. Enabling the plugin places this on the bar,
// which is the launch path that does not depend on a keybind or menu edit.
BarWidget {
  id: root
  moduleName: "io.github.cfaulkingham.omasnapshot"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function launch() {
    var shell = root.bar ? root.bar.shell : null
    if (shell && typeof shell.toggle === "function") {
      shell.toggle(root.moduleName, "{}")
      return
    }
    Quickshell.execDetached([
      "/usr/bin/omarchy-shell",
      "shell",
      "toggle",
      root.moduleName,
      "{}"
    ])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-camera, the same glyph as Trigger → Capture → Camera.
    text: "󰄀"
    tooltipText: "Camera"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton)
        root.launch()
    }
  }
}
