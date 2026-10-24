import QtQuick
import TestSupport

// Records its command in Fs and "finishes" right away with Fs.processOutput.
QtObject {
  id: process
  property var command: []
  property bool running: false
  property var stdout: null
  property var stderr: null
  property var environment: ({})

  signal started()
  signal exited(int exitCode, int exitStatus)

  function exec(cmd) { command = cmd; running = true }

  onRunningChanged: {
    if (!running) return
    Fs.record(command)
    Qt.callLater(() => {
      process.running = false
      const out = process.processExitCode === 0 ? process.stdout : process.stderr
      if (out) { out.text = Fs.processOutput; out.streamFinished() }
      process.exited(Fs.processExitCode, 0)
    })
  }
  readonly property int processExitCode: Fs.processExitCode
}
