pragma Singleton
import QtQuick

// Stand-in for Quickshell.Services.Pipewire: no audio devices in tests.
QtObject {
  property var defaultAudioSource: null
  property var defaultAudioSink: null
  property var nodes: []
  property bool ready: true
}
