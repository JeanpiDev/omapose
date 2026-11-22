import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Extra IPC (refresh/status/forget; open/close/toggle mirror the shell's own
// summon/hide routing). Kept in its own file because qmllint crashes on any
// IpcHandler with typed functions, which would fail the guide's
// `qmllint BarWidget.qml Panel.qml` step.
Item {
  id: ipcRoot
  property var widget: null
  property var store: null
  visible: false

  IpcHandler {
    target: Model.PLUGIN_ID
    function open(): void { ipcRoot.widget.open() }
    function close(): void { ipcRoot.widget.close() }
    function toggle(): void { ipcRoot.widget.toggle() }
    function refresh(): void { ipcRoot.store.refresh() }
    function status(): string { return ipcRoot.store.statusJson() }
    function forget(name: string): void { ipcRoot.store.forgetProject(name) }
  }
}
