import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Config.js" as Config

// Tuner + customize overlay for the ASUS Vivobook S14 Copilot+ (S5406SA).
Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string configPath: configHome + "/omarchy/vivobook-s14-copilot.json"

  function fileFromUrl(url) {
    var s = String(url || "")
    if (s.indexOf("file://") === 0) {
      s = s.substring(7)
      try { s = decodeURIComponent(s) } catch (e) {}
    }
    while (s.length > 1 && s.charAt(s.length - 1) === "/")
      s = s.substring(0, s.length - 1)
    return s
  }

  readonly property string pluginDir: {
    if (manifest && manifest.__sourceDir)
      return String(manifest.__sourceDir)
    var resolved = fileFromUrl(Qt.resolvedUrl("."))
    if (resolved.indexOf("/") === 0)
      return resolved
    return configHome + "/omarchy/plugins/vivobook.s14-copilot"
  }
  readonly property string applyBin: pluginDir + "/bin/apply"

  property string pendingMode: ""
  property string pendingProfile: ""
  property string lastTunedKey: ""

  property bool settingsOpen: false
  property var cfg: Config.defaults()
  property string selectedProfile: "balanced"
  property bool hydrating: false
  property bool chargeHelperReady: false
  property bool chargeHelperBusy: false
  readonly property var currentProfile: cfg && cfg.profiles ? cfg.profiles[selectedProfile] : ({})

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.family

  property string pendingKey: ""

  function applyNow(mode, profile) {
    if (pluginDir === "") return
    pendingMode = mode
    pendingProfile = profile || ""
    debounce.interval = (mode === "tune" && pendingProfile === "") ? 900 : 400
    debounce.restart()
  }

  function startPpdQuery() {
    if (ppdQuery.running) {
      ppdQuery.running = false
      Qt.callLater(function() {
        if (root.pendingMode === "tune" && root.pendingProfile === "")
          ppdQuery.running = true
      })
      return
    }
    ppdQuery.running = true
  }

  function runPending() {
    if (pluginDir === "") return
    if (applyProcess.running) return
    var mode = pendingMode
    var profile = pendingProfile
    if (mode === "tune" && !profile) {
      startPpdQuery()
      return
    }
    pendingMode = ""
    pendingProfile = ""
    if (mode === "") return

    var cmd = [applyBin]
    var key = ""
    if (mode === "unplug") {
      cmd.push("unplug")
      key = "unplug"
    } else if (mode === "tune") {
      cmd.push("--tune-only", profile)
      key = "tune:" + profile + ":" + (UPower.onBattery ? "battery" : "ac")
    } else {
      return
    }

    if (key === lastTunedKey) return
    pendingKey = key
    applyProcess.command = cmd
    applyProcess.running = true
  }

  function onPowerSourceChanged() {
    lastTunedKey = ""
    if (UPower.onBattery) {
      applyNow("unplug", "")
      return
    }
    applyNow("tune", "")
  }

  function openSettings(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = ({}) }
    if (payload.profile === "performance" || payload.profile === "balanced" || payload.profile === "power-saver")
      selectedProfile = payload.profile
    hydrating = true
    settingsFile.reload()
    refreshChargeHelper()
    settingsOpen = true
    Qt.callLater(function() {
      if (root.settingsOpen) keyCatcher.forceActiveFocus()
    })
  }

  function closeSettings() {
    settingsOpen = false
  }

  function applyLoaded(raw) {
    cfg = Config.parse(raw)
    hydrating = false
  }

  function patch(mutator) {
    var next = Config.clone(cfg)
    mutator(next)
    cfg = next
    saveSoon.restart()
  }

  function setGlobal(key, value) {
    patch(function(next) { next[key] = value })
  }

  function setProfileKey(key, value) {
    var profile = selectedProfile
    patch(function(next) {
      if (!next.profiles[profile]) next.profiles[profile] = {}
      next.profiles[profile][key] = value
    })
  }

  function resetDefaults() {
    cfg = Config.defaults()
    saveSoon.restart()
  }

  function refreshChargeHelper() {
    if (pluginDir === "" || helperReadyProc.running) return
    helperReadyProc.command = [applyBin, "helper-ready"]
    helperReadyProc.running = true
  }

  function installChargeHelper() {
    if (pluginDir === "" || chargeHelperBusy || setupProc.running) return
    chargeHelperBusy = true
    setupProc.command = [applyBin, "setup"]
    setupProc.running = true
  }

  Timer {
    id: debounce
    interval: 400
    repeat: false
    onTriggered: root.runPending()
  }

  Timer {
    id: saveSoon
    interval: 180
    repeat: false
    onTriggered: {
      if (root.hydrating) return
      settingsFile.setText(Config.stringify(root.cfg))
    }
  }

  Process {
    id: applyProcess
    running: false
    onExited: function(exitCode) {
      if (exitCode === 0 && root.pendingKey !== "")
        root.lastTunedKey = root.pendingKey
      root.refreshChargeHelper()
      if (root.pendingMode !== "") root.runPending()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("vivobook.s14-copilot", text.trim())
    }
  }

  Process {
    id: helperReadyProc
    command: [root.applyBin, "helper-ready"]
    running: false
    onExited: function(exitCode) {
      root.chargeHelperReady = exitCode === 0
    }
  }

  Process {
    id: setupProc
    command: [root.applyBin, "setup"]
    running: false
    onExited: function(exitCode) {
      root.chargeHelperBusy = false
      root.refreshChargeHelper()
      if (exitCode === 0) {
        root.lastTunedKey = ""
        root.applyNow("tune", "")
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("vivobook.s14-copilot", text.trim())
    }
  }

  Process {
    id: ppdQuery
    command: ["busctl", "get-property", "org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        var m = t.match(/"([^"]+)"/)
        var profile = m ? m[1] : t
        if (profile === "performance" || profile === "balanced" || profile === "power-saver") {
          root.pendingMode = "tune"
          root.pendingProfile = profile
          root.runPending()
        }
      }
    }
  }

  Process {
    id: ppdMonitor
    running: true
    command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.UPower.PowerProfiles", "--object-path", "/org/freedesktop/UPower/PowerProfiles"]
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).indexOf("ActiveProfile") >= 0) {
          root.lastTunedKey = ""
          root.applyNow("tune", "")
        }
      }
    }
    onExited: Qt.callLater(function() {
      if (!ppdMonitor.running) ppdMonitor.running = true
    })
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.onPowerSourceChanged()
    }
  }

  FileView {
    id: settingsFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyLoaded(text())
    onLoadFailed: root.applyLoaded("")
    onFileChanged: {
      if (!root.hydrating) settingsFile.reload()
      root.lastTunedKey = ""
      if (UPower.onBattery) root.applyNow("unplug", "")
      else root.applyNow("tune", "")
    }
  }

  IpcHandler {
    target: "vivobook.s14-copilot"
    function open(payload: string): void { root.openSettings(payload) }
    function close(): void { root.closeSettings() }
    function setup(): void { root.installChargeHelper() }
  }

  Component.onCompleted: {
    root.lastTunedKey = ""
    root.refreshChargeHelper()
    if (UPower.onBattery)
      root.applyNow("unplug", "")
    else
      root.applyNow("tune", "")
  }

  PanelWindow {
    visible: root.settingsOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "vivobook-s14-copilot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea { anchors.fill: parent; onClicked: root.closeSettings() }
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(460), parent.width - Style.space(48))
      height: Math.min(body.implicitHeight + Style.spacing.panelPadding * 2, parent.height - Style.space(48))
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.closeSettings()

        Flickable {
          id: flick
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          contentWidth: width
          contentHeight: body.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: body
            width: flick.width
            spacing: Style.space(14)

            Text {
              text: "Vivobook S14 Copilot+"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Pick extras for each Omarchy power profile. Changes save immediately and apply to the active profile."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Toggle {
              width: parent.width
              label: "Force power-saver on unplug"
              description: "When the charger comes out, switch to the power-saver extras."
              checked: root.cfg.autoBattery === true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.setGlobal("autoBattery", !root.cfg.autoBattery)
            }

            Toggle {
              width: parent.width
              label: "Chromium VAAPI"
              description: "Decode video on Intel Arc instead of the CPU."
              checked: root.cfg.vaapi === true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.setGlobal("vaapi", !root.cfg.vaapi)
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "PROFILE EXTRAS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              width: parent.width
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              value: root.selectedProfile
              options: [
                { value: "performance", label: "Performance" },
                { value: "balanced", label: "Balanced" },
                { value: "power-saver", label: "Power-saver" }
              ]
              onChanged: function(v) { root.selectedProfile = v }
            }

            OptionRow {
              label: "Panel refresh"
              value: String(root.currentProfile.refresh || "120")
              options: [
                { value: "60", label: "60 Hz" },
                { value: "120", label: "120 Hz" },
                { value: "skip", label: "Leave" }
              ]
              onPicked: function(v) { root.setProfileKey("refresh", v) }
            }

            OptionRow {
              label: "Animations"
              value: String(root.currentProfile.animations || "on")
              options: [
                { value: "on", label: "On" },
                { value: "off", label: "Off" },
                { value: "skip", label: "Leave" }
              ]
              onPicked: function(v) { root.setProfileKey("animations", v) }
            }

            OptionRow {
              label: "Charge limit"
              value: String(root.currentProfile.charge || "80")
              options: [
                { value: "80", label: "80%" },
                { value: "100", label: "100%" },
                { value: "skip", label: "Leave" }
              ]
              onPicked: function(v) { root.setProfileKey("charge", v) }
            }

            Column {
              visible: !root.chargeHelperReady
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Charge hold needs package vivobook-s14-copilot-charge (git clone https://github.com/paulogeyer/vivobook-s14-copilot-charge.git && makepkg -si). The plugin never runs as root."
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Button {
                text: root.chargeHelperBusy ? "Checking…" : "Recheck charge helper"
                bordered: true
                active: true
                enabled: !root.chargeHelperBusy
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.installChargeHelper()
              }
            }

            OptionRow {
              label: "Keyboard light"
              value: String(root.currentProfile.keyboard || "restore")
              options: [
                { value: "off", label: "Off" },
                { value: "restore", label: "Restore" },
                { value: "skip", label: "Leave" }
              ]
              onPicked: function(v) { root.setProfileKey("keyboard", v) }
            }

            OptionRow {
              label: "Thermal policy"
              value: String(root.currentProfile.thermal || "0")
              options: [
                { value: "2", label: "Silent" },
                { value: "0", label: "Default" },
                { value: "1", label: "Boost" },
                { value: "skip", label: "Leave" }
              ]
              onPicked: function(v) { root.setProfileKey("thermal", v) }
            }

            Row {
              spacing: Style.space(8)
              Button {
                text: "Reset defaults"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.resetDefaults()
              }
              Button {
                text: "Done"
                bordered: true
                active: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.closeSettings()
              }
            }
          }
        }
      }
    }
  }

  component OptionRow: Column {
    property string label: ""
    property string value: ""
    property var options: []
    signal picked(string value)

    width: parent.width
    spacing: Style.space(6)

    Text {
      text: parent.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    ButtonGroup {
      width: parent.width
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      value: parent.value
      options: parent.options
      onChanged: function(v) { parent.picked(v) }
    }
  }
}
