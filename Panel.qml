import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "components"

Panel {
  id: root
  moduleName: Model.PLUGIN_ID
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null

  readonly property var barIdentity: hostWidget || root
  property string view: "list"
  property var logTarget: null
  property int selectedIndex: -1
  property bool listFocus: false
  property string statusText: ""
  // Down asks first; the request keeps the engine the list was read from, so
  // confirming can only act on what was shown.
  property var pendingDown: null
  readonly property bool confirmOpen: pendingDown !== null

  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int rowCount: store ? store.rows.count : 0

  Strings {
    id: tr
    directory: Qt.resolvedUrl("i18n")
    override: root.store ? root.store.language : "auto"
  }

  function t(key, fallback) { return tr.t(key, fallback) }

  // ---- lifecycle -------------------------------------------------------------
  function open() {
    root.view = "list"
    root.pendingDown = null
    root.statusText = ""
    root.listFocus = false
    root.selectedIndex = -1
    searchField.text = ""
    list.positionViewAtBeginning()
    root.controller.show()
    Qt.callLater(root.focusSearch)
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: if (!opened) {
    root.view = "list"
    root.pendingDown = null
  }

  // ---- focus & selection -------------------------------------------------------
  function focusSearch() {
    root.listFocus = false
    searchField.forceActiveFocus()
  }

  function enterList(index) {
    if (root.rowCount === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.rowCount - 1, index))
    root.listFocus = true
    searchField.focus = false
    keyCatcher.forceActiveFocus()
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function move(dy) {
    if (root.rowCount === 0) return
    if (!root.listFocus) {
      enterList(dy < 0 ? root.rowCount - 1 : 0)
      return
    }
    var next = root.selectedIndex + dy
    if (next < 0) {
      focusSearch()
      return
    }
    root.selectedIndex = Math.min(root.rowCount - 1, next)
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // Hover only moves the cursor when the list already has focus: it never
  // steals focus from the search field nor scrolls the view.
  function hoverSelect(index) {
    if (root.listFocus) root.selectedIndex = index
  }

  function currentRow() {
    if (!root.store || root.selectedIndex < 0 || root.selectedIndex >= root.rowCount) return null
    return root.store.rows.get(root.selectedIndex)
  }

  Connections {
    target: root.store
    function onRowsSynced() {
      if (root.selectedIndex >= root.rowCount) root.selectedIndex = root.rowCount - 1
      if (root.rowCount === 0) root.listFocus = false
    }
  }

  function flash(message) {
    root.statusText = message || ""
    if (message) statusClear.restart()
  }

  Timer {
    id: statusClear
    interval: 2500
    onTriggered: root.statusText = ""
  }

  // ---- actions -------------------------------------------------------------------
  function projectAction(name, verb) {
    if (!root.store) return
    if (verb === "down") {
      root.pendingDown = { name: name, snapshot: root.store.snapshot(name) }
      return
    }
    root.store.runAction(name, verb, null, root.store.snapshot(name))
  }

  function serviceAction(row, verb) {
    if (root.store && row) root.store.runAction(row.project, verb, row.service, root.store.snapshot(row.project))
  }

  function confirmDown() {
    var request = root.pendingDown
    root.pendingDown = null
    if (request && root.store) root.store.runAction(request.name, "down", null, request.snapshot)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function cancelDown() {
    root.pendingDown = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openLogs(row) {
    if (!row || row.kind !== "service" || !row.containerId) return
    root.logTarget = { project: row.project, service: row.service, containerId: row.containerId, host: root.store.engine ? root.store.engine.host : "" }
    root.view = "logs"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function showList() {
    root.view = "list"
    Qt.callLater(function() {
      if (root.listFocus) keyCatcher.forceActiveFocus()
      else root.focusSearch()
    })
  }

  function portsOf(row) {
    if (!row || row.kind !== "service") return []
    try { return JSON.parse(row.portsJson) } catch (e) { return [] }
  }

  function activatePort(port) {
    if (!port || !root.store) return
    if (port.probe && !Model.probeIsHttp(port.probe)) {
      root.flash(port.probe === "down" ? root.t("status.portDown") : root.t("status.notHttp"))
      return
    }
    root.store.openUrl(port.url)
  }

  function copyPort(row) {
    var ports = root.portsOf(row)
    if (!ports.length || !root.store) return
    var address = Model.addressFor(ports[0].url)
    root.store.copy(address)
    root.flash(root.t("status.copied").arg(address))
  }

  function openFirstHttp(row) {
    var ports = root.portsOf(row)
    for (var i = 0; i < ports.length; i++) {
      if (!ports[i].probe || Model.probeIsHttp(ports[i].probe)) {
        root.activatePort(ports[i])
        return
      }
    }
    if (ports.length) root.activatePort(ports[0])
  }

  function horizontal(dx) {
    var row = root.currentRow()
    if (!row) return
    if (row.kind === "project") {
      if (row.total > 0 && (dx > 0) !== !!row.expanded) root.store.toggleExpanded(row.project)
    } else if (dx > 0) {
      root.openLogs(row)
    } else {
      // ← on a service jumps back to its project row.
      for (var i = root.selectedIndex - 1; i >= 0; i--) {
        if (root.store.rows.get(i).kind === "project") {
          root.selectedIndex = i
          list.positionViewAtIndex(i, ListView.Contain)
          break
        }
      }
    }
  }

  function activateCurrent() {
    var row = root.currentRow()
    if (!row) return
    if (row.kind === "project") { if (row.total > 0) root.store.toggleExpanded(row.project) }
    else root.openLogs(row)
  }

  function shortcut(text) {
    var row = root.currentRow()
    var key = String(text || "")
    if (key === "/") { root.focusSearch(); return }
    if (key === ",") { root.view = "settings"; return }
    if (key === "R") { if (root.store) root.store.refresh(); return }
    if (!row) return
    if (row.kind === "project") {
      if (key === "u") root.projectAction(row.project, "up")
      else if (key === "d") root.projectAction(row.project, "down")
      else if (key === "r") root.projectAction(row.project, "restart")
      else if (key === "f" && row.remembered && row.total === 0) root.store.forgetProject(row.project)
    } else {
      if (key === "s") root.serviceAction(row, row.state === "running" ? "stop" : "start")
      else if (key === "r") root.serviceAction(row, "restart")
      else if (key === "o") root.openFirstHttp(row)
      else if (key === "y") root.copyPort(row)
    }
  }

  // ---- surface -----------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(Style.space(470))

    // Opaque backing: themes may give popups a translucent background, which
    // lets text from windows behind bleed into the list.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -panel.padding
      z: -1
      radius: Style.cornerRadius
      color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.confirmOpen || searchField.activeFocus

      // PanelKeyCatcher reserves h/j/k/l + arrows for movement and x/Delete
      // for delete, so they map to: → / l open (logs or expand), ← / h back.
      onMoveRequested: function(dx, dy) {
        if (root.view === "list") {
          if (dy !== 0) root.move(dy)
          else if (dx !== 0) root.horizontal(dx)
        } else if (root.view === "logs" && dx < 0) {
          root.showList()
        }
      }
      onDeleteRequested: if (root.view === "list") {
        var row = root.currentRow()
        if (!row) return
        if (row.kind === "project") root.projectAction(row.project, "down")
        else if (row.state === "running") root.serviceAction(row, "stop")
      }
      onActivateRequested: if (root.view === "list") root.activateCurrent()
      onCloseRequested: {
        if (root.view !== "list") root.showList()
        else root.close()
      }
      // Omarchy convention: Tab / Shift+Tab move to the neighbouring bar panel.
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text, modifiers) {
        if (root.view === "list") root.shortcut(text)
        else if (root.view === "logs" && (text === "t" || text === "T")) root.store.openTerminalLogs(root.logTarget.project, root.logTarget.service)
      }

      // ---- list view ---------------------------------------------------------------
      Item {
        id: listView
        anchors.fill: parent
        visible: root.view === "list"

        // Same layout as qs.Ui PanelHero, plus a second meta line with the
        // memory used by running containers.
        Item {
          id: hero
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)
          height: implicitHeight

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: ""
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroActions.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.t("title")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.store ? tr.tn("panel.running", root.store.runningCount).arg(Commons.I18n.formatNumber(root.store.runningCount)).toUpperCase() : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          Row {
            id: heroActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            PanelActionButton {
              iconText: ""
              tooltipText: "R"
              foreground: root.fg
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              onClicked: if (root.store) root.store.refresh()
            }
            PanelActionButton {
              iconText: ""
              tooltipText: root.t("action.settings")
              foreground: root.fg
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.view = "settings"
            }
          }
        }

        // Docker CPU / RAM of running containers (docker stats, panel open).
        Row {
          id: usageRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: hero.bottom
          anchors.topMargin: visible ? Style.space(12) : 0
          height: visible ? implicitHeight : 0
          spacing: Style.space(28)
          readonly property var usage: root.store && root.store.runningCount > 0 ? root.store.usage : null
          readonly property var mem: usage ? Model.bytesParts(usage.mem) : null
          readonly property var limit: usage && usage.limit > 0 ? Model.bytesParts(usage.limit) : null
          visible: !!usage

          Column {
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: root.t("stats.cpu").toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Text {
              textFormat: Text.PlainText
              text: usageRow.usage ? root.t("stats.cpuValue").arg(Commons.I18n.formatNumber(usageRow.usage.cpuSystem, usageRow.usage.cpuSystem < 10 ? 1 : 0) + "%") : ""
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Column {
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: root.t("stats.ram").toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Text {
              textFormat: Text.PlainText
              text: {
                if (!usageRow.mem) return ""
                var used = Commons.I18n.formatNumber(usageRow.mem.value, usageRow.mem.decimals) + " " + usageRow.mem.unit
                if (!usageRow.limit || usageRow.usage.memPercent < 0) return used
                return root.t("stats.ramValue")
                  .arg(used)
                  .arg(Commons.I18n.formatNumber(usageRow.usage.memPercent, usageRow.usage.memPercent < 10 ? 1 : 0) + "%")
                  .arg(Commons.I18n.formatNumber(usageRow.limit.value, usageRow.limit.decimals) + " " + usageRow.limit.unit)
              }
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        TextField {
          id: searchField
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: usageRow.bottom
          anchors.topMargin: Style.space(10)
          foreground: root.fg
          font.family: root.fontFamily
          placeholderText: root.t("search.placeholder")
          onTextChanged: if (root.store) root.store.setQuery(text)
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (searchField.text) searchField.text = ""
              else root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.switchPanel(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.enterList(0)
              event.accepted = true
            }
          }
        }

        PanelSeparator {
          id: rule
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: searchField.bottom
          anchors.topMargin: Style.space(8)
          foreground: root.fg
        }

        ListView {
          id: list
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: rule.bottom
          anchors.bottom: footer.top
          anchors.topMargin: Style.space(6)
          anchors.bottomMargin: Style.space(6)
          clip: true
          spacing: Style.space(2)
          model: root.store ? root.store.rows : null
          boundsBehavior: Flickable.StopAtBounds
          visible: !!root.store && root.store.errorKind === ""
          ScrollIndicator.vertical: ScrollIndicator {}

          delegate: Item {
            id: rowItem
            required property int index
            required property var model
            width: list.width
            height: loader.item ? loader.item.implicitHeight : 0

            Loader {
              id: loader
              width: parent.width
              sourceComponent: rowItem.model.kind === "project" ? projectComponent : serviceComponent
            }

            Component {
              id: projectComponent
              ProjectRow {
                row: rowItem.model
                strings: tr
                fg: root.fg
                fontFamily: root.fontFamily
                home: root.store ? root.store.home : ""
                hasCursor: root.listFocus && root.selectedIndex === rowItem.index
                onHoveredRow: root.hoverSelect(rowItem.index)
                onToggled: {
                  if (root.listFocus) root.selectedIndex = rowItem.index
                  root.store.toggleExpanded(rowItem.model.project)
                }
                onActionRequested: function(verb) { root.projectAction(rowItem.model.project, verb) }
                onForgetRequested: root.store.forgetProject(rowItem.model.project)
              }
            }

            Component {
              id: serviceComponent
              ServiceRow {
                row: rowItem.model
                strings: tr
                fg: root.fg
                fontFamily: root.fontFamily
                hasCursor: root.listFocus && root.selectedIndex === rowItem.index
                onHoveredRow: root.hoverSelect(rowItem.index)
                onActionRequested: function(verb) { root.serviceAction(rowItem.model, verb) }
                onLogsRequested: root.openLogs(rowItem.model)
                onPortActivated: function(port) { root.activatePort(port) }
              }
            }
          }
        }

        // Empty and error states share the list area.
        Column {
          anchors.centerIn: list
          width: list.width - Style.space(24)
          spacing: Style.space(4)
          visible: !!root.store && root.store.loaded && (root.store.errorKind !== "" || root.rowCount === 0)

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: {
              if (!root.store) return ""
              if (root.store.errorKind) return root.t("error." + root.store.errorKind, root.t("error.generic"))
              return root.store.query ? root.t("empty.filter") : root.t("empty.none")
            }
            color: root.store && root.store.errorKind ? Color.urgent : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            textFormat: Text.PlainText
            text: {
              if (!root.store) return ""
              if (root.store.errorKind === "daemon") return root.t("error.daemonHint")
              if (root.store.errorKind === "permission") return root.t("error.permissionHint")
              return root.store.errorKind || root.store.query ? "" : root.t("empty.hint")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          // Each "key action" pair is glued with no-break spaces so a wrap only
          // ever happens between hints.
          function glue(s) {
            return String(s).split(" · ").map(function(part) { return part.replace(/ /g, "\u00a0") }).join(" · ")
          }
          text: root.statusText !== "" ? root.statusText
            : glue(root.listFocus
              ? "/ " + root.t("hint.search") + " · ↑↓ " + root.t("hint.move") + " · Enter " + root.t("hint.expand") + " · " + root.t("hint.actions") + " · → " + root.t("hint.logs")
              : "↓ " + root.t("hint.list") + " · Tab " + root.t("hint.panels") + " · Esc " + root.t("hint.close"))
          color: root.statusText !== "" ? Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }

      // ---- logs view -----------------------------------------------------------------
      LogView {
        anchors.fill: parent
        visible: root.view === "logs"
        active: root.opened && root.view === "logs"
        target: root.logTarget
        maxLines: root.store ? root.store.logLines : 200
        strings: tr
        fg: root.fg
        fontFamily: root.fontFamily
        onBackRequested: root.showList()
        onTerminalRequested: if (root.logTarget) root.store.openTerminalLogs(root.logTarget.project, root.logTarget.service)
      }

      // ---- settings view -----------------------------------------------------------------
      SettingsView {
        anchors.fill: parent
        visible: root.view === "settings"
        store: root.store
        strings: tr
        fg: root.fg
        fontFamily: root.fontFamily
        onBackRequested: root.showList()
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.confirmOpen
        focus: root.confirmOpen
        message: root.t("confirm.down").arg(root.pendingDown ? root.pendingDown.name : "")
        confirmText: root.t("action.down")
        background: Color.menu.background
        foreground: Color.menu.text
        scrim: Color.menu.scrim
        selectedBackground: Color.menu.selectedBackground
        selectedText: Color.menu.selectedText
        fontFamily: root.fontFamily
        cornerRadius: Style.cornerRadius
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { if (handleKey(event)) event.accepted = true }
        onCanceled: root.cancelDown()
        onConfirmed: root.confirmDown()
        onOpenedChanged: if (opened) { selectedIndex = 1; forceActiveFocus() }
      }
    }
  }
}
