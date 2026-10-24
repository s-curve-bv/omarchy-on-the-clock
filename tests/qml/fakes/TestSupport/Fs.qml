pragma Singleton
import QtQuick

// In-memory files and a log of started commands, shared by the Quickshell
// stand-ins and the tests.
QtObject {
  property var files: ({})
  property var commands: []
  property var env: ({ HOME: "/home/test" })
  property string processOutput: "committed locally"
  property int processExitCode: 0

  signal changed(string path)

  function reset() {
    files = {}
    commands = []
    processOutput = "committed locally"
    processExitCode = 0
  }
  function read(path) { return files.hasOwnProperty(path) ? files[path] : null }
  function write(path, text) {
    const next = Object.assign({}, files)
    next[path] = text
    files = next
    changed(path)
  }
  function record(command) { commands = commands.concat([command]) }
  function ran(word) { return commands.some(c => c.join(" ").indexOf(word) !== -1) }
}
