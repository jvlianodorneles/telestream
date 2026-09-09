import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// BarWidget.qml - Status Bar Widget for TeleStream on Omarchy
BarWidget {
  id: root
  moduleName: "dorneles.telestream"

  // Settings from shell.json
  readonly property string displayFormat: (root.settings && root.settings.displayFormat) ? root.settings.displayFormat : "icon_text"
  readonly property bool showDuration: (root.settings && root.settings.showDuration !== undefined) ? root.settings.showDuration : true

  // Theme luminance detection & adaptive contrast (inspired by jankeesvw)
  readonly property bool lightTheme: {
    var bg = Color.background
    return (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) > 0.5
  }

  function fade(c, amount) {
    var bg = Color.background
    return Qt.rgba(c.r + (bg.r - c.r) * amount, c.g + (bg.g - c.g) * amount, c.b + (bg.b - c.b) * amount, 1.0)
  }

  // Iconography: Unicode code points for encoding immunity
  readonly property string iconBroadcast: String.fromCodePoint(0xF0567) // nf-md-video
  readonly property string iconLoading:   String.fromCodePoint(0xF144A) // nf-md-clock_fast
  readonly property string iconAlert:     String.fromCodePoint(0xF0026) // nf-md-alert_circle

  // Live state from state.json
  property var streamState: ({ "status": "idle" })
  readonly property string currentStatus: streamState ? (streamState.status || "idle") : "idle"
  readonly property bool isStreaming: currentStatus === "streaming"
  readonly property bool isStarting: currentStatus === "starting" || currentStatus === "fetching"
  readonly property bool isError: currentStatus === "error"
  readonly property bool isLiveStory: streamState && streamState.is_live_story === true
  readonly property double startTime: streamState && streamState.start_time ? Number(streamState.start_time) : 0

  // Elapsed timer string (HH:MM:SS)
  property string durationStr: "00:00:00"

  readonly property string cliScriptPath: Qt.resolvedUrl("scripts/streamer_cli.py").toString().replace(/^file:\/\//, "")

  // Watch state.json for reactive updates
  property FileView stateFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/telestream/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.streamState = JSON.parse(text())
      } catch (e) {
        // Keep previous state
      }
    }
  }

  // Timer to update elapsed streaming duration
  Timer {
    interval: 1000
    repeat: true
    running: root.isStreaming
    triggeredOnStart: true
    onTriggered: {
      if (!root.isStreaming || root.startTime <= 0) {
        root.durationStr = "00:00:00"
        return
      }
      var now = Date.now() / 1000
      var elapsed = Math.max(0, Math.floor(now - root.startTime))
      var h = Math.floor(elapsed / 3600)
      var m = Math.floor((elapsed % 3600) / 60)
      var s = elapsed % 60
      function pad(n) { return n < 10 ? "0" + n : String(n) }
      root.durationStr = (h > 0 ? (pad(h) + ":") : "") + pad(m) + ":" + pad(s)
    }
  }

  // Pulsing animation for LIVE recording indicator
  property real pulseOpacity: 1.0
  SequentialAnimation on pulseOpacity {
    running: root.isStreaming
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
    NumberAnimation { from: 0.35; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
  }

  // Popup panel loader
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("streamState" in target) target.streamState = root.streamState
    if ("cliScriptPath" in target) target.cliScriptPath = root.cliScriptPath
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onStreamStateChanged: injectPanel()

  Component.onCompleted: {
    stateFile.reload()
    refreshStatus()
  }

  function refreshStatus() {
    stateFile.reload()
    if (cliScriptPath !== "") {
      Quickshell.execDetached(["python3", cliScriptPath, "status"])
    }
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function stopStream() {
    if (cliScriptPath !== "") {
      Quickshell.execDetached(["python3", cliScriptPath, "stop"], function() {
        refreshStatus()
      })
    }
  }

  // IPC Handler for Hyprland shortcuts & command line
  // Flash indicator for headless actions (inspired by Omableep)
  property bool flashing: false
  Timer {
    id: flashTimer
    interval: 160
    repeat: false
    onTriggered: root.flashing = false
  }

  function triggerFlash() {
    root.flashing = true
    flashTimer.restart()
  }

  IpcHandler {
    target: "dorneles.telestream"

    function open(): void { root.triggerFlash(); root.open() }
    function close(): void { root.triggerFlash(); root.close() }
    function toggle(): void { root.triggerFlash(); root.togglePanel() }
    function stop(): void { root.triggerFlash(); root.stopStream() }
    function refresh(): void { root.triggerFlash(); root.refreshStatus() }
    function setVideoPath(path: string): void {
      root.triggerFlash()
      if (panelLoader.item) {
        panelLoader.item.videoPath = path
        panelLoader.item.sourceMode = "local"
      }
      root.open()
    }
  }

  readonly property real slotWidth: {
    if (root.displayFormat === "icon_only") {
      return Style.bar.iconSlot
    }
    return Math.max(12, contentRow.implicitWidth + button.scaledHorizontalMargin * 2)
  }

  implicitWidth: root.vertical ? (root.bar ? root.bar.barSize : Style.bar.sizeHorizontal) : slotWidth
  implicitHeight: button.implicitHeight

  // Smooth expanding transition on the bar slot (inspired by UniFi Protect)
  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.5
    verticalPadding: 6
    tooltipText: {
      if (root.isStreaming) {
        var tel = root.streamState && root.streamState.telemetry ? root.streamState.telemetry : null
        var extra = ""
        if (tel && tel.bitrate && tel.bitrate !== "--") {
          extra = "\nBitrate: " + tel.bitrate + " · FPS: " + (tel.fps || "--")
        }
        return "TeleStream LIVE (" + root.durationStr + ")" + extra + "\nSource: " + (root.streamState.source || "Unknown") + "\nLeft-click: Controls · Right-click: Stop · Middle: Logs"
      }
      if (root.isStarting) return "TeleStream connecting..."
      if (root.isError) return "TeleStream error! Click to inspect logs."
      return "TeleStream — RTMP Video Streamer\nLeft-click: Controls · Middle-click: Logs"
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.isStreaming) {
          root.triggerFlash()
          root.stopStream()
        } else {
          root.togglePanel()
        }
      } else if (b === Qt.MiddleButton) {
        if (panelLoader.item) {
          panelLoader.item.currentView = "logs"
          panelLoader.item.logFileView.reload()
        }
        root.open()
      } else {
        root.togglePanel()
      }
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      // Live Red Dot Indicator
      Rectangle {
        id: liveDot
        visible: root.isStreaming
        width: Style.space(7)
        height: Style.space(7)
        radius: width / 2
        color: Color.urgent
        opacity: root.pulseOpacity
        anchors.verticalCenter: parent.verticalCenter
      }

      // Icon with Contextual Badge Container (inspired by jankeesvw)
      Item {
        id: iconContainer
        visible: root.displayFormat !== "text_only"
        width: iconText.implicitWidth
        height: iconText.implicitHeight
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: iconText
          anchors.centerIn: parent
          text: root.isStreaming ? root.iconBroadcast : (root.isStarting ? root.iconLoading : (root.isError ? root.iconAlert : root.iconBroadcast))
          textFormat: Text.PlainText
          color: root.flashing ? Color.accent : (root.isStreaming ? Color.urgent : (root.isError ? Color.warning : button.foreground))
          font.family: button.fontFamily
          font.pixelSize: button.fontSize * 1.1
          renderType: Text.NativeRendering
        }

        // Story Mode vertical badge / State Badge (hanging off top-right corner)
        Rectangle {
          id: cornerBadge
          visible: root.isLiveStory && (root.isStreaming || root.isStarting)
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(3)
          anchors.topMargin: -Style.space(2)
          width: Style.space(6)
          height: Style.space(6)
          radius: width / 2
          color: Color.accent
          border.width: 1.5
          border.color: Color.bar.background
        }
      }

      // Status label / duration
      Text {
        id: statusLabel
        visible: !root.vertical && root.displayFormat !== "icon_only"
        text: {
          if (root.isStreaming) {
            return root.showDuration ? ("LIVE " + root.durationStr) : "LIVE"
          }
          if (root.isStarting) return "Connecting..."
          if (root.isError) return "Error"
          return "TeleStream"
        }
        textFormat: Text.PlainText
        color: root.flashing ? Color.accent : (root.isStreaming ? Color.urgent : button.foreground)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: root.isStreaming
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
