import QtQuick
import TestSupport

// Reads and writes Fs. Like the real one it loads when the path is set,
// keeps the loaded text until the next load, and with watchChanges reports
// every write to its path, its own writes included, asynchronously.
QtObject {
  id: view
  property string path: ""
  property bool watchChanges: false
  property bool printErrors: true
  property bool atomicWrites: false
  property bool blockWrites: false
  property bool preload: true
  property string loadedText: ""

  signal loaded()
  signal loadFailed(var error)
  signal fileChanged()
  signal saved()

  function text() { return loadedText }
  function reload() {
    if (!path) return
    const content = Fs.read(path)
    if (content === null) { loadFailed("FileNotFound"); return }
    loadedText = content
    loaded()
  }
  function setText(content) {
    loadedText = content
    Fs.write(path, content)
    saved()
  }

  onPathChanged: Qt.callLater(reload)

  property Connections watcher: Connections {
    target: Fs
    // Reported a moment later, as the real watcher does.
    function onChanged(changedPath) {
      if (view.watchChanges && changedPath === view.path) Qt.callLater(() => view.fileChanged())
    }
  }
}
