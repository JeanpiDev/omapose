import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: Model.PLUGIN_ID

  readonly property string glyph: ""
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  // Shibumi paints its widgets with its own "ink" (seal colour or the colour
  // configured per widget); the native bar uses barForeground.
  readonly property color inkColor: bar && bar.visualTokens
    && typeof bar.visualTokens.widgetContentColor === "function"
    ? bar.visualTokens.widgetContentColor(root.settings, bar.urgent)
    : (bar ? bar.barForeground : Commons.Color.foreground)

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.store = store
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Strings {
    id: tr
    directory: Qt.resolvedUrl("i18n")
    override: store.language
  }

  ComposeStore {
    id: store
    settings: root.settings
    panelOpen: root.opened
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.inkColor
    text: store.runningCount > 0 ? root.glyph + " " + Commons.I18n.formatNumber(store.runningCount) : root.glyph
    dimmed: store.errorKind !== ""
    tooltipText: store.errorKind !== ""
      ? tr.t("error." + store.errorKind, tr.t("error.generic"))
      : tr.tn("panel.services", store.runningCount).arg(Commons.I18n.formatNumber(store.runningCount))
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) store.refresh()
    }
  }

  PluginIpc {
    widget: root
    store: store
  }
}
