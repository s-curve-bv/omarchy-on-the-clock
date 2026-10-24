pragma Singleton
import QtQuick
import TestSupport

QtObject {
  function env(name) { return Fs.env[name] || "" }
  function execDetached(command) { Fs.record(command) }
}
