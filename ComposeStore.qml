import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The only layer that runs processes. Lives inside the bar widget (not a
// shell service) so it works on bars that inject their own `bar` object,
// such as Shibumi, where bar.shell.serviceFor() cannot resolve this plugin.
Item {
  id: root
  visible: false

  property var settings: ({})
  property bool panelOpen: false

  // ---- settings ----------------------------------------------------------
  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null || v === "" ? fallback : v
  }
  function flag(name, fallback) {
    var v = setting(name, fallback)
    return v === true || v === "true" || v === "On" || v === 1
  }
  function number(name, fallback, lo, hi) {
    var n = parseInt(setting(name, fallback), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(lo, Math.min(hi, n))
  }
  readonly property bool probeEnabled: flag("probePorts", true)
  readonly property bool showStopped: flag("showStopped", true)
  readonly property int idleRefreshSec: number("idleRefreshSec", 60, 15, 3600)
  readonly property int logLines: number("logLines", 200, 50, 2000)
  readonly property string language: {
    var v = String(setting("language", "auto"))
    return v === "en" || v === "es" ? v : "auto"
  }

  // ---- state ---------------------------------------------------------------
  property var projects: []
  property var baseProjects: []
  property var remembered: ({})
  property bool rememberedLoaded: false
  property var existing: ({})
  property var probes: ({})
  property var busy: ({})
  property var expanded: ({})
  property string query: ""
  property string errorKind: ""
  // Engine (endpoint + ID) the visible list was read from. Only updated when a
  // listing made with it arrives, so actions always target what is shown.
  property var engine: null
  property var listingEngine: null
  // Engine of baseProjects; set in the same step as baseProjects and only
  // published (with the projects) in finalize().
  property var baseEngine: null
  property string currentHost: ""
  property bool loaded: false
  property bool pendingRefresh: false
  readonly property int runningCount: Model.runningServices(projects)
  property alias rows: rowsModel
  property bool dirReady: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy/omapose"

  signal rowsSynced()

  ListModel { id: rowsModel }

  // ---- reading docker --------------------------------------------------------
  // refresh: resolve the current context's endpoint -> (if it changed) the
  // engine ID -> docker ps pinned to that endpoint.
  function refresh() {
    if (!rememberedLoaded) return
    if (hostProc.running || idProc.running || psProc.running || existProc.running) {
      pendingRefresh = true
      return
    }
    hostProc.running = true
  }

  function hostResolved(out) {
    var host = Model.parseHost(out)
    if (!host) {
      failListing("generic")
      return
    }
    if (host !== root.currentHost) {
      root.currentHost = host
      restartEvents()
    }
    if (root.engine && root.engine.host === host) {
      runPs(root.engine)
      return
    }
    idProc.streams = 0
    idProc.command = Model.engineIdArgs(host)
    idProc.running = true
  }

  function idResolved(out, err) {
    var id = Model.parseEngineId(out)
    if (!id) {
      failListing(Model.classifyError(err) || "generic")
      return
    }
    runPs({ host: root.currentHost, id: id })
  }

  function runPs(engine) {
    root.listingEngine = engine
    psProc.streams = 0
    psProc.command = Model.capped(Model.withHost(engine.host, Model.dockerPsArgs()))
    psProc.running = true
  }

  function failListing(kind) {
    root.errorKind = kind
    root.baseEngine = null
    root.baseProjects = []
    root.existing = ({})
    finalize()
  }

  Process {
    id: hostProc
    command: Model.engineHostArgs()
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.hostResolved(text)
    }
  }

  Process {
    id: idProc
    property int streams: 0
    running: false
    stdout: StdioCollector {
      id: idOut
      waitForEnd: true
      onStreamFinished: if (++idProc.streams === 2) root.idResolved(idOut.text, idErr.text)
    }
    stderr: StdioCollector {
      id: idErr
      waitForEnd: true
      onStreamFinished: if (++idProc.streams === 2) root.idResolved(idOut.text, idErr.text)
    }
  }

  function handlePs(out, err) {
    var text = String(out || "")
    var hasRows = /\S/.test(text)
    var kind = hasRows ? "" : Model.classifyError(err)
    root.errorKind = kind
    root.baseEngine = kind ? null : root.listingEngine
    root.baseProjects = kind ? [] : Model.groupProjects(Model.parseContainers(text))
    if (!kind) {
      var seen = Model.rememberSeen(root.remembered, root.baseProjects, new Date().toISOString())
      if (seen.changed) {
        root.remembered = seen.projects
        saveRemembered()
      }
    }
    var files = kind ? [] : Model.filesToCheck(root.baseProjects, root.remembered)
    if (files.length) {
      existProc.command = ["sh", "-c", "for f in \"$@\"; do [ -e \"$f\" ] && printf '%s\\n' \"$f\"; done; exit 0", "omapose-exists"].concat(files)
      existProc.running = true
    } else {
      root.existing = ({})
      finalize()
    }
  }

  // The only place where the visible engine and projects change, together.
  function finalize() {
    var engine = root.errorKind ? null : root.baseEngine
    var list = root.errorKind ? [] : Model.mergeRemembered(root.baseProjects, root.remembered, root.existing)
    root.projects = Model.stampEngine(list, engine)
    root.engine = engine
    root.loaded = true
    syncRows()
    // A port that appeared since the last probe gets its label right away.
    if (root.panelOpen && root.probeEnabled) {
      var urls = Model.probeUrls(root.projects)
      for (var i = 0; i < urls.length; i++) {
        if (root.probes[urls[i]] === undefined) { root.runProbe(); break }
      }
    }
    if (root.pendingRefresh) {
      root.pendingRefresh = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: psProc
    property int streams: 0
    running: false
    stdout: StdioCollector {
      id: psOut
      waitForEnd: true
      onStreamFinished: if (++psProc.streams === 2) root.handlePs(psOut.text, psErr.text)
    }
    stderr: StdioCollector {
      id: psErr
      waitForEnd: true
      onStreamFinished: if (++psProc.streams === 2) root.handlePs(psOut.text, psErr.text)
    }
  }

  Process {
    id: existProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.existing = Model.parseExisting(text)
        root.finalize()
      }
    }
  }

  // ---- list rows: synced in place by key so scroll and selection survive ----
  function syncRows() {
    var next = Model.buildRows(root.projects, {
      query: root.query,
      expanded: root.expanded,
      busy: root.busy,
      probes: root.probes,
      memory: root.memory,
      showStopped: root.showStopped
    })
    for (var i = 0; i < next.length; i++) {
      var row = next[i]
      if (i < rowsModel.count && rowsModel.get(i).key === row.key) {
        if (rowsModel.get(i).sig !== row.sig) rowsModel.set(i, row)
        continue
      }
      var j = -1
      for (var k = i + 1; k < rowsModel.count; k++) {
        if (rowsModel.get(k).key === row.key) { j = k; break }
      }
      if (j >= 0) {
        rowsModel.move(j, i, 1)
        if (rowsModel.get(i).sig !== row.sig) rowsModel.set(i, row)
      } else {
        rowsModel.insert(i, row)
      }
    }
    while (rowsModel.count > next.length) rowsModel.remove(rowsModel.count - 1)
    root.rowsSynced()
  }

  function setQuery(text) {
    var q = String(text || "")
    if (q === root.query) return
    root.query = q
    syncRows()
  }

  function toggleExpanded(name) {
    var next = {}
    for (var k in root.expanded) next[k] = root.expanded[k]
    next[name] = !next[name]
    root.expanded = next
    syncRows()
  }

  // Frozen copy of what is shown, for actions that need a confirmation.
  function snapshot(projectName) {
    return Model.snapshotFor(root.projects, projectName, root.engine)
  }

  function findProject(name) {
    for (var i = 0; i < root.projects.length; i++) if (root.projects[i].name === name) return root.projects[i]
    return null
  }

  // ---- live updates: docker events, with a slow fallback timer --------------
  property int eventsBackoffMs: 2000
  property bool alive: true

  Process {
    id: eventsProc
    running: false
    command: root.currentHost ? Model.withHost(root.currentHost, Model.eventsArgs()) : Model.eventsArgs()
    stdout: SplitParser {
      onRead: function(data) {
        root.eventsBackoffMs = 2000
        eventsDebounce.restart()
      }
    }
    onExited: function(code) {
      if (!root.alive) return
      eventsRestart.interval = root.eventsBackoffMs
      root.eventsBackoffMs = Math.min(60000, root.eventsBackoffMs * 2)
      eventsRestart.restart()
    }
  }

  // The events stream follows the endpoint of the current context.
  function restartEvents() {
    if (!root.alive || !root.rememberedLoaded) return
    if (eventsProc.running) eventsProc.running = false
    else eventsRestart.restart()
  }

  Timer {
    id: eventsRestart
    repeat: false
    onTriggered: if (root.alive && !eventsProc.running) {
      eventsProc.running = true
      root.refresh()
    }
  }

  Timer {
    id: eventsDebounce
    interval: 300
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.idleRefreshSec * 1000
    running: root.rememberedLoaded
    repeat: true
    onTriggered: root.refresh()
  }

  onPanelOpenChanged: if (panelOpen) refresh()
  onShowStoppedChanged: syncRows()

  // ---- CPU / RAM of running containers (only while the panel is open) ----
  // `docker stats --no-stream` samples for ~1-2 s, so it runs in the
  // background every 10 s and never blocks the list.
  property var usage: null
  property var memory: ({})
  property int cores: 1

  Process {
    id: coresProc
    command: ["nproc"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.cores = Math.max(1, parseInt(String(text).trim(), 10) || 1)
    }
  }

  Timer {
    interval: 10000
    running: root.panelOpen && root.loaded && root.runningCount > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runStats()
  }

  onRunningCountChanged: if (runningCount === 0) { usage = null; memory = ({}) }

  function runStats() {
    if (statsProc.running) return
    var argv = root.engine ? Model.withHost(root.engine.host, Model.statsArgs(Model.runningContainerIds(root.projects))) : null
    if (!argv) { root.usage = null; return }
    statsProc.command = Model.capped(argv)
    statsProc.running = true
  }

  Process {
    id: statsProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var stats = Model.parseStats(text)
        root.usage = Model.usageTotal(root.projects, stats, root.cores)
        root.memory = Model.memoryByContainer(root.projects, stats)
        root.syncRows()
      }
    }
  }

  // ---- HTTP probe (only while the panel is open) ----------------------------
  // Each probe is a real GET that shows up in the app's access log, so probe
  // once when the panel opens and then rarely.
  Timer {
    interval: 60000
    running: root.panelOpen && root.probeEnabled && root.loaded
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runProbe()
  }

  onProbeEnabledChanged: if (!probeEnabled) {
    root.probes = ({})
    syncRows()
  }

  function runProbe() {
    if (probeProc.running) return
    var urls = Model.probeUrls(root.projects)
    if (!urls.length) return
    probeProc.command = Model.probeArgs(urls)
    probeProc.running = true
  }

  Process {
    id: probeProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.probes = Model.parseProbes(text)
        root.syncRows()
      }
    }
  }

  // ---- remembered projects ----------------------------------------------------
  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
    onExited: root.dirReady = true
  }

  FileView {
    id: rememberFile
    path: root.dirReady ? root.stateDir + "/projects.json" : ""
    blockLoading: false
    printErrors: false
    onLoaded: {
      var parsed = Model.parseRemembered(text())
      if (!parsed.ok) {
        Quickshell.execDetached(["mv", "-f", rememberFile.path, rememberFile.path + ".corrupt-" + Date.now()])
      }
      root.remembered = parsed.projects
      root.ready()
    }
    onLoadFailed: function(error) {
      root.remembered = ({})
      root.ready()
    }
  }

  function ready() {
    if (root.rememberedLoaded) return
    root.rememberedLoaded = true
    eventsProc.running = true
    refresh()
  }

  function saveRemembered() {
    rememberFile.setText(Model.serializeRemembered(root.remembered))
  }

  function forgetProject(name) {
    root.remembered = Model.forget(root.remembered, name)
    saveRemembered()
    finalize()
  }

  // ---- actions --------------------------------------------------------------------
  function busyKey(project, service) {
    return service ? "s:" + project + "/" + service : "p:" + project
  }

  function isBusy(key) {
    return !!(root.busy[key] && root.busy[key].status === "running")
  }

  function setBusy(key, entry) {
    var next = {}
    for (var k in root.busy) next[k] = root.busy[k]
    if (entry) next[key] = entry
    else delete next[key]
    root.busy = next
    syncRows()
  }

  // `engine` is the snapshot taken when the action was requested (e.g. when
  // the Down confirmation opened); the guard re-checks it before running.
  // `snapshot` ({ engine, project }) is what was on screen when the action was
  // requested (e.g. when the Down confirmation opened); it is used as-is, so
  // a later refresh or context switch cannot change the target.
  function runAction(projectName, verb, service, snapshot) {
    var shot = snapshot && snapshot.engine && snapshot.project ? snapshot : root.snapshot(projectName)
    var target = shot ? shot.engine : null
    var project = shot ? shot.project : null
    var raw = null
    if (service) {
      var svc = Model.findService(project ? [project] : [], projectName, service)
      raw = svc ? Model.serviceArgs(svc.containerId, verb) : null
    } else {
      raw = Model.composeArgs(project, verb)
    }
    var argv = raw ? Model.guardedArgs(target, raw) : null
    var key = busyKey(projectName, service)
    if (isBusy(key)) return false
    if (!argv) {
      setBusy(key, { status: "error", message: "Docker engine or project is no longer available; refresh and try again", until: Date.now() + 8000 })
      return false
    }
    setBusy(key, { status: "running", message: "", until: 0 })
    var proc = actionComponent.createObject(root, { key: key, argv: argv })
    proc.running = true
    return true
  }

  function finishAction(key, code, output) {
    if (code === 0) setBusy(key, null)
    else setBusy(key, { status: "error", message: Model.cleanMessage(output), until: Date.now() + 8000 })
    refresh()
  }

  Component {
    id: actionComponent
    Process {
      id: action
      property string key: ""
      property var argv: []
      property int exitCode: -1
      property int done: 0
      // stderr is folded into stdout (bounded) so errors can be shown in the row.
      command: ["sh", "-c", "out=$(\"$@\" 2>&1); c=$?; printf '%s' \"$out\" | tail -c 4096; exit $c", "omapose-action"].concat(argv)
      stdout: StdioCollector {
        id: actionOut
        waitForEnd: true
        onStreamFinished: if (++action.done === 2) action.complete()
      }
      onExited: function(code) {
        action.exitCode = code
        if (++action.done === 2) action.complete()
      }
      function complete() {
        root.finishAction(action.key, action.exitCode, actionOut.text)
        action.destroy()
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: {
      for (var k in root.busy) if (root.busy[k].until) return true
      return false
    }
    onTriggered: {
      var now = Date.now()
      var next = {}
      var changed = false
      for (var k in root.busy) {
        if (root.busy[k].until && root.busy[k].until <= now) changed = true
        else next[k] = root.busy[k]
      }
      if (changed) {
        root.busy = next
        root.syncRows()
      }
    }
  }

  // ---- helpers for the UI ----------------------------------------------------------
  function copy(text) {
    if (text) Quickshell.execDetached(["wl-copy", "--", String(text)])
  }

  function openUrl(url) {
    if (/^https?:\/\//.test(String(url))) Quickshell.execDetached(["xdg-open", String(url)])
  }

  function openShell(projectName, service) {
    var svc = Model.findService(root.projects, projectName, service)
    var argv = svc && svc.state === "running" ? Model.shellArgs(root.engine, svc.containerId) : null
    if (argv) Quickshell.execDetached(argv)
    return !!argv
  }

  function openTerminalLogs(projectName, service) {
    var svc = Model.findService(root.projects, projectName, service)
    var argv = svc && root.engine ? Model.terminalLogsArgs(svc.containerId, root.engine.host) : null
    if (argv) Quickshell.execDetached(argv)
  }

  function statusJson() {
    return JSON.stringify({
      projects: root.projects.length,
      running: root.runningCount,
      error: root.errorKind,
      events: eventsProc.running,
      engine: root.engine ? root.engine.host : ""
    })
  }

  Component.onCompleted: mkdirProc.running = true

  Component.onDestruction: {
    root.alive = false
    eventsRestart.stop()
    eventsProc.running = false
    psProc.running = false
    hostProc.running = false
    idProc.running = false
    probeProc.running = false
    existProc.running = false
    statsProc.running = false
  }
}
