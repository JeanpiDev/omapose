import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

CursorSurface {
  id: root

  property var row: null
  property var strings: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  property string home: ""

  signal toggled()
  signal actionRequested(string verb)
  signal forgetRequested()
  signal hoveredRow()

  readonly property bool busy: !!row && row.busy === "running"
  readonly property bool isRunning: !!row && row.running > 0
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color stateColor: {
    if (!row) return dim
    if (row.state === "running") return Color.accent
    if (row.state === "unhealthy" || row.state === "missing") return Color.urgent
    if (row.state === "partial") return fg
    return dim
  }

  function t(key, fallback) { return strings ? strings.t(key, fallback) : (fallback || key) }

  foreground: fg
  width: parent ? parent.width : implicitWidth
  implicitHeight: content.implicitHeight + Style.space(12)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hoveredRow()
    onClicked: if (root.row && root.row.total > 0) root.toggled()
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: actions.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        // Projects with no containers (after `down`) have nothing to expand.
        text: root.row && root.row.total > 0 ? (root.row.expanded ? "" : "") : " "
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: nameText
        textFormat: Text.PlainText
        text: root.row ? root.row.title : ""
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width * 0.55)
      }

      Text {
        textFormat: Text.PlainText
        text: {
          if (!root.row) return ""
          if (root.busy) return root.t("action.busy")
          var label = root.t("state." + root.row.state, root.row.state)
          return root.row.total > 0 ? label + " · " + root.row.running + "/" + root.row.total : label
        }
        color: root.busy ? Color.accent : root.stateColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      text: root.row ? Model.shortPath(root.row.detail, root.home) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      leftPadding: Style.space(16)
    }

    Text {
      width: parent.width
      visible: !!root.row && root.row.message !== ""
      textFormat: Text.PlainText
      text: root.row ? root.row.message : ""
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
      leftPadding: Style.space(16)
    }
  }

  Row {
    id: actions
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
    enabled: !root.busy
    opacity: root.busy ? 0.4 : 1

    PanelActionButton {
      visible: !!root.row && !root.row.missing && !root.isRunning
      iconText: ""
      tooltipText: root.t("action.up")
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      onClicked: root.actionRequested("up")
    }
    PanelActionButton {
      visible: root.isRunning
      iconText: ""
      tooltipText: root.t("action.restart")
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      onClicked: root.actionRequested("restart")
    }
    PanelActionButton {
      visible: root.isRunning
      iconText: ""
      tooltipText: root.t("action.down")
      foreground: root.fg
      hoverColor: Color.urgent
      fontFamily: root.fontFamily
      onClicked: root.actionRequested("down")
    }
    PanelActionButton {
      visible: !!root.row && root.row.remembered && !root.isRunning && root.row.total === 0
      iconText: ""
      tooltipText: root.t("action.forget")
      foreground: root.fg
      hoverColor: Color.urgent
      fontFamily: root.fontFamily
      onClicked: root.forgetRequested()
    }
  }
}
