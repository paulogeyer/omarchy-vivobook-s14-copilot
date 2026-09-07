import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Headless tuner for the ASUS Vivobook S14 Copilot+ (S5406SA).
// Reapplies extras when AC/battery or power-profiles-daemon changes.
Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string applyBin: pluginDir + "/bin/apply"
  readonly property bool autoBattery: Quickshell.env("OMARCHY_VIVOBOOK_AUTO_BATTERY") !== "0"

  property string pendingMode: ""
  property string pendingProfile: ""
  property string lastTunedKey: ""

  function applyNow(mode, profile) {
    if (pluginDir === "") return
    pendingMode = mode
    pendingProfile = profile || ""
    debounce.restart()
  }

  function runPending() {
    if (pluginDir === "" || applyProcess.running) return
    var mode = pendingMode
    var profile = pendingProfile
    pendingMode = ""
    pendingProfile = ""
    if (mode === "") return

    var cmd = [applyBin]
    var key = ""
    if (mode === "battery-force") {
      cmd.push("--remember", "--source", "battery", "power-saver")
      key = "battery:power-saver"
    } else if (mode === "tune") {
      if (!profile) return
      cmd.push("--tune-only", profile)
      key = "tune:" + profile + ":" + (UPower.onBattery ? "battery" : "ac")
    } else {
      return
    }

    if (key === lastTunedKey) return
    lastTunedKey = key
    applyProcess.command = cmd
    applyProcess.running = true
  }

  function onPowerSourceChanged() {
    lastTunedKey = ""
    if (UPower.onBattery && root.autoBattery) {
      applyNow("battery-force", "power-saver")
      return
    }
    applyNow("tune", "")
  }

  Timer {
    id: debounce
    interval: 400
    repeat: false
    onTriggered: {
      if (root.pendingMode === "tune" && root.pendingProfile === "") {
        ppdQuery.running = true
        return
      }
      root.runPending()
    }
  }

  Process {
    id: applyProcess
    running: false
    onExited: if (root.pendingMode !== "") root.runPending()
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("vivobook.s14-copilot", text.trim())
    }
  }

  Process {
    id: ppdQuery
    command: ["powerprofilesctl", "get"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var profile = text.trim()
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
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.onPowerSourceChanged()
    }
  }

  Component.onCompleted: {
    root.lastTunedKey = ""
    if (UPower.onBattery && root.autoBattery)
      root.applyNow("battery-force", "power-saver")
    else
      root.applyNow("tune", "")
  }
}
