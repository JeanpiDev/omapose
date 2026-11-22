import QtQuick
import qs.Commons
import "../Model.js" as Model

// One published port with its HTTP/TCP status. Click: open in the browser
// when the port answers HTTP, otherwise report why (the panel shows it).
Rectangle {
  id: root

  property var port: null
  property var strings: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  signal activated(var port)

  readonly property string probe: port ? String(port.probe || "") : ""
  readonly property var label: Model.probeLabel(probe)
  readonly property string tone: Model.probeTone(probe)
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color toneColor: tone === "ok" ? Color.accent
    : tone === "down" ? Color.urgent
    : tone === "warn" ? fg
    : dim

  function t(key) { return strings ? strings.t(key) : key }

  readonly property string statusText: {
    if (label.code > 0) return "HTTP " + label.code + (label.key ? " · " + t(label.key) : "")
    return label.key ? t(label.key) : ""
  }

  implicitWidth: chipText.implicitWidth + Style.space(14)
  implicitHeight: chipText.implicitHeight + Style.space(4)
  radius: Style.cornerRadius > 0 ? height / 2 : 0
  color: mouse.containsMouse ? Qt.rgba(fg.r, fg.g, fg.b, 0.08) : "transparent"
  border.width: 1
  border.color: Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.45)

  Text {
    id: chipText
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.port ? ":" + root.port.hostPort + (root.statusText ? "  " + root.statusText : "") : ""
    color: root.toneColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: root.tone === "ok"
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated(root.port)
  }
}
