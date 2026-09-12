import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import "Paths.js" as Paths

Item {
  id: root

  property var env: ({})
  property var videoOutput: null
  property bool sessionActive: false
  property real gamma: 1

  readonly property bool hasCamera: mediaDevices.videoInputs.length > 0
  readonly property bool hasMic: mediaDevices.audioInputs.length > 0
  readonly property bool cameraActive: camera.active && camera.error === Camera.NoError
  readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState
  readonly property bool readyForCapture: imageCapture.readyForCapture
  readonly property string cameraName: camera.cameraDevice.description || ""
  readonly property string elapsedText: Paths.formatElapsed(recorder.duration)
  readonly property string errorText: {
    if (!root.sessionActive)
      return ""
    if (!root.hasCamera)
      return "No camera found"
    if (camera.error !== Camera.NoError && camera.errorString)
      return camera.errorString
    if (recorder.error !== MediaRecorder.NoError && recorder.errorString)
      return recorder.errorString
    if (imageCapture.error !== ImageCapture.NoError && imageCapture.errorString)
      return imageCapture.errorString
    return ""
  }

  property int lastRecorderState: MediaRecorder.StoppedState
  property string pendingVideoPath: ""
  property string pendingPhotoPath: ""
  property string pendingGammaKind: ""
  property string pendingGammaPath: ""
  property bool applyingGamma: false

  signal saved(string kind, string path)
  signal failed(string message)

  function finishSave(kind, path) {
    var cmd = Paths.gammaApplyCommand(kind, path, root.gamma)
    if (!cmd) {
      root.saved(kind, path)
      return
    }
    root.pendingGammaKind = kind
    root.pendingGammaPath = path
    root.applyingGamma = true
    gammaProc.command = cmd
    gammaProc.running = true
  }

  function ensureDirs() {
    Quickshell.execDetached(["mkdir", "-p", Paths.picturesDir(root.env)])
    Quickshell.execDetached(["mkdir", "-p", Paths.videosDir(root.env)])
  }

  function startSession() {
    root.pendingVideoPath = ""
    root.pendingPhotoPath = ""
    root.ensureDirs()
    if (mediaDevices.defaultVideoInput && mediaDevices.defaultVideoInput.id)
      camera.cameraDevice = mediaDevices.defaultVideoInput
    else if (mediaDevices.videoInputs.length > 0)
      camera.cameraDevice = mediaDevices.videoInputs[0]
    if (mediaDevices.defaultAudioInput)
      audioInput.device = mediaDevices.defaultAudioInput
    camera.active = root.hasCamera
  }

  function stopSession() {
    if (root.recording)
      recorder.stop()
    camera.active = false
  }

  function takePhoto() {
    if (!Paths.canTakePhoto(root.cameraActive, root.recording, root.readyForCapture)) {
      if (!root.hasCamera)
        root.failed("No camera found")
      else if (root.recording)
        root.failed("Stop recording to take a photo")
      else
        root.failed("Camera is not ready")
      return false
    }
    root.pendingPhotoPath = Paths.photoPath(root.env, new Date())
    imageCapture.captureToFile(root.pendingPhotoPath)
    return true
  }

  function toggleRecord() {
    if (root.recording) {
      recorder.stop()
      return true
    }
    if (!Paths.canToggleRecord(root.cameraActive, root.recording)) {
      root.failed(root.hasCamera ? "Camera is not ready" : "No camera found")
      return false
    }
    if (!root.hasMic) {
      root.failed("No microphone found")
      return false
    }
    root.pendingVideoPath = Paths.videoPath(root.env, new Date())
    recorder.outputLocation = Paths.fileUrl(root.pendingVideoPath)
    recorder.record()
    return true
  }

  MediaDevices {
    id: mediaDevices
  }

  CaptureSession {
    id: session
    camera: camera
    audioInput: audioInput
    imageCapture: imageCapture
    recorder: recorder
    videoOutput: root.videoOutput
  }

  Camera {
    id: camera
    active: false
    onErrorOccurred: function(error, errorString) {
      if (root.sessionActive && errorString)
        root.failed(errorString)
    }
  }

  AudioInput {
    id: audioInput
    muted: false
  }

  ImageCapture {
    id: imageCapture
    fileFormat: ImageCapture.JPEG
    quality: ImageCapture.HighQuality
    onImageSaved: function(id, fileName) {
      root.finishSave("photo", fileName || root.pendingPhotoPath)
    }
    onErrorOccurred: function(id, error, errorString) {
      if (errorString)
        root.failed(errorString)
    }
  }

  MediaRecorder {
    id: recorder
    quality: MediaRecorder.HighQuality
    onRecorderStateChanged: function(state) {
      if (root.lastRecorderState === MediaRecorder.RecordingState && state === MediaRecorder.StoppedState) {
        var path = Paths.localPath(recorder.actualLocation ? recorder.actualLocation.toString() : root.pendingVideoPath)
        if (path)
          root.finishSave("video", path)
      }
      root.lastRecorderState = state
    }
    onErrorOccurred: function(error, errorString) {
      if (errorString)
        root.failed(errorString)
    }
  }

  Process {
    id: gammaProc
    onExited: function(exitCode) {
      var kind = root.pendingGammaKind
      var path = root.pendingGammaPath
      root.applyingGamma = false
      root.pendingGammaKind = ""
      root.pendingGammaPath = ""
      if (path)
        root.saved(kind, path)
      if (exitCode !== 0)
        root.failed("Could not apply gamma")
    }
  }

  onSessionActiveChanged: {
    if (root.sessionActive)
      root.startSession()
    else
      root.stopSession()
  }
}
