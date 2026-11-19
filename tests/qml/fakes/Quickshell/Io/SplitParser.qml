import QtQuick

QtObject {
  property string splitMarker: "\n"
  property string text: ""
  signal streamFinished()
  signal read(string data)
}
