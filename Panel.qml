import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "QRCode.js" as QRCodeLib

// Panel.qml - Native Omarchy Control Center for TeleStream
Panel {
  id: root
  moduleName: "dorneles.telestream"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var streamState: ({ "status": "idle" })

  // Ensure cliScriptPath is never empty by computing default absolute path
  readonly property string defaultCliPath: {
    var p = Qt.resolvedUrl("scripts/streamer_cli.py").toString()
    return p.replace(/^file:\/\//, "")
  }
  property string cliScriptPath: defaultCliPath

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: Color.popups.text
  readonly property color activeColor: Color.accent
  readonly property string fontFamily: Style.font.family

  // Theme luminance detection & adaptive contrast (inspired by jankeesvw)
  readonly property bool lightTheme: {
    var bg = Color.background
    return (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) > 0.5
  }

  function fade(c, amount) {
    var bg = Color.background
    return Qt.rgba(c.r + (bg.r - c.r) * amount, c.g + (bg.g - c.g) * amount, c.b + (bg.b - c.b) * amount, 1.0)
  }

  readonly property color muted: fade(foreground, 0.45)
  readonly property color surfaceMuted: fade(Color.background, 0.08)

  // 3D perspective card flip when switching between views (inspired by jankeesvw)
  property string pendingView: "main"
  property real flipAngle: 0
  readonly property real flipScale: 1 - 0.14 * Math.abs(Math.sin(flipAngle * Math.PI / 180))

  function switchViewWithFlip(targetView) {
    if (root.currentView === targetView) return
    if (flipAnim.running) {
      root.currentView = targetView
      return
    }
    root.pendingView = targetView
    flipAnim.start()
  }

  SequentialAnimation {
    id: flipAnim
    NumberAnimation {
      target: root; property: "flipAngle"
      to: 90; duration: 150; easing.type: Easing.InCubic
    }
    ScriptAction {
      script: {
        root.flipAngle = -90
        root.currentView = root.pendingView
        if (root.currentView === "about") root.generateQr()
        if (root.currentView === "logs") root.logFileView.reload()
      }
    }
    NumberAnimation {
      target: root; property: "flipAngle"
      to: 0; duration: 200; easing.type: Easing.OutCubic
    }
  }

  // Iconography: Unicode code points for encoding immunity
  readonly property string iconTerminal:  String.fromCodePoint(0xf018d)
  readonly property string iconAbout:     String.fromCodePoint(0xf02fc)
  readonly property string iconClose:     String.fromCodePoint(0xf0156)
  readonly property string iconFile:      String.fromCodePoint(0xf0214)
  readonly property string iconYouTube:   String.fromCodePoint(0xf05c3)
  readonly property string iconBrowse:    String.fromCodePoint(0xf0969)
  readonly property string iconPaste:     String.fromCodePoint(0xf018f)
  readonly property string iconSave:      String.fromCodePoint(0xf04d2)
  readonly property string iconManage:    String.fromCodePoint(0xf0493)
  readonly property string iconEye:       String.fromCodePoint(0xf0208)
  readonly property string iconEyeOff:    String.fromCodePoint(0xf0209)
  readonly property string iconStop:      String.fromCodePoint(0xf04db)
  readonly property string iconLoading:   String.fromCodePoint(0xf144a)
  readonly property string iconPlay:      String.fromCodePoint(0xf040c)
  readonly property string iconBack:      String.fromCodePoint(0xf004d)
  readonly property string iconClear:     String.fromCodePoint(0xf00e2)
  readonly property string iconSaveDisk:  String.fromCodePoint(0xf0193)
  readonly property string iconBottom:    String.fromCodePoint(0xf0045)
  readonly property string iconPlus:      String.fromCodePoint(0xf0415)
  readonly property string iconEdit:      String.fromCodePoint(0xf03eb)
  readonly property string iconCheck:     String.fromCodePoint(0xf012c)
  readonly property string iconTrash:     String.fromCodePoint(0xf01b4)
  readonly property string iconCopy:      String.fromCodePoint(0xf014d)
  readonly property string iconTelegram:  String.fromCodePoint(0xf0b7b)
  readonly property string iconBroadcast: String.fromCodePoint(0xf0567)
  readonly property string iconHistory:   String.fromCodePoint(0xf02da)

  // Sub-views: "main", "logs", "favorites", "about"
  property string currentView: "main"

  // Streaming fields
  property string sourceMode: "local" // "local" or "youtube"
  property string videoPath: ""
  property string youtubeUrl: ""
  property string serverUrl: "rtmps://dc1-1.rtmp.t.me/s/"
  property string streamKey: ""
  property bool showStreamKey: false

  // History of recent media sources (max 5 each)
  property var recentLocalSources: []
  property var recentUrlSources: []
  property bool showRecentSources: false
  readonly property var currentRecentSources: (root.sourceMode === "local") ? (root.recentLocalSources || []) : (root.recentUrlSources || [])

  // Streaming options
  property bool liveStory: false
  property string loopMode: "Loop Infinitely"
  property string qualityPreset: "Source Quality"

  // Configuration and favorites
  property var favoritesList: []
  property string selectedFavoriteName: ""

  // Reactive options for the favorites dropdown
  readonly property var favoriteOptions: {
    var list = root.favoritesList || []
    var opts = [{ value: "", label: "Custom Server (Manual URL & Key)" }]
    for (var i = 0; i < list.length; i++) {
      var it = list[i]
      if (it && it.name) {
        opts.push({ value: it.name, label: it.name })
      }
    }
    return opts
  }

  // Favorite Editor form state
  property string editingOriginalName: ""
  property string editingFavName: ""
  property string editingFavUrl: "rtmps://dc1-1.rtmp.t.me/s/"
  property string editingFavKey: ""
  property bool showFavKey: false
  property string favNotification: ""

  // State flags
  readonly property string currentStatus: streamState ? (streamState.status || "idle") : "idle"
  readonly property bool isStreaming: currentStatus === "streaming"
  readonly property bool isStarting: currentStatus === "starting" || currentStatus === "fetching"
  readonly property bool isError: currentStatus === "error"

  // Live telemetry parsed from ffmpeg daemon
  readonly property var telemetry: streamState && streamState.telemetry ? streamState.telemetry : ({})

  // Elapsed duration string (HH:MM:SS)
  readonly property double startTime: streamState && streamState.start_time ? Number(streamState.start_time) : 0
  property string durationStr: "00:00:00"

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.isStreaming
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
      root.durationStr = (h < 10 ? "0" + h : h) + ":" + (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
    }
  }

  // Hero status phrases rotation with cross-fade (inspired by Omarchy core panels)
  property int phraseIndex: 0
  property real heroMetaOpacity: 1.0
  readonly property var streamingPhrases: [
    "Broadcasting live",
    "Encoding frames",
    "Streaming pixels",
    "Beaming content",
    "Pushing packets"
  ]
  readonly property var idlePhrases: [
    "Ready to stream",
    "Standing by",
    "Awaiting signal"
  ]
  readonly property var activePhrases: root.isStreaming
    ? streamingPhrases
    : (root.isStarting ? ["Connecting...", "Negotiating codecs"] : (root.isError ? ["Stream error"] : idlePhrases))

  readonly property string heroStatusText: activePhrases.length > 0 ? activePhrases[phraseIndex % activePhrases.length] : "Ready"

  Timer {
    id: phraseTimer
    interval: 2800
    repeat: true
    running: root.opened
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: root
      property: "heroMetaOpacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: root
      property: "heroMetaOpacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  // Logs state
  property string logContent: ""
  property string logNotification: ""

  // QR Code for PIX Donation
  readonly property string pixPayload: "00020126580014br.gov.bcb.pix0136aa97cd56-b793-4c39-94be-c190a29f40865204000053039865802BR5925JULIANO_DORNELES_DOS_SANT6012Santo_Angelo610998803-41762290525C7X00138965117602953262656304D7E8"
  property var qrMatrix: []
  readonly property int qrSize: (qrMatrix && qrMatrix.length) ? qrMatrix.length : 0
  property bool pixCopied: false

  Timer {
    id: pixResetTimer
    interval: 2500
    repeat: false
    onTriggered: root.pixCopied = false
  }

  // FileView to read the log file on-demand (no constant inotify churn)
  property FileView logFileView: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/telestream/telestream.log"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var t = text()
      if (t.length > 65536) {
        t = t.substring(t.length - 65536)
        var nl = t.indexOf("\n")
        if (nl !== -1) t = t.substring(nl + 1)
      }
      root.logContent = t
    }
  }

  // Gentle 1s poll timer only active when logs view is currently open
  Timer {
    id: logPollTimer
    interval: 1000
    repeat: true
    running: root.opened && root.currentView === "logs"
    onTriggered: logFileView.reload()
  }

  // FileViews to directly watch config.json for instant reactive updates
  property FileView userConfigFileView: FileView {
    path: Quickshell.env("HOME") + "/.config/telestream/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseConfigFile(text())
  }

  property FileView localConfigFileView: FileView {
    path: Qt.resolvedUrl("config.json").toString().replace(/^file:\/\//, "")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseConfigFile(text())
  }

  // Process to reliably load configuration via CLI
  Process {
    id: configLoaderProc
    command: ["python3", root.cliScriptPath, "get-config"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.parseConfigFile(text)
      }
    }
  }

  function parseConfigFile(raw) {
    if (!raw || raw.trim() === "") return
    try {
      var parsed = JSON.parse(raw)
      if (parsed.favorites && Array.isArray(parsed.favorites) && parsed.favorites.length > 0) {
        root.favoritesList = parsed.favorites
      }
      if (parsed.live_story !== undefined) {
        root.liveStory = parsed.live_story
      }
      if (parsed.recent_local_sources && Array.isArray(parsed.recent_local_sources)) {
        root.recentLocalSources = parsed.recent_local_sources
      }
      if (parsed.recent_url_sources && Array.isArray(parsed.recent_url_sources)) {
        root.recentUrlSources = parsed.recent_url_sources
      }
      if (parsed.last_favorite_name && root.selectedFavoriteName === "") {
        root.selectedFavoriteName = parsed.last_favorite_name
        root.applyFavorite(parsed.last_favorite_name)
      } else if (root.favoritesList.length > 0 && root.selectedFavoriteName === "") {
        root.selectedFavoriteName = root.favoritesList[0].name
        root.applyFavorite(root.selectedFavoriteName)
      }
    } catch (e) {}
  }

  Component.onCompleted: {
    userConfigFileView.reload()
    localConfigFileView.reload()
    loadConfigData()
  }

  function open() {
    currentView = "main"
    loadConfigData()
    if (hostWidget && typeof hostWidget.refreshStatus === "function") {
      hostWidget.refreshStatus()
    }
    controller.show()
  }

  function close() {
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function loadConfigData() {
    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    configLoaderProc.command = ["python3", script, "get-config"]
    configLoaderProc.running = true
  }

  function applyFavorite(name) {
    for (var i = 0; i < favoritesList.length; i++) {
      if (favoritesList[i].name === name) {
        serverUrl = favoritesList[i].url || ""
        streamKey = favoritesList[i].key || ""
        selectedFavoriteName = name
        break
      }
    }
  }

  function saveCurrentAsFavorite() {
    if (serverUrl.trim() === "" || streamKey.trim() === "") {
      root.logNotification = "Please enter Server URL and Stream Key first."
      return
    }
    editingOriginalName = ""
    editingFavName = (selectedFavoriteName !== "" && selectedFavoriteName !== "Custom Server") ? selectedFavoriteName : "My Stream Server"
    editingFavUrl = serverUrl.trim()
    editingFavKey = streamKey.trim()
    favNotification = "Review server details and click '+ Add Favorite'."
    currentView = "favorites"
  }

  function saveFavorite(isNew) {
    var n = editingFavName.trim()
    var u = editingFavUrl.trim()
    var k = editingFavKey.trim()

    if (n === "" || u === "" || k === "") {
      favNotification = "⚠️ Please fill in Name, URL, and Stream Key."
      return
    }

    // 1. Optimistically update local list so UI responds with 0ms latency
    var list = (root.favoritesList ? root.favoritesList.slice() : [])
    var oldN = editingOriginalName
    var found = false

    if (!isNew && oldN !== "") {
      for (var i = 0; i < list.length; i++) {
        if (list[i].name === oldN) {
          list[i] = { name: n, url: u, key: k }
          found = true
          break
        }
      }
    }
    if (!found) {
      for (var j = 0; j < list.length; j++) {
        if (list[j].name === n) {
          list[j] = { name: n, url: u, key: k }
          found = true
          break
        }
      }
    }
    if (!found) {
      list.push({ name: n, url: u, key: k })
    }

    root.favoritesList = list
    root.selectedFavoriteName = n
    root.applyFavorite(n)

    favNotification = isNew ? ("✓ Favorite '" + n + "' added!") : ("✓ Favorite '" + n + "' updated!")
    clearFavoriteForm()

    // 2. Persist to disk via CLI in background
    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    var cmd = ["python3", script, "save-favorite", n, u, k]
    if (!isNew && oldN !== "" && oldN !== n) {
      cmd.push("--old-name")
      cmd.push(oldN)
    }
    Quickshell.execDetached(cmd)
  }

  function removeFavorite(favName) {
    var list = (root.favoritesList ? root.favoritesList.slice() : [])
    var newList = []
    for (var i = 0; i < list.length; i++) {
      if (list[i].name !== favName) {
        newList.push(list[i])
      }
    }
    root.favoritesList = newList
    if (root.selectedFavoriteName === favName) {
      root.selectedFavoriteName = newList.length > 0 ? newList[0].name : ""
      if (root.selectedFavoriteName !== "") root.applyFavorite(root.selectedFavoriteName)
    }
    favNotification = "Removed favorite '" + favName + "'"
    if (editingOriginalName === favName) {
      clearFavoriteForm()
    }
    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    Quickshell.execDetached(["python3", script, "remove-favorite", favName])
  }

  function startEditFavorite(fav) {
    editingOriginalName = fav.name || ""
    editingFavName = fav.name || ""
    editingFavUrl = fav.url || ""
    editingFavKey = fav.key || ""
    favNotification = "Editing: " + fav.name
  }

  function clearFavoriteForm() {
    editingOriginalName = ""
    editingFavName = ""
    editingFavUrl = "rtmps://dc1-1.rtmp.t.me/s/"
    editingFavKey = ""
  }

  function addRecentSource(src, mode) {
    if (!src || src.trim() === "") return
    var s = src.trim()
    var isUrl = (mode === "youtube" || s.startsWith("http://") || s.startsWith("https://"))
    var list = (isUrl ? root.recentUrlSources : root.recentLocalSources).slice()
    var idx = list.indexOf(s)
    if (idx !== -1) list.splice(idx, 1)
    list.unshift(s)
    if (list.length > 5) list = list.slice(0, 5)
    if (isUrl) root.recentUrlSources = list
    else root.recentLocalSources = list

    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    var flag = isUrl ? "--url" : "--local"
    Quickshell.execDetached(["python3", script, "add-recent", s, flag])
  }

  function removeRecentSource(src, mode) {
    if (!src) return
    var isUrl = (mode === "youtube")
    var list = (isUrl ? root.recentUrlSources : root.recentLocalSources).slice()
    var idx = list.indexOf(src)
    if (idx !== -1) list.splice(idx, 1)
    if (isUrl) root.recentUrlSources = list
    else root.recentLocalSources = list

    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    Quickshell.execDetached(["python3", script, "remove-recent", src, "--type", mode])
  }

  function clearRecentSources(mode) {
    if (mode === "youtube") {
      root.recentUrlSources = []
    } else if (mode === "local") {
      root.recentLocalSources = []
    } else {
      root.recentLocalSources = []
      root.recentUrlSources = []
    }
    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    Quickshell.execDetached(["python3", script, "clear-recent", "--type", mode])
  }

  function startStream() {
    var src = (sourceMode === "local") ? videoPath.trim() : youtubeUrl.trim()
    var sUrl = serverUrl.trim()
    var sKey = streamKey.trim()

    if (src === "" || sUrl === "" || sKey === "") {
      root.logNotification = "Error: Please provide video source, server URL, and stream key."
      return
    }

    var lowerUrl = sUrl.toLowerCase()
    if (!lowerUrl.startsWith("rtmp://") && !lowerUrl.startsWith("rtmps://") && !lowerUrl.startsWith("srt://")) {
      root.logNotification = "Error: Server URL must start with rtmp://, rtmps://, or srt://"
      return
    }

    addRecentSource(src, root.sourceMode)

    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    var cmd = ["python3", script, "start",
      "--source", src,
      "--loop", root.loopMode,
      "--preset", root.qualityPreset
    ]

    var isSavedFav = (root.selectedFavoriteName !== "" && root.selectedFavoriteName !== "Custom Server")
    if (isSavedFav) {
      cmd.push("--favorite", root.selectedFavoriteName)
    } else {
      cmd.push("--server", sUrl, "--key", sKey)
    }

    if (root.liveStory) cmd.push("--story")

    Quickshell.execDetached(cmd)
  }

  function stopStream() {
    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    Quickshell.execDetached(["python3", script, "stop"])
  }

  readonly property string pickerScriptPath: {
    var p = Qt.resolvedUrl("scripts/file_picker.py").toString()
    return p.replace(/^file:\/\//, "")
  }

  Process {
    id: filePickerProc
    command: ["python3", root.pickerScriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var selected = text ? text.trim() : ""
        if (selected !== "") {
          root.videoPath = selected
          root.sourceMode = "local"
        }
        root.open()
      }
    }
  }

  function browseFile() {
    root.close()
    filePickerProc.running = true
  }

  Process {
    id: clipboardProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var clip = text ? text.trim() : ""
        if (clip !== "") {
          if (root.sourceMode === "youtube") root.youtubeUrl = clip
          else root.videoPath = clip
        }
      }
    }
  }

  function pasteClipboard() {
    clipboardProc.running = true
  }

  function clearLogs() {
    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    Quickshell.execDetached(["python3", script, "clear-logs"])
  }

  function saveLogFile() {
    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
    Quickshell.execDetached(["python3", script, "save-log-file"])
    root.logNotification = "Log saved to your home directory."
  }

  function generateQr() {
    try {
      root.qrMatrix = QRCodeLib.generateMatrix(pixPayload, "M")
    } catch (e) {
      try {
        root.qrMatrix = QRCodeLib.generateMatrix(pixPayload, "L")
      } catch (err) {
        root.qrMatrix = []
      }
    }
  }

  readonly property real desiredWidth: {
    if (root.currentView === "logs") return Style.space(520)
    if (root.currentView === "favorites") return Style.space(480)
    if (root.currentView === "about") return Style.space(440)
    return Style.space(460)
  }

  readonly property real activeViewHeight: {
    var h = 0
    if (root.currentView === "logs") h = logsCol.implicitHeight
    else if (root.currentView === "favorites") h = favsCol.implicitHeight
    else if (root.currentView === "about") h = aboutCol.implicitHeight
    else h = mainCol.implicitHeight
    return Math.max(Style.space(340), h)
  }

  readonly property bool isAnyEditorFocused: {
    if (typeof sourceField !== "undefined" && sourceField && sourceField.activeFocus) return true
    if (typeof serverUrlField !== "undefined" && serverUrlField && serverUrlField.activeFocus) return true
    if (typeof streamKeyField !== "undefined" && streamKeyField && streamKeyField.activeFocus) return true
    if (typeof favNameInput !== "undefined" && favNameInput && favNameInput.activeFocus) return true
    if (typeof favUrlInput !== "undefined" && favUrlInput && favUrlInput.activeFocus) return true
    if (typeof favKeyInput !== "undefined" && favKeyInput && favKeyInput.activeFocus) return true
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.desiredWidth)
    contentHeight: panel.fittedContentHeight(root.activeViewHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.isAnyEditorFocused

      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.switchPanel) root.switchPanel(direction)
      }

      onTextKey: function(t) {
        if (t === "s" || t === "S") {
          if (root.isStreaming) root.stopStream()
          else root.startStream()
          return
        }
        if (t === "l" || t === "L") {
          root.switchViewWithFlip(root.currentView === "logs" ? "main" : "logs")
          return
        }
        if (t === "f" || t === "F" || t === "m" || t === "M") {
          if (root.currentView === "favorites") root.switchViewWithFlip("main")
          else {
            root.clearFavoriteForm()
            root.switchViewWithFlip("favorites")
          }
          return
        }
        if (t === "a" || t === "A") {
          root.switchViewWithFlip(root.currentView === "about" ? "main" : "about")
          return
        }
        if (t === "h" || t === "H") {
          root.switchViewWithFlip("main")
          return
        }
        if (t === "q" || t === "Q") {
          if (root.isStreaming) root.stopStream()
          return
        }
      }

      onActivateRequested: {
        if (root.currentView === "main") {
          if (root.isStreaming) root.stopStream()
          else root.startStream()
        }
      }

      Item {
        id: contentStack
        anchors.fill: parent

        // 3D perspective card flip (inspired by jankeesvw)
        transform: [
          Translate { x: -contentStack.width / 2; y: -contentStack.height / 2 },
          Scale { xScale: root.flipScale; yScale: root.flipScale },
          Rotation {
            axis.x: 0; axis.y: 1; axis.z: 0
            angle: root.flipAngle
          },
          Matrix4x4 {
            matrix: Qt.matrix4x4(1, 0, 0,       0,
                                 0, 1, 0,       0,
                                 0, 0, 1,       0,
                                 0, 0, -0.0009, 1)
          },
          Translate { x: contentStack.width / 2; y: contentStack.height / 2 }
        ]

        // =========================================================
        // VIEW 1: MAIN CONTROL CENTER
        // =========================================================
        Column {
          id: mainCol
          visible: root.currentView === "main"
          width: parent.width
          spacing: Style.space(8)

          // Hero Section (inspired by Omarchy core panels)
          PanelHero {
            id: hero
            title: "TeleStream"
            meta: root.heroStatusText
            metaOpacity: root.heroMetaOpacity
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Item {
              width: Style.font.display
              height: Style.font.display

              Text {
                anchors.centerIn: parent
                text: root.iconBroadcast
                textFormat: Text.PlainText
                color: root.isStreaming ? Color.urgent : (root.isError ? Color.warning : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: RowLayout {
              spacing: Style.space(6)

              // Master stream toggle switch
              ToggleSwitch {
                checked: root.isStreaming || root.isStarting
                busy: root.isStarting
                onToggled: {
                  if (root.isStreaming) root.stopStream()
                  else root.startStream()
                }

                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.isStreaming ? "Stop stream (S)" : "Start stream (S)"
                }
              }

              // Logs button
              Button {
                implicitWidth: Style.space(26)
                implicitHeight: Style.space(26)
                iconText: root.iconTerminal
                tooltipText: "Streaming logs (L)"
                onClicked: root.switchViewWithFlip("logs")
              }

              // About / Donate button
              Button {
                implicitWidth: Style.space(26)
                implicitHeight: Style.space(26)
                iconText: root.iconAbout
                tooltipText: "About / PIX (A)"
                onClicked: root.switchViewWithFlip("about")
              }

              // Close button
              Button {
                implicitWidth: Style.space(26)
                implicitHeight: Style.space(26)
                iconText: root.iconClose
                tooltipText: "Close (Esc)"
                onClicked: root.close()
              }
            }
          }

          // Stream Activity Pulse Bar (visible during streaming)
          Rectangle {
            visible: root.isStreaming
            width: parent.width
            height: Style.space(3)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            clip: true

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width
              radius: parent.radius
              color: Color.urgent

              SequentialAnimation on opacity {
                running: root.isStreaming && root.opened
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
              }
            }
          }

          // Live Telemetry Grid (visible when streaming)
          Column {
            visible: root.isStreaming
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator {}

            PanelSectionHeader {
              text: "LIVE METRICS"
            }

            GridLayout {
              width: parent.width
              columns: 4
              columnSpacing: Style.space(12)
              rowSpacing: Style.space(3)

              // Col 1 & 2: Duration & Bitrate
              Text {
                text: "Duration"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: root.durationStr
                textFormat: Text.PlainText
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                text: "Bitrate"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: String(root.telemetry && root.telemetry.bitrate ? root.telemetry.bitrate : "--")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              // Col 3 & 4: Frames & FPS
              Text {
                text: "Frames"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: String(root.telemetry && root.telemetry.frame !== undefined ? root.telemetry.frame : "--")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                text: "FPS"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: String(root.telemetry && root.telemetry.fps ? root.telemetry.fps : "--")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              // Col 5 & 6: Speed & Preset
              Text {
                text: "Speed"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: String(root.telemetry && root.telemetry.speed ? root.telemetry.speed : "--")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                text: "Preset"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: root.qualityPreset
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
                Layout.maximumWidth: Style.space(100)
              }
            }
          }

          PanelSeparator {}

          // Source Type Header
          RowLayout {
            width: parent.width
            PanelSectionHeader {
              text: "MEDIA SOURCE"
            }
            Item { Layout.fillWidth: true }
            Text {
              text: "Toggle: S"
              textFormat: Text.PlainText
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption * 0.8
            }
          }

          // Source Type Selector Tabs
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(26)
              text: "Local Video"
              iconText: root.iconFile
              selected: root.sourceMode === "local"
              tooltipText: "Stream a local video file from disk"
              onClicked: root.sourceMode = "local"
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(26)
              text: "YouTube URL"
              iconText: root.iconYouTube
              selected: root.sourceMode === "youtube"
              tooltipText: "Stream from YouTube via yt-dlp"
              onClicked: root.sourceMode = "youtube"
            }
          }

          // Source Input Row
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: sourceField
              Layout.fillWidth: true
              placeholderText: root.sourceMode === "local" ? "Path to local video file..." : "https://www.youtube.com/watch?v=..."
              text: root.sourceMode === "local" ? root.videoPath : root.youtubeUrl
              onTextEdited: {
                if (root.sourceMode === "local") root.videoPath = text
                else root.youtubeUrl = text
              }
            }

            Button {
              implicitWidth: Style.space(32)
              implicitHeight: Style.space(28)
              iconText: root.sourceMode === "local" ? root.iconBrowse : root.iconPaste
              tooltipText: root.sourceMode === "local" ? "Browse video file with Flea" : "Paste link from clipboard"
              onClicked: {
                if (root.sourceMode === "local") root.browseFile()
                else root.pasteClipboard()
              }
            }

            Button {
              implicitWidth: Style.space(32)
              implicitHeight: Style.space(28)
              iconText: root.iconHistory
              tooltipText: "Recent sources history (" + root.currentRecentSources.length + ")"
              selected: root.showRecentSources
              onClicked: root.showRecentSources = !root.showRecentSources
            }
          }

          // Recent Sources Dropdown Card
          Rectangle {
            id: recentSourcesCard
            visible: root.showRecentSources
            width: parent.width
            implicitHeight: visible ? (recentCol.implicitHeight + Style.space(16)) : 0
            radius: Style.cornerRadius
            color: root.surfaceMuted
            border.width: 1
            border.color: Color.popups.border
            clip: true

            Column {
              id: recentCol
              width: parent.width - Style.space(16)
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(8)
              spacing: Style.space(4)

              // Header row
              RowLayout {
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: (root.sourceMode === "local" ? "RECENT LOCAL FILES" : "RECENT URLS") + " (" + root.currentRecentSources.length + "/5)"
                  textFormat: Text.PlainText
                  color: Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption * 0.85
                  font.bold: true
                }

                Item { Layout.fillWidth: true }

                Button {
                  visible: root.currentRecentSources.length > 0
                  implicitHeight: Style.space(20)
                  text: "Clear"
                  iconText: root.iconClear
                  tooltipText: "Clear recent " + (root.sourceMode === "local" ? "files" : "URLs") + " history"
                  onClicked: root.clearRecentSources(root.sourceMode)
                }
              }

              // Empty state
              Text {
                visible: root.currentRecentSources.length === 0
                width: parent.width
                text: "No recent " + (root.sourceMode === "local" ? "local files" : "URLs") + " recorded yet."
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                topPadding: Style.space(6)
                bottomPadding: Style.space(6)
              }

              // Items repeater
              Repeater {
                model: root.currentRecentSources

                delegate: Rectangle {
                  id: itemDelegate
                  width: recentCol.width
                  height: Style.space(30)
                  radius: Style.cornerRadius * 0.75
                  color: itemMouse.containsMouse ? root.fade(Color.accent, 0.15) : "transparent"

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(4)
                    spacing: Style.space(6)

                    Item {
                      Layout.fillWidth: true
                      Layout.fillHeight: true

                      MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.sourceMode === "local") {
                            root.videoPath = modelData
                          } else {
                            root.youtubeUrl = modelData
                          }
                          root.showRecentSources = false
                        }
                      }

                      RowLayout {
                        anchors.fill: parent
                        spacing: Style.space(6)

                        Text {
                          text: (root.sourceMode === "local") ? root.iconFile : root.iconYouTube
                          textFormat: Text.PlainText
                          color: itemMouse.containsMouse ? Color.accent : Color.muted
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          Layout.fillWidth: true
                          text: {
                            var val = String(modelData)
                            if (root.sourceMode === "local") {
                              var slash = val.lastIndexOf("/")
                              var name = slash >= 0 ? val.substring(slash + 1) : val
                              return name + " (" + val + ")"
                            }
                            return val
                          }
                          textFormat: Text.PlainText
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.95
                          elide: Text.ElideMiddle
                        }
                      }
                    }

                    Button {
                      id: deleteBtn
                      implicitWidth: Style.space(22)
                      implicitHeight: Style.space(22)
                      iconText: root.iconTrash
                      tooltipText: "Remove from history"
                      onClicked: root.removeRecentSource(modelData, root.sourceMode)
                    }
                  }
                }
              }
            }
          }

          PanelSeparator {}

          // Favorites Selection Header Row
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "TARGET SERVER"
            }

            Item { Layout.fillWidth: true }

            Button {
              implicitHeight: Style.space(22)
              text: "Save"
              iconText: root.iconSave
              tooltipText: "Save current server as favorite (F)"
              onClicked: root.saveCurrentAsFavorite()
            }

            Button {
              implicitHeight: Style.space(22)
              text: "Manage"
              iconText: root.iconManage
              tooltipText: "Manage saved servers"
              onClicked: {
                root.clearFavoriteForm()
                root.switchViewWithFlip("favorites")
              }
            }
          }

          // Server Favorites Dropdown
          Dropdown {
            id: favDropdown
            width: parent.width
            value: root.selectedFavoriteName
            options: root.favoriteOptions
            onChanged: function(val) {
              root.selectedFavoriteName = val
              if (val !== "") {
                root.applyFavorite(val)
                var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
                Quickshell.execDetached(["python3", script, "set-last-favorite", val])
              }
            }
          }

          // Server URL & Stream Key Inputs
          Column {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: serverUrlField
              width: parent.width
              placeholderText: "Server URL (e.g. rtmps://dc1-1.rtmp.t.me/s/)..."
              text: root.serverUrl
              onTextEdited: root.serverUrl = text
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: streamKeyField
                Layout.fillWidth: true
                placeholderText: "Stream Key..."
                password: !root.showStreamKey
                text: root.streamKey
                onTextEdited: root.streamKey = text
              }

              Button {
                implicitWidth: Style.space(32)
                implicitHeight: Style.space(28)
                iconText: root.showStreamKey ? root.iconEye : root.iconEyeOff
                tooltipText: root.showStreamKey ? "Hide Stream Key" : "Show Stream Key"
                onClicked: root.showStreamKey = !root.showStreamKey
              }
            }
          }

          PanelSeparator {}

          PanelSectionHeader {
            text: "ENCODING & STORY"
          }

          // Quality Preset
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "Quality Preset"
              textFormat: Text.PlainText
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Dropdown {
              width: parent.width
              value: root.qualityPreset
              options: [
                "Source Quality",
                "1080p (5 Mbps)",
                "720p (3 Mbps)",
                "480p (1.5 Mbps)"
              ]
              onChanged: function(val) { root.qualityPreset = val }
            }
          }

          // Loop Mode
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "Loop Mode"
              textFormat: Text.PlainText
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Dropdown {
              width: parent.width
              value: root.loopMode
              options: [
                "Loop Infinitely",
                "Play Once"
              ]
              onChanged: function(val) { root.loopMode = val }
            }
          }

          // Toggle: Live Story (9:16)
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            ToggleSwitch {
              checked: root.liveStory
              onToggled: root.liveStory = !root.liveStory

              PanelToolTip {
                visible: parent.containsMouse
                text: "Enable 9:16 vertical stream mode"
              }
            }

            Column {
              Layout.fillWidth: true
              spacing: 1
              Text {
                text: "Live Story (9:16 Vertical)"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: "Blurred vertical background for mobile stories"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption * 0.85
              }
            }
          }

          // Start / Stop Stream Action Button
          Button {
            width: parent.width
            implicitHeight: Style.space(36)
            text: root.isStreaming ? "Stop Stream" : (root.isStarting ? "Connecting..." : "Start Stream")
            iconText: root.isStreaming ? root.iconStop : (root.isStarting ? root.iconLoading : root.iconPlay)
            active: root.isStreaming
            accent: root.isStreaming ? Color.urgent : Color.accent
            enabled: !root.isStarting
            tooltipText: root.isStreaming ? "Stop active stream (S)" : "Start streaming (S)"
            onClicked: {
              if (root.isStreaming) root.stopStream()
              else root.startStream()
            }
          }
        }

        // =========================================================
        // VIEW 2: LOGS VIEW
        // =========================================================
        Column {
          id: logsCol
          visible: root.currentView === "logs"
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              implicitWidth: Style.space(26)
              implicitHeight: Style.space(26)
              iconText: root.iconBack
              tooltipText: "Back to Controls (Esc / H)"
              onClicked: root.switchViewWithFlip("main")
            }

            PanelSectionHeader {
              text: "APPLICATION & FFMPEG LOGS"
            }

            Item { Layout.fillWidth: true }

            Button {
              implicitHeight: Style.space(24)
              text: "Clear"
              iconText: root.iconClear
              tooltipText: "Clear active log buffer"
              onClicked: {
                root.clearLogs()
                toast.show("Log buffer cleared")
              }
            }

            Button {
              implicitHeight: Style.space(24)
              text: "Save"
              iconText: root.iconSaveDisk
              tooltipText: "Save logs to ~/telestream_log_....txt"
              onClicked: {
                root.saveLogFile()
                toast.show("Logs saved to home directory")
              }
            }
          }

          PanelSeparator {}

          // Terminal style logs box
          Rectangle {
            width: parent.width
            implicitHeight: Style.space(360)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Color.background
            border.width: 1
            border.color: Color.popups.border
            clip: true

            Flickable {
              id: logFlickable
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentWidth: width
              contentHeight: logText.implicitHeight
              clip: true

              property bool userScrolledUp: false

              onContentYChanged: {
                if (contentHeight > height) {
                  userScrolledUp = (contentY < (contentHeight - height - Style.space(30)))
                }
              }

              TextEdit {
                id: logText
                width: logFlickable.width
                text: root.logContent ? root.logContent : "No logs available. Start a stream to view ffmpeg output."
                textFormat: Text.PlainText
                readOnly: true
                selectByMouse: true
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption * 0.9
                wrapMode: TextEdit.WrapAnywhere
              }

              onContentHeightChanged: {
                if (!userScrolledUp) {
                  logFlickable.contentY = Math.max(0, logFlickable.contentHeight - logFlickable.height)
                }
              }
            }

            // Floating Jump to Bottom Button when scrolled up
            Button {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(10)
              visible: logFlickable.userScrolledUp && (logFlickable.contentHeight > logFlickable.height)
              text: "Bottom"
              iconText: root.iconBottom
              implicitHeight: Style.space(24)
              tooltipText: "Scroll to latest log entries"
              onClicked: {
                logFlickable.userScrolledUp = false
                logFlickable.contentY = Math.max(0, logFlickable.contentHeight - logFlickable.height)
              }
            }
          }
        }

        // =========================================================
        // VIEW 3: FAVORITES MANAGER
        // =========================================================
        Column {
          id: favsCol
          visible: root.currentView === "favorites"
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              implicitWidth: Style.space(26)
              implicitHeight: Style.space(26)
              iconText: root.iconBack
              tooltipText: "Back to Controls (Esc / H)"
              onClicked: root.switchViewWithFlip("main")
            }

            PanelSectionHeader {
              text: "MANAGE FAVORITE SERVERS"
            }

            Item { Layout.fillWidth: true }

            Button {
              implicitHeight: Style.space(24)
              text: "Clear"
              iconText: root.iconClear
              tooltipText: "Clear input fields"
              onClicked: {
                root.clearFavoriteForm()
                toast.show("Form cleared")
              }
            }
          }

          PanelSeparator {}

          // Add / Edit Favorite Form Box
          Rectangle {
            width: parent.width
            implicitHeight: formCol.implicitHeight + Style.space(16)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Color.popups.background
            border.width: 1
            border.color: Color.popups.border

            Column {
              id: formCol
              width: parent.width - Style.space(16)
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: root.editingOriginalName !== "" ? ("Editing: " + root.editingOriginalName) : "Add New Favorite"
                textFormat: Text.PlainText
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: favNameInput
                width: parent.width
                placeholderText: "Server Name (e.g. Telegram Live)"
                text: root.editingFavName
                onTextEdited: root.editingFavName = text
              }

              TextField {
                id: favUrlInput
                width: parent.width
                placeholderText: "Server RTMP URL"
                text: root.editingFavUrl
                onTextEdited: root.editingFavUrl = text
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: favKeyInput
                  Layout.fillWidth: true
                  placeholderText: "Stream Key"
                  password: !root.showFavKey
                  text: root.editingFavKey
                  onTextEdited: root.editingFavKey = text
                }

                Button {
                  implicitWidth: Style.space(32)
                  implicitHeight: Style.space(28)
                  iconText: root.showFavKey ? root.iconEye : root.iconEyeOff
                  tooltipText: root.showFavKey ? "Hide Stream Key" : "Show Stream Key"
                  onClicked: root.showFavKey = !root.showFavKey
                }
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(28)
                  text: "Add New"
                  iconText: root.iconPlus
                  tooltipText: "Add server to favorites"
                  onClicked: {
                    root.saveFavorite(true)
                    toast.show("Favorite saved")
                  }
                }

                Button {
                  visible: root.editingOriginalName !== ""
                  Layout.fillWidth: true
                  implicitHeight: Style.space(28)
                  text: "Save Changes"
                  iconText: root.iconSaveDisk
                  tooltipText: "Save changes to this favorite"
                  onClicked: {
                    root.saveFavorite(false)
                    toast.show("Favorite updated")
                  }
                }
              }
            }
          }

          PanelSeparator {}

          // Favorites List Header
          PanelSectionHeader {
            text: "SAVED SERVERS (" + root.favoritesList.length + ")"
          }

          // List of Favorites with explicit implicitHeight
          ListView {
            width: parent.width
            implicitHeight: Math.min(Style.space(220), Math.max(Style.space(80), root.favoritesList.length * Style.space(46)))
            height: implicitHeight
            spacing: Style.space(4)
            clip: true
            model: root.favoritesList

            delegate: Rectangle {
              width: parent.width
              height: Style.space(42)
              radius: Style.cornerRadius
              color: root.editingOriginalName === modelData.name ? Color.popups.border : Color.background
              border.width: 1
              border.color: root.selectedFavoriteName === modelData.name ? Color.accent : Color.popups.border

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(6)

                Column {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: modelData.name || "Untitled"
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body * 0.95
                    font.bold: root.selectedFavoriteName === modelData.name
                    elide: Text.ElideRight
                  }

                  Text {
                    text: (modelData.url || "") + " (" + (modelData.key ? "key saved" : "no key") + ")"
                    textFormat: Text.PlainText
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 0.85
                    elide: Text.ElideRight
                  }
                }

                // Edit Button
                Button {
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  iconText: root.iconEdit
                  tooltipText: "Edit this favorite"
                  onClicked: root.startEditFavorite(modelData)
                }

                // Use Button
                Button {
                  implicitHeight: Style.space(26)
                  text: "Use"
                  iconText: root.iconCheck
                  tooltipText: "Use this server in main controls"
                  onClicked: {
                    root.applyFavorite(modelData.name)
                    var script = (root.cliScriptPath && root.cliScriptPath !== "") ? root.cliScriptPath : root.defaultCliPath
                    Quickshell.execDetached(["python3", script, "set-last-favorite", modelData.name])
                    root.switchViewWithFlip("main")
                    toast.show("Using server: " + modelData.name)
                  }
                }

                // Delete Button
                Button {
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  iconText: root.iconTrash
                  tooltipText: "Delete this favorite"
                  onClicked: {
                    root.removeFavorite(modelData.name)
                    toast.show("Favorite removed")
                  }
                }
              }
            }
          }
        }

        // =========================================================
        // VIEW 4: ABOUT / DONATE (PIX)
        // =========================================================
        Column {
          id: aboutCol
          visible: root.currentView === "about"
          width: parent.width
          spacing: Style.space(10)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              implicitWidth: Style.space(26)
              implicitHeight: Style.space(26)
              iconText: root.iconBack
              tooltipText: "Back to Controls (Esc / H)"
              onClicked: root.switchViewWithFlip("main")
            }

            PanelSectionHeader {
              text: "ABOUT TELESTREAM"
            }

            Item { Layout.fillWidth: true }
          }

          PanelSeparator {}

          Text {
            width: parent.width
            text: "TeleStream Omarchy — Stream local video files or YouTube videos directly to RTMP servers with 9:16 vertical Live Story mode."
            textFormat: Text.PlainText
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // PIX Donation Card with auto-sized implicitHeight
          Rectangle {
            id: qrBox
            width: parent.width
            implicitHeight: qrCardCol.implicitHeight + Style.space(24)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Color.background
            border.width: 1
            border.color: Color.popups.border

            Column {
              id: qrCardCol
              width: parent.width - Style.space(20)
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(12)
              spacing: Style.space(8)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Donate via PIX"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              // High-performance single-item Canvas for QR Code
              Rectangle {
                width: Style.space(140)
                height: Style.space(140)
                color: "#FFFFFF"
                radius: Style.cornerRadius
                anchors.horizontalCenter: parent.horizontalCenter

                Canvas {
                  id: qrCanvas
                  anchors.centerIn: parent
                  width: Style.space(128)
                  height: Style.space(128)
                  renderTarget: Canvas.FramebufferObject

                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.fillStyle = "#FFFFFF"
                    ctx.fillRect(0, 0, width, height)
                    var m = root.qrMatrix
                    if (!m || m.length === 0) return
                    ctx.fillStyle = "#000000"
                    var n = m.length
                    var cellW = width / n
                    var cellH = height / n
                    for (var r = 0; r < n; r++) {
                      for (var c = 0; c < n; c++) {
                        if (m[r] && m[r][c]) {
                          ctx.fillRect(c * cellW, r * cellH, Math.ceil(cellW), Math.ceil(cellH))
                        }
                      }
                    }
                  }

                  Connections {
                    target: root
                    function onQrMatrixChanged() { qrCanvas.requestPaint() }
                  }
                }
              }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: Style.space(26)
                text: root.pixCopied ? "PIX Code Copied!" : "Copy PIX Code"
                iconText: root.pixCopied ? root.iconCheck : root.iconCopy
                tooltipText: "Copy raw PIX paste-and-pay code to clipboard"
                onClicked: {
                  Quickshell.execDetached(["wl-copy", root.pixPayload])
                  root.pixCopied = true
                  pixResetTimer.restart()
                  toast.show("PIX code copied to clipboard!")
                }
              }

              Text {
                width: parent.width
                text: "Enjoying the app? Consider sending a collectible gift on Telegram: t.me/jvlianodorneles"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption * 0.9
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
              }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: Style.space(24)
                text: "Open Telegram Profile"
                iconText: root.iconTelegram
                tooltipText: "Open Telegram in web browser"
                onClicked: {
                  Quickshell.execDetached(["xdg-open", "https://t.me/jvlianodorneles"])
                }
              }
            }
          }
        }
      }
    }

    // Reusable Toast Notification component (visible across all views)
    Rectangle {
      id: toast
      property string message: ""
      visible: opacity > 0
      opacity: 0
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(10)
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width - Style.space(24), toastLabel.implicitWidth + Style.space(28))
      height: Style.space(26)
      radius: height / 2
      color: Color.popups.background
      border.color: Color.accent
      border.width: 1
      z: 200

      Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }

      Text {
        id: toastLabel
        anchors.centerIn: parent
        text: toast.message
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      Timer {
        id: toastTimer
        interval: 2200
        repeat: false
        onTriggered: toast.opacity = 0
      }

      function show(msg) {
        message = msg
        opacity = 1.0
        toastTimer.restart()
      }
    }
  }
}
