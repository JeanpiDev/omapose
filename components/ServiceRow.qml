import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var row: null
  property var strings: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  signal actionRequested(string verb)
  signal logsRequested()
  signal portActivated(var port)
  signal hoveredRow()

  readonly property bool busy: !!row && row.busy === "running"
  // A container stuck restarting is "active": offer restart/stop, not start.
  readonly property bool isRunning: !!row && (row.state === "running" || row.state === "restarting")
  readonly property var ports: {
    if (!row) return []
    try { return JSON.parse(row.portsJson) } catch (e) { return [] }
  }
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color stateColor: {
    if (!row) return dim
    if (row.health === "unhealthy" || row.state === "restarting" || row.state === "dead") return Color.urgent
    if (row.state === "running") return Color.accent
    return dim
  }

  function t(key, fallback) { return strings ? strings.t(key, fallback) : (fallback || key) }

  foreground: fg
  width: parent ? parent.width : implicitWidth
  implicitHeight: content.implicitHeight + Style.space(10)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: root.hoveredRow()
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: actions.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(28)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(3)

    // Line 1: state dot, service name and its ports to the right (wraps if
    // there are many). Line 2: state / health under the name.
    Flow {
      id: titleLine
      width: parent.width
      spacing: Style.space(8)

      Text {
        id: dot
        textFormat: Text.PlainText
        text: "●"
        color: root.stateColor
        font.pixelSize: Style.font.caption
        height: nameText.height
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        id: nameText
        textFormat: Text.PlainText
        text: root.row ? root.row.title : ""
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: Math.min(implicitWidth, titleLine.width * 0.5)
      }

      Repeater {
        model: root.ports
        delegate: PortChip {
          required property var modelData
          port: modelData
          strings: root.strings
          fg: root.fg
          fontFamily: root.fontFamily
          onActivated: function(port) { root.portActivated(port) }
        }
      }
    }

    Text {
      leftPadding: dot.width + titleLine.spacing
      textFormat: Text.PlainText
      text: {
        if (!root.row) return ""
        if (root.busy) return root.t("action.busy")
        if (root.row.state !== "running") return root.t("service." + root.row.state, root.row.state)
        if (root.row.health) return root.t("health." + root.row.health, root.row.health)
        return root.t("state.running")
      }
      color: root.busy ? Color.accent : root.stateColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
      visible: !root.isRunning
      iconText: ""
      tooltipText: root.t("action.start")
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      onClicked: root.actionRequested("start")
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
      tooltipText: root.t("action.stop")
      foreground: root.fg
      hoverColor: Color.urgent
      fontFamily: root.fontFamily
      onClicked: root.actionRequested("stop")
    }
    PanelActionButton {
      iconText: ""
      tooltipText: root.t("action.logs")
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      onClicked: root.logsRequested()
    }
  }
}
