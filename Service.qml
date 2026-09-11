// Service entrypoint -- runs whichkey-keyd for the lifetime of the shell so the
// plugin needs no systemd user unit. The daemon only *reads* evdev; your user
// must be in the `input` group for it to see any keyboard (see README).
//
// This replaces the unit's Restart=on-failure. whichkey-keyd runs forever once
// it starts (it rescans for hotplugged keyboards itself), so in practice it
// exits only on:
//   - a crash                -> restart, with a short backoff if it flaps
//   - user not in `input`    -> it exits immediately; after a few fast tries we
//                               drop to a 60s retry and log the fix once, so a
//                               later re-login self-heals with no shell restart
//   - SIGTERM from the shell -> `stopping` is set, we do not respawn
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Injected by the shell's plugin loader when present.
  property var shell: null
  property var manifest: null

  // Omarchy 4.0.3 does not populate __sourceDir for third-party manifests, so
  // fall back to this file's own directory.
  readonly property string pluginDir: {
    var s = String((manifest && manifest.__sourceDir) || Qt.resolvedUrl("."))
    if (s.indexOf("file://") === 0)
      s = s.slice("file://".length)
    try {
      s = decodeURIComponent(s)
    } catch (e) {}
    if (s.length > 1 && s.charAt(s.length - 1) === "/")
      s = s.slice(0, -1)
    return s
  }

  // True while the shell is tearing the plugin down, so onExited does not race
  // the shutdown by respawning.
  property bool stopping: false
  // Consecutive exits within healthyMs of starting; drives the backoff.
  property int quickFailures: 0
  property double startedAt: 0
  // Set when we drop to slow-retry, so the hint is logged once, not per minute.
  property bool warnedSlow: false

  readonly property int healthyMs: 3000     // stayed up this long => healthy
  readonly property int fastTries: 6        // fast retries before slowing down
  readonly property int slowRetryMs: 60000  // retry cadence after that

  Component.onCompleted: daemon.running = true
  Component.onDestruction: {
    root.stopping = true
    daemon.running = false
  }

  Process {
    id: daemon
    // setpriv --pdeathsig TERM: the daemon dies with the shell, never leaks.
    command: ["setpriv", "--pdeathsig", "TERM", root.pluginDir + "/whichkey-keyd"]

    onRunningChanged: if (running) {
      root.startedAt = Date.now()
      aliveTimer.restart()
    }

    onExited: (code, status) => {
      aliveTimer.stop()
      if (root.stopping)
        return

      var quick = (Date.now() - root.startedAt) < root.healthyMs
      root.quickFailures = quick ? root.quickFailures + 1 : 0

      if (root.quickFailures >= root.fastTries) {
        if (!root.warnedSlow) {
          root.warnedSlow = true
          console.warn("whichkey: whichkey-keyd keeps exiting immediately "
            + "(code " + code + "). It needs read access to /dev/input/event* -- "
            + "add your user to the 'input' group and fully log out and back in "
            + "(a lock or a new terminal is not enough; `id -nG` must list "
            + "'input'). Retrying every " + (root.slowRetryMs / 1000) + "s.")
        }
        restartTimer.interval = root.slowRetryMs
      } else {
        restartTimer.interval = Math.min(1000 * (root.quickFailures + 1), 10000)
      }
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    repeat: false
    onTriggered: if (!root.stopping) daemon.running = true
  }

  // Held for healthyMs => healthy: clear the failure count and the warning.
  Timer {
    id: aliveTimer
    interval: root.healthyMs
    repeat: false
    onTriggered: {
      if (root.warnedSlow)
        console.log("whichkey: whichkey-keyd is up and reading input")
      root.quickFailures = 0
      root.warnedSlow = false
    }
  }
}
