pragma Singleton
import QtQuick

// Stand-in for Quickshell.Hyprland's Hyprland: no events in tests.
QtObject {
  signal rawEvent(var event)
  function dispatch(request) {}
}
