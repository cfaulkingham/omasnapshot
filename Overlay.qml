import QtQuick
import QtMultimedia
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Paths.js" as Paths

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool pendingDismiss: false
  property string toast: ""
  property real gamma: 1
  property string homeDir: Quickshell.env("HOME") || ""
  property string picturesOverride: Quickshell.env("OMARCHY_SCREENSHOT_DIR") || ""
  property string videosOverride: Quickshell.env("OMARCHY_SCREENRECORD_DIR") || ""
  property string xdgPictures: Quickshell.env("XDG_PICTURES_DIR") || ""
  property string xdgVideos: Quickshell.env("XDG_VIDEOS_DIR") || ""

  readonly property var pathEnv: ({
    HOME: root.homeDir,
    OMARCHY_SCREENSHOT_DIR: root.picturesOverride,
    OMARCHY_SCREENRECORD_DIR: root.videosOverride,
    XDG_PICTURES_DIR: root.xdgPictures,
    XDG_VIDEOS_DIR: root.xdgVideos
  })
  readonly property string pluginId: (root.manifest && root.manifest.id) || "io.github.cfaulkingham.omasnapshot"
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.family
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int previewWidth: Style.space(720)
  readonly property int previewHeight: Math.round(previewWidth * 9 / 16)
  readonly property int cardWidth: previewWidth + contentMargin * 2
  readonly property bool recording: session.recording
  readonly property bool canPhoto: Paths.canTakePhoto(session.cameraActive, session.recording, session.readyForCapture)
  readonly property bool canRecord: Paths.canToggleRecord(session.cameraActive, session.recording)

  function open(payloadJson) {
    root.pendingDismiss = false
    root.toast = ""
    root.opened = true
    session.sessionActive = true
    Qt.callLater(function() {
      if (root.opened)
        keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.pendingDismiss = false
    session.sessionActive = false
    root.opened = false
    root.toast = ""
  }

  function dismiss() {
    if (session.recording) {
      root.pendingDismiss = true
      session.toggleRecord()
      return
    }
    session.sessionActive = false
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  function showToast(kind, path) {
    root.toast = Paths.toastMessage(kind, path)
    toastTimer.restart()
  }

  function handleEscape() {
    if (!Paths.escapeCloses(session.recording)) {
      session.toggleRecord()
      return
    }
    root.dismiss()
  }

  function persistGamma() {
    settingsFile.setText(JSON.stringify({ gamma: Paths.clampGamma(root.gamma) }) + "\n")
  }

  function nudgeGamma(delta) {
    root.gamma = Paths.clampGamma(root.gamma + delta)
    root.persistGamma()
  }

  FileView {
    id: settingsFile
    path: root.homeDir + "/.config/omarchy/omasnapshot.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(text() || "{}")
        root.gamma = Paths.clampGamma(data.gamma)
      } catch (e) {
        root.gamma = 1
      }
    }
    onLoadFailed: root.gamma = 1
  }

  CameraSession {
    id: session
    env: root.pathEnv
    gamma: root.gamma
    videoOutput: preview
    onSaved: function(kind, path) {
      root.showToast(kind, path)
      if (kind === "photo")
        flashAnim.restart()
      if (root.pendingDismiss && !session.recording)
        Qt.callLater(root.dismiss)
    }
    onFailed: function(message) {
      root.toast = message
      toastTimer.restart()
    }
    onRecordingChanged: {
      if (root.pendingDismiss && !session.recording)
        Qt.callLater(root.dismiss)
    }
  }

  Timer {
    id: toastTimer
    interval: 2500
    onTriggered: root.toast = ""
  }

  Process {
    command: ["xdg-user-dir", "PICTURES"]
    running: root.picturesOverride === "" && root.xdgPictures === ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value)
          root.xdgPictures = value
      }
    }
  }

  Process {
    command: ["xdg-user-dir", "VIDEOS"]
    running: root.videosOverride === "" && root.xdgVideos === ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value)
          root.xdgVideos = value
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-omasnapshot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: content.implicitHeight + contentTopInset + contentBottomInset
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      scale: Math.min(1,
        (panel.width - Style.gapsOut * 4) / Math.max(1, width),
        (panel.height - Style.gapsOut * 4) / Math.max(1, height))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.handleEscape()
            event.accepted = true
          } else if (event.key === Qt.Key_Space) {
            session.takePhoto()
            event.accepted = true
          } else if (event.key === Qt.Key_R) {
            session.toggleRecord()
            event.accepted = true
          } else if (event.key === Qt.Key_BracketLeft) {
            root.nudgeGamma(-0.05)
            event.accepted = true
          } else if (event.key === Qt.Key_BracketRight) {
            root.nudgeGamma(0.05)
            event.accepted = true
          }
        }
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: card.contentLeftInset
        anchors.topMargin: card.contentTopInset
        width: root.previewWidth
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Esc"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dismiss()
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            visible: session.recording

            Rectangle {
              width: Style.space(8)
              height: Style.space(8)
              radius: width / 2
              color: Color.urgent
              anchors.verticalCenter: parent.verticalCenter
              SequentialAnimation on opacity {
                running: session.recording
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 550 }
                NumberAnimation { to: 1; duration: 550 }
              }
            }

            Text {
              text: "REC  " + session.elapsedText
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: session.cameraName
            color: root.foreground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width * 0.38)
            horizontalAlignment: Text.AlignRight
          }
        }

        Item {
          id: previewFrame
          width: root.previewWidth
          height: root.previewHeight
          clip: true

          Rectangle {
            anchors.fill: parent
            color: "black"
            radius: Math.max(0, root.cornerRadius - Style.space(4))
          }

          VideoOutput {
            id: preview
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            mirrored: true
            visible: session.cameraActive && Paths.gammaIsNeutral(root.gamma)
            layer.enabled: !Paths.gammaIsNeutral(root.gamma)
            layer.smooth: true
          }

          GammaAdjust {
            anchors.fill: parent
            source: preview
            gamma: Math.max(0.0001, root.gamma)
            visible: session.cameraActive && !Paths.gammaIsNeutral(root.gamma)
          }

          Rectangle {
            id: flash
            anchors.fill: parent
            color: "white"
            opacity: 0
            SequentialAnimation {
              id: flashAnim
              NumberAnimation { target: flash; property: "opacity"; to: 0.72; duration: 50 }
              NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 180 }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: session.errorText !== "" || !session.hasCamera
            text: session.errorText || "No camera found"
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Text {
          width: parent.width
          height: Style.font.body + Style.space(2)
          text: session.applyingGamma ? "Applying gamma…" : root.toast
          color: root.foreground
          opacity: session.applyingGamma || root.toast !== "" ? 1 : 0
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }

        Row {
          width: parent.width
          spacing: Style.space(10)
          height: Math.max(Style.space(22), Style.font.body)

          Text {
            id: gammaName
            text: "Gamma"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onDoubleClicked: {
                root.gamma = 1
                root.persistGamma()
              }
            }
          }

          PanelSlider {
            width: parent.width - gammaName.width - gammaValue.width - Style.space(20)
            height: parent.height
            minimum: 0.5
            maximum: 2
            step: 0.05
            value: root.gamma
            trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
            fillColor: root.foreground
            knobColor: root.foreground
            tickColor: root.background
            onMoved: function(v) { root.gamma = Paths.clampGamma(v) }
            onReleased: function(v) {
              root.gamma = Paths.clampGamma(v)
              root.persistGamma()
            }
            onRightClicked: {
              root.gamma = 1
              root.persistGamma()
            }
          }

          Text {
            id: gammaValue
            width: Style.space(36)
            text: Paths.gammaLabel(root.gamma)
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(24)

          Item {
            id: shutter
            width: Style.space(64)
            height: Style.space(64)
            opacity: root.canPhoto ? 1 : 0.35

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "transparent"
              border.color: root.foreground
              border.width: 3
            }

            Rectangle {
              id: shutterInner
              width: Style.space(46)
              height: Style.space(46)
              radius: width / 2
              anchors.centerIn: parent
              color: root.foreground
            }

            MouseArea {
              anchors.fill: parent
              enabled: root.canPhoto
              cursorShape: Qt.PointingHandCursor
              onPressed: shutterInner.scale = 0.86
              onReleased: shutterInner.scale = 1
              onCanceled: shutterInner.scale = 1
              onClicked: session.takePhoto()
            }
          }

          Item {
            width: Style.space(56)
            height: Style.space(56)
            opacity: root.canRecord ? 1 : 0.35
            anchors.verticalCenter: shutter.verticalCenter

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "transparent"
              border.color: root.foreground
              border.width: 3
            }

            Rectangle {
              width: session.recording ? Style.space(20) : Style.space(32)
              height: session.recording ? Style.space(20) : Style.space(32)
              radius: session.recording ? Style.space(4) : width / 2
              anchors.centerIn: parent
              color: Color.urgent
            }

            MouseArea {
              anchors.fill: parent
              enabled: root.canRecord
              cursorShape: Qt.PointingHandCursor
              onClicked: session.toggleRecord()
            }
          }
        }

        Text {
          width: parent.width
          text: "Space photo   ·   R record   ·   [ ] gamma   ·   Esc close"
          color: root.foreground
          opacity: 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
