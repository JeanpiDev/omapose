import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Plugin settings (written through `omarchy bar set`, so they live in
// shell.json like any other widget setting) and the About card.
Item {
  id: root

  property var store: null
  property var strings: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family

  signal backRequested()

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)

  function t(key, fallback) { return strings ? strings.t(key, fallback) : (fallback || key) }

  function setSetting(key, value) {
    Quickshell.execDetached(["omarchy", "bar", "set", Model.PLUGIN_ID, key, JSON.stringify(value), "--json"])
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
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.t("settings.title")
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
  }

  Flickable {
    id: flick
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(10)
    clip: true
    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollIndicator.vertical: ScrollIndicator {}

    Column {
      id: column
      width: flick.width
      spacing: Style.space(10)

      Column {
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: root.t("settings.language")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ButtonGroup {
          options: [
            { value: "auto", label: root.t("settings.langAuto") },
            { value: "en", label: "English" },
            { value: "es", label: "Español" }
          ]
          value: root.store ? root.store.language : "auto"
          foreground: root.fg
          fontFamily: root.fontFamily
          onChanged: function(value) { root.setSetting("language", value) }
        }
      }

      Toggle {
        width: parent.width
        label: root.t("settings.probe")
        checked: !!root.store && root.store.probeEnabled
        foreground: root.fg
        fontFamily: root.fontFamily
        onClicked: root.setSetting("probePorts", !checked)
      }

      Toggle {
        width: parent.width
        label: root.t("settings.showStopped")
        checked: !!root.store && root.store.showStopped
        foreground: root.fg
        fontFamily: root.fontFamily
        onClicked: root.setSetting("showStopped", !checked)
      }

      NumberField {
        width: parent.width
        label: root.t("settings.logLines")
        from: 50
        to: 2000
        stepSize: 50
        value: root.store ? root.store.logLines : 200
        foreground: root.fg
        fontFamily: root.fontFamily
        onModified: function(value) { root.setSetting("logLines", value) }
      }

      NumberField {
        width: parent.width
        label: root.t("settings.refresh")
        from: 15
        to: 3600
        stepSize: 15
        value: root.store ? root.store.idleRefreshSec : 60
        foreground: root.fg
        fontFamily: root.fontFamily
        onModified: function(value) { root.setSetting("idleRefreshSec", value) }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.fg
      }

      // ---- About ----------------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(4)

        PanelSectionHeader {
          text: root.t("about.title")
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          textFormat: Text.PlainText
          text: "Compose · v" + Model.VERSION
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.t("about.privacy")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          text: root.t("about.repo") + ": " + Model.HOMEPAGE.replace(/^https:\/\//, "")
          color: linkMouse.containsMouse ? Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: linkMouse.containsMouse

          MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(Model.HOMEPAGE)
          }
        }
      }
    }
  }
}
