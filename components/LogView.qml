import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Last N lines of one container, followed live. The docker process only runs
// while this view is active.
Item {
  id: root

  property var target: null
  property int maxLines: 200
  property bool active: false
  property var strings: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  property bool follow: true

  signal backRequested()
  signal terminalRequested()

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)

  function t(key, fallback) { return strings ? strings.t(key, fallback) : (fallback || key) }

  function start() {
    proc.running = false
    lines.clear()
    root.follow = true
    var argv = root.target ? Model.withHost(root.target.host, Model.logsArgs(root.target.containerId, root.maxLines)) : null
    if (!argv) return
    proc.command = argv
    proc.running = true
  }

  function stop() {
    proc.running = false
  }

  function push(data) {
    var s = String(data)
    if (s.length > 2000) s = s.slice(0, 2000)
    lines.append({ line: s })
    while (lines.count > root.maxLines) lines.remove(0)
    if (root.follow) Qt.callLater(function() { list.positionViewAtEnd() })
  }

  function followEnd() {
    root.follow = true
    list.positionViewAtEnd()
  }

  onActiveChanged: active ? start() : stop()
  onTargetChanged: if (active) start()
  Component.onDestruction: proc.running = false

  ListModel { id: lines }

  Process {
    id: proc
    running: false
    stdout: SplitParser { onRead: function(data) { root.push(data) } }
    stderr: SplitParser { onRead: function(data) { root.push(data) } }
  }

  Item {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.max(backButton.height, titleText.implicitHeight)

    PanelActionButton {
      id: backButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      iconText: ""
      tooltipText: root.t("action.back")
      foreground: root.fg
      fontFamily: root.fontFamily
      onClicked: root.backRequested()
    }

    Text {
      id: titleText
      anchors.left: backButton.right
      anchors.right: terminalButton.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.t("logs.title").arg(root.target ? root.target.project + "/" + root.target.service : "")
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      elide: Text.ElideMiddle
    }

    PanelActionButton {
      id: terminalButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: ""
      tooltipText: root.t("action.terminal")
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      onClicked: root.terminalRequested()
    }
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.bottom: pausedText.visible ? pausedText.top : parent.bottom
    anchors.topMargin: Style.space(8)
    clip: true
    model: lines
    boundsBehavior: Flickable.StopAtBounds
    ScrollIndicator.vertical: ScrollIndicator {}
    onMovementEnded: root.follow = list.atYEnd

    delegate: Text {
      required property string line
      width: list.width
      textFormat: Text.PlainText
      text: line
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WrapAnywhere
    }

    Text {
      anchors.centerIn: parent
      visible: lines.count === 0
      textFormat: Text.PlainText
      text: root.t("logs.waiting")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Text {
    id: pausedText
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: !root.follow
    textFormat: Text.PlainText
    text: root.t("logs.paused")
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.followEnd()
    }
  }
}
