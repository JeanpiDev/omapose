// Pure logic for Omarchy Compose. Qt-free so node can unit-test it.
// Everything that comes from docker, files or settings is untrusted: it is
// bounded and validated here before the UI sees it.

var VERSION = "0.1.0"
var PLUGIN_ID = "io.github.jeanpidev.omarchy-compose"
var HOMEPAGE = "https://github.com/JeanpiDev/omarchy-compose"

var MAX_OUTPUT_BYTES = 262144
var MAX_CONTAINERS = 256
var MAX_PROJECTS = 64
var MAX_PROBES = 64
var MAX_PORT_RANGE = 16
var MAX_STATUS = 128
var MAX_PATH = 4096
var MAX_MESSAGE = 512

var STATES = ["running", "exited", "restarting", "paused", "created", "dead", "removing"]
var PROJECT_VERBS = ["up", "down", "restart"]
var SERVICE_VERBS = ["start", "stop", "restart"]
var HTTPS_PORTS = [443, 8443]

var PS_TEMPLATE = "{" + [
  "\"id\":{{json .ID}}",
  "\"project\":{{json (.Label \"com.docker.compose.project\")}}",
  "\"service\":{{json (.Label \"com.docker.compose.service\")}}",
  "\"workingDir\":{{json (.Label \"com.docker.compose.project.working_dir\")}}",
  "\"configFiles\":{{json (.Label \"com.docker.compose.project.config_files\")}}",
  "\"oneoff\":{{json (.Label \"com.docker.compose.oneoff\")}}",
  "\"state\":{{json .State}}",
  "\"status\":{{json .Status}}",
  "\"ports\":{{json .Ports}}"
].join(",") + "}"

// ---- helpers ----------------------------------------------------------------

function str(value, max) {
  var s = value === undefined || value === null ? "" : String(value)
  return max && s.length > max ? s.slice(0, max) : s
}

function trim(value) {
  return str(value).replace(/^\s+|\s+$/g, "")
}

function isProjectName(name) {
  return /^[a-z0-9][a-z0-9_-]{0,127}$/.test(str(name))
}

function isServiceName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/.test(str(name))
}

function isContainerId(id) {
  return /^[0-9a-f]{12,64}$/.test(str(id))
}

function isAbsPath(path) {
  var p = str(path)
  return p.length > 1 && p.length <= MAX_PATH && p.charAt(0) === "/" && p.indexOf("\n") < 0 && p.indexOf("\0") < 0
}

// Wraps an argv so its stdout is capped, without interpolating any value
// into the shell script: the argv travels as "$@".
function capped(argv) {
  return ["sh", "-c", "\"$@\" | head -c " + MAX_OUTPUT_BYTES, "omarchy-compose"].concat(argv)
}

// ---- docker ps -----------------------------------------------------------------

function dockerPsArgs() {
  return ["docker", "ps", "-a", "--no-trunc", "--filter", "label=com.docker.compose.project", "--format", PS_TEMPLATE]
}

function eventsArgs() {
  return ["docker", "events", "--filter", "type=container", "--filter", "label=com.docker.compose.project", "--format", "{{.Action}}"]
}

function healthFromStatus(status) {
  var s = str(status)
  if (/\(unhealthy\)/.test(s)) return "unhealthy"
  if (/\(health: starting\)/.test(s)) return "starting"
  if (/\(healthy\)/.test(s)) return "healthy"
  return ""
}

function splitHostPort(text) {
  var t = trim(text)
  var at = t.lastIndexOf(":")
  if (at < 0) return { host: "", port: t }
  var host = t.slice(0, at)
  if (host.charAt(0) === "[" && host.charAt(host.length - 1) === "]") host = host.slice(1, -1)
  return { host: host, port: t.slice(at + 1) }
}

function portRange(text) {
  var m = /^(\d{1,5})(?:-(\d{1,5}))?$/.exec(trim(text))
  if (!m) return null
  var a = parseInt(m[1], 10)
  var b = m[2] ? parseInt(m[2], 10) : a
  if (a < 1 || b > 65535 || b < a || b - a >= MAX_PORT_RANGE) return null
  return [a, b]
}

// "80/tcp, 127.0.0.1:8081->8081/tcp, :::8081->8081/tcp" -> published ports only.
function parsePorts(field) {
  var out = []
  var seen = {}
  var parts = str(field, 4096).split(",")
  for (var i = 0; i < parts.length; i++) {
    var entry = trim(parts[i])
    var arrow = entry.indexOf("->")
    if (arrow < 0) continue
    var left = splitHostPort(entry.slice(0, arrow))
    var right = entry.slice(arrow + 2)
    var slash = right.indexOf("/")
    var proto = slash >= 0 ? right.slice(slash + 1) : "tcp"
    if (proto !== "tcp" && proto !== "udp") continue
    var hostRange = portRange(left.port)
    var ctrRange = portRange(slash >= 0 ? right.slice(0, slash) : right)
    if (!hostRange || !ctrRange) continue
    for (var p = hostRange[0]; p <= hostRange[1]; p++) {
      var key = proto + ":" + p
      var ipv6 = left.host.indexOf(":") >= 0
      if (seen[key] !== undefined) {
        // Prefer the IPv4 binding when docker reports both families.
        if (!ipv6 && out[seen[key]].host.indexOf(":") >= 0) out[seen[key]].host = left.host
        continue
      }
      seen[key] = out.length
      out.push({
        host: left.host,
        hostPort: p,
        containerPort: ctrRange[0] + (p - hostRange[0]),
        proto: proto
      })
    }
  }
  out.sort(function (a, b) { return a.hostPort - b.hostPort })
  return out
}

function parseContainer(obj) {
  if (!obj || typeof obj !== "object") return null
  var project = str(obj.project)
  var service = str(obj.service)
  var id = str(obj.id)
  if (!isProjectName(project) || !isServiceName(service) || !isContainerId(id)) return null
  if (str(obj.oneoff) === "True") return null
  var state = str(obj.state)
  if (STATES.indexOf(state) < 0) state = "dead"
  var files = []
  var rawFiles = str(obj.configFiles, MAX_PATH * 4).split(",")
  for (var i = 0; i < rawFiles.length && files.length < 8; i++) {
    if (isAbsPath(rawFiles[i])) files.push(rawFiles[i])
  }
  var status = str(obj.status, MAX_STATUS)
  return {
    id: id,
    project: project,
    service: service,
    workingDir: isAbsPath(obj.workingDir) ? str(obj.workingDir) : "",
    configFiles: files,
    state: state,
    status: status,
    health: healthFromStatus(status),
    ports: parsePorts(obj.ports)
  }
}

function parseContainers(raw) {
  var out = []
  var lines = str(raw, MAX_OUTPUT_BYTES).split("\n")
  for (var i = 0; i < lines.length && out.length < MAX_CONTAINERS; i++) {
    var line = trim(lines[i])
    if (!line) continue
    var obj = null
    try { obj = JSON.parse(line) } catch (e) { obj = null }
    var c = parseContainer(obj)
    if (c) out.push(c)
  }
  return out
}

// ---- projects ----------------------------------------------------------------

function serviceRank(state) {
  return state === "running" ? 0 : state === "restarting" ? 1 : state === "paused" ? 2 : 3
}

function aggregateState(services, missing) {
  if (missing) return "missing"
  // No "completed one-shot" heuristic: a server stopped with `docker stop`
  // also exits 0 and stopped containers report no ports, so they cannot be
  // told apart from init containers. The row shows running/total instead.
  var running = 0
  var unhealthy = false
  for (var i = 0; i < services.length; i++) {
    if (services[i].state === "running") running++
    if (services[i].health === "unhealthy" || services[i].state === "restarting" || services[i].state === "dead") unhealthy = true
  }
  if (unhealthy && running > 0) return "unhealthy"
  if (services.length > 0 && running === services.length) return "running"
  if (running > 0) return "partial"
  return "stopped"
}

// Containers -> projects (one service entry per compose service; with scaled
// services the most "alive" container represents the service).
function groupProjects(containers) {
  var byName = {}
  var order = []
  for (var i = 0; i < containers.length; i++) {
    var c = containers[i]
    var p = byName[c.project]
    if (!p) {
      if (order.length >= MAX_PROJECTS) continue
      p = { name: c.project, workingDir: c.workingDir, configFiles: c.configFiles.slice(), services: {}, remembered: false, missing: false }
      byName[c.project] = p
      order.push(c.project)
    }
    if (!p.workingDir && c.workingDir) p.workingDir = c.workingDir
    if (!p.configFiles.length && c.configFiles.length) p.configFiles = c.configFiles.slice()
    var cur = p.services[c.service]
    if (!cur || serviceRank(c.state) < serviceRank(cur.state)) {
      p.services[c.service] = {
        name: c.service,
        containerId: c.id,
        state: c.state,
        health: c.health,
        status: c.status,
        ports: c.ports
      }
    }
  }
  var out = []
  for (var j = 0; j < order.length; j++) out.push(finishProject(byName[order[j]]))
  return sortProjects(out)
}

function finishProject(p) {
  var names = Object.keys(p.services).sort()
  var list = []
  for (var i = 0; i < names.length; i++) list.push(p.services[names[i]])
  var running = 0
  for (var k = 0; k < list.length; k++) if (list[k].state === "running") running++
  return {
    name: p.name,
    workingDir: p.workingDir,
    configFiles: p.configFiles,
    services: list,
    running: running,
    remembered: !!p.remembered,
    missing: !!p.missing,
    state: aggregateState(list, p.missing)
  }
}

function sortProjects(list) {
  return list.sort(function (a, b) {
    var ar = a.running > 0 ? 0 : 1
    var br = b.running > 0 ? 0 : 1
    return ar - br || a.name.localeCompare(b.name)
  })
}

// Adds remembered projects that have no containers (after `down`).
// `existing` maps config file path -> true for files that still exist.
function mergeRemembered(projects, remembered, existing) {
  var out = projects.slice()
  var have = {}
  for (var i = 0; i < out.length; i++) {
    have[out[i].name] = true
    if (remembered && remembered[out[i].name]) out[i].remembered = true
  }
  var names = remembered ? Object.keys(remembered).sort() : []
  for (var j = 0; j < names.length && out.length < MAX_PROJECTS; j++) {
    var name = names[j]
    if (have[name]) continue
    var r = remembered[name]
    var files = r.configFiles || []
    var missing = files.length === 0
    for (var f = 0; f < files.length; f++) if (!existing || !existing[files[f]]) missing = true
    out.push({
      name: name,
      workingDir: r.workingDir || "",
      configFiles: files,
      services: [],
      running: 0,
      remembered: true,
      missing: missing,
      state: missing ? "missing" : "stopped"
    })
  }
  return sortProjects(out)
}

// ---- remembered projects file ---------------------------------------------------

function parseRemembered(raw) {
  var data = null
  try { data = JSON.parse(str(raw, MAX_OUTPUT_BYTES) || "{}") } catch (e) { return { ok: false, projects: {} } }
  var projects = {}
  var src = data && data.projects && typeof data.projects === "object" ? data.projects : {}
  var names = Object.keys(src)
  for (var i = 0; i < names.length && Object.keys(projects).length < MAX_PROJECTS; i++) {
    var name = names[i]
    var r = src[name]
    if (!isProjectName(name) || !r || typeof r !== "object") continue
    var files = []
    var rf = Array.isArray(r.configFiles) ? r.configFiles : []
    for (var f = 0; f < rf.length && files.length < 8; f++) if (isAbsPath(rf[f])) files.push(str(rf[f]))
    projects[name] = {
      workingDir: isAbsPath(r.workingDir) ? str(r.workingDir) : "",
      configFiles: files,
      lastSeen: str(r.lastSeen, 40)
    }
  }
  return { ok: true, projects: projects }
}

// Returns { changed, projects } after recording every project seen in docker.
function rememberSeen(remembered, projects, nowIso) {
  var next = {}
  var changed = false
  var names = Object.keys(remembered || {})
  for (var i = 0; i < names.length; i++) next[names[i]] = remembered[names[i]]
  for (var j = 0; j < projects.length; j++) {
    var p = projects[j]
    if (!p.configFiles.length || p.services.length === 0) continue
    var prev = next[p.name]
    var same = prev && prev.workingDir === p.workingDir && JSON.stringify(prev.configFiles) === JSON.stringify(p.configFiles)
    if (same) continue
    next[p.name] = { workingDir: p.workingDir, configFiles: p.configFiles.slice(), lastSeen: str(nowIso, 40) }
    changed = true
  }
  return { changed: changed, projects: next }
}

function forget(remembered, name) {
  var next = {}
  var names = Object.keys(remembered || {})
  for (var i = 0; i < names.length; i++) if (names[i] !== name) next[names[i]] = remembered[names[i]]
  return next
}

function serializeRemembered(projects) {
  return JSON.stringify({ version: 1, projects: projects || {} }, null, 2) + "\n"
}

// Config files of remembered projects that have no containers right now.
function filesToCheck(projects, remembered) {
  var have = {}
  for (var i = 0; i < projects.length; i++) have[projects[i].name] = true
  var out = []
  var names = Object.keys(remembered || {})
  for (var j = 0; j < names.length; j++) {
    if (have[names[j]]) continue
    var files = remembered[names[j]].configFiles || []
    for (var f = 0; f < files.length; f++) if (out.indexOf(files[f]) < 0) out.push(files[f])
  }
  return out
}

function parseExisting(raw) {
  var out = {}
  var lines = str(raw, MAX_OUTPUT_BYTES).split("\n")
  for (var i = 0; i < lines.length; i++) if (isAbsPath(lines[i])) out[lines[i]] = true
  return out
}

// ---- rows for the list view -------------------------------------------------------

function matches(text, query) {
  return str(text).toLowerCase().indexOf(query) >= 0
}

// Flattens projects into list rows. `expanded` maps project name -> bool;
// while filtering every matching project is shown expanded.
function buildRows(projects, options) {
  var opts = options || {}
  var query = trim(opts.query).toLowerCase()
  var expanded = opts.expanded || {}
  var busy = opts.busy || {}
  var probes = opts.probes || {}
  var rows = []
  for (var i = 0; i < projects.length; i++) {
    var p = projects[i]
    if (!opts.showStopped && p.running === 0 && !query) continue
    var projectHit = !query || matches(p.name, query) || matches(p.workingDir, query)
    var services = []
    for (var s = 0; s < p.services.length; s++) {
      var svc = p.services[s]
      if (projectHit || matches(svc.name, query)) services.push(svc)
    }
    if (!projectHit && services.length === 0) continue
    var open = query ? true : !!expanded[p.name]
    var pKey = "p:" + p.name
    var pBusy = busy[pKey] || {}
    rows.push(rowFor({
      key: pKey,
      kind: "project",
      project: p.name,
      title: p.name,
      state: p.state,
      detail: p.workingDir,
      running: p.running,
      total: p.services.length,
      expanded: open,
      remembered: p.remembered,
      missing: p.missing,
      busy: str(pBusy.status),
      message: str(pBusy.message, MAX_MESSAGE)
    }))
    if (!open) continue
    for (var k = 0; k < services.length; k++) {
      var sv = services[k]
      var sKey = "s:" + p.name + "/" + sv.name
      var sBusy = busy[sKey] || {}
      var ports = []
      for (var q = 0; q < sv.ports.length; q++) {
        var port = sv.ports[q]
        var url = port.proto === "tcp" ? browseUrl(port) : ""
        ports.push({ hostPort: port.hostPort, containerPort: port.containerPort, proto: port.proto, url: url, probe: url ? str(probes[url]) : "" })
      }
      rows.push(rowFor({
        key: sKey,
        kind: "service",
        project: p.name,
        service: sv.name,
        title: sv.name,
        state: sv.state,
        health: sv.health,
        detail: sv.status,
        containerId: sv.containerId,
        portsJson: JSON.stringify(ports),
        busy: str(sBusy.status),
        message: str(sBusy.message, MAX_MESSAGE)
      }))
    }
  }
  return rows
}

// Every row carries the same roles (ListModel needs a stable role set).
function rowFor(fields) {
  var row = {
    key: "", kind: "", project: "", service: "", title: "", state: "", health: "",
    detail: "", containerId: "", portsJson: "[]", running: 0, total: 0,
    expanded: false, remembered: false, missing: false, busy: "", message: "", sig: ""
  }
  for (var k in fields) if (row.hasOwnProperty(k)) row[k] = fields[k]
  var copy = {}
  for (var f in row) if (f !== "sig") copy[f] = row[f]
  row.sig = JSON.stringify(copy)
  return row
}

function runningServices(projects) {
  var n = 0
  for (var i = 0; i < projects.length; i++) n += projects[i].running
  return n
}

// ---- errors ------------------------------------------------------------------------

function classifyError(stderr) {
  var s = str(stderr, 4096).toLowerCase()
  if (!s) return ""
  if (s.indexOf("permission denied") >= 0) return "permission"
  if (s.indexOf("cannot connect to the docker daemon") >= 0 || s.indexOf("is the docker daemon running") >= 0) return "daemon"
  return "generic"
}

// ---- ports / HTTP probe ---------------------------------------------------------------

function browseUrl(port) {
  if (!port || !port.hostPort) return ""
  var host = str(port.host)
  if (!host || host === "0.0.0.0") host = "127.0.0.1"
  else if (host === "::") host = "[::1]"
  else if (host.indexOf(":") >= 0) host = "[" + host + "]"
  var scheme = HTTPS_PORTS.indexOf(port.hostPort) >= 0 ? "https" : "http"
  return scheme + "://" + host + ":" + port.hostPort
}

function addressFor(url) {
  return str(url).replace(/^https?:\/\//, "")
}

function probeUrls(projects) {
  var out = []
  for (var i = 0; i < projects.length; i++) {
    var services = projects[i].services
    for (var s = 0; s < services.length; s++) {
      if (services[s].state !== "running") continue
      var ports = services[s].ports
      for (var p = 0; p < ports.length && out.length < MAX_PROBES; p++) {
        if (ports[p].proto !== "tcp") continue
        var url = browseUrl(ports[p])
        if (url && out.indexOf(url) < 0) out.push(url)
      }
    }
  }
  return out
}

var PROBE_SCRIPT = [
  "for u in \"$@\"; do",
  "  c=$(curl -sk -o /dev/null --max-time 1 -w '%{http_code}' \"$u\" 2>/dev/null)",
  "  e=$?",
  "  printf '%s\\t%s\\t%s\\n' \"$u\" \"$c\" \"$e\"",
  "done"
].join("\n")

function probeArgs(urls) {
  return ["sh", "-c", PROBE_SCRIPT, "omarchy-compose-probe"].concat(urls.slice(0, MAX_PROBES))
}

// Lines "<url>\t<http_code>\t<curl_exit>" -> { url: "http:<code>" | "tcp" | "down" }
function parseProbes(raw) {
  var out = {}
  var lines = str(raw, MAX_OUTPUT_BYTES).split("\n")
  for (var i = 0; i < lines.length && i < MAX_PROBES; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 3) continue
    var url = trim(parts[0])
    var code = trim(parts[1])
    var exit = parseInt(trim(parts[2]), 10)
    if (!/^https?:\/\/[^\s]+$/.test(url)) continue
    if (/^[1-5][0-9][0-9]$/.test(code)) out[url] = "http:" + code
    else if (exit === 7) out[url] = "down"
    else out[url] = "tcp"
  }
  return out
}

function probeCode(status) {
  var m = /^http:([0-9]{3})$/.exec(str(status))
  return m ? parseInt(m[1], 10) : 0
}

function probeIsHttp(status) {
  return probeCode(status) > 0
}

// Returns { key, code } so the UI can translate the label.
function probeLabel(status) {
  var code = probeCode(status)
  if (code === 401 || code === 403) return { key: "probe.auth", code: code }
  if (code === 404) return { key: "probe.api", code: code }
  if (code > 0) return { key: "", code: code }
  if (status === "tcp") return { key: "probe.tcp", code: 0 }
  if (status === "down") return { key: "probe.down", code: 0 }
  return { key: "", code: 0 }
}

// "ok" | "warn" | "muted" | "down" | ""
function probeTone(status) {
  var code = probeCode(status)
  if (code >= 200 && code < 400) return "ok"
  if (code >= 400) return "warn"
  if (status === "tcp") return "muted"
  if (status === "down") return "down"
  return ""
}

// ---- compose actions ------------------------------------------------------------------

// Project-level actions go through compose. `down` and `restart` enable every
// profile so services behind `profiles:` are included; `down` also removes
// orphans (containers of services no longer in the file). `up` keeps the
// default profile so it never starts e.g. test services by surprise.
function composeArgs(project, verb) {
  if (!project || !isProjectName(project.name)) return null
  if (PROJECT_VERBS.indexOf(verb) < 0) return null
  var files = project.configFiles || []
  if (!files.length) return null
  var argv = ["docker", "compose", "-p", project.name]
  if (isAbsPath(project.workingDir)) argv.push("--project-directory", project.workingDir)
  for (var i = 0; i < files.length; i++) {
    if (!isAbsPath(files[i])) return null
    argv.push("-f", files[i])
  }
  if (verb !== "up") argv.push("--profile", "*")
  argv.push(verb)
  if (verb === "up") argv.push("-d")
  if (verb === "down") argv.push("--remove-orphans")
  return argv
}

// Service-level actions act on the container itself: compose would answer
// "no such service" for services behind a profile or no longer in the file.
function serviceArgs(containerId, verb) {
  if (!isContainerId(containerId) || SERVICE_VERBS.indexOf(verb) < 0) return null
  return ["docker", verb, containerId]
}

function findService(projects, projectName, serviceName) {
  for (var i = 0; i < projects.length; i++) {
    if (projects[i].name !== projectName) continue
    var services = projects[i].services
    for (var s = 0; s < services.length; s++) if (services[s].name === serviceName) return services[s]
  }
  return null
}

function logsArgs(containerId, lines) {
  if (!isContainerId(containerId)) return null
  var n = Math.max(10, Math.min(2000, parseInt(lines, 10) || 200))
  return ["docker", "logs", "--tail", String(n), "-f", containerId]
}

function terminalLogsArgs(containerId) {
  if (!isContainerId(containerId)) return null
  return ["xdg-terminal-exec", "docker", "logs", "-f", "--tail", "200", containerId]
}

function cleanMessage(stderr) {
  var lines = str(stderr, 8192).split("\n")
  var kept = []
  for (var i = lines.length - 1; i >= 0 && kept.length < 3; i--) {
    var l = trim(lines[i])
    if (l) kept.unshift(l)
  }
  return str(kept.join(" · "), MAX_MESSAGE)
}

var LANGUAGES = ["en", "es"]

// "auto" follows Omarchy's language (base code, e.g. "es-CO" -> "es");
// anything unsupported falls back to English.
function languageFor(override, systemLanguage) {
  var o = str(override)
  if (o !== "auto" && LANGUAGES.indexOf(o) >= 0) return o
  var base = str(systemLanguage).split("-")[0].toLowerCase()
  return LANGUAGES.indexOf(base) >= 0 ? base : "en"
}

// Catalog entry -> string. Plural entries are { one, other }; English and
// Spanish only use "one" for exactly 1. count < 0 means "not a count".
function pluralPick(entry, count) {
  if (typeof entry === "string") return entry
  if (!entry || typeof entry !== "object") return ""
  if (count === 1 && typeof entry.one === "string") return entry.one
  return typeof entry.other === "string" ? entry.other : ""
}

function shortPath(path, home) {
  var p = str(path)
  var h = str(home)
  if (h && p.indexOf(h + "/") === 0) return "~" + p.slice(h.length)
  return p
}

if (typeof module !== "undefined") {
  module.exports = {
    VERSION: VERSION,
    PLUGIN_ID: PLUGIN_ID,
    HOMEPAGE: HOMEPAGE,
    MAX_OUTPUT_BYTES: MAX_OUTPUT_BYTES,
    capped: capped,
    dockerPsArgs: dockerPsArgs,
    eventsArgs: eventsArgs,
    healthFromStatus: healthFromStatus,
    parsePorts: parsePorts,
    parseContainers: parseContainers,
    groupProjects: groupProjects,
    aggregateState: aggregateState,
    mergeRemembered: mergeRemembered,
    parseRemembered: parseRemembered,
    rememberSeen: rememberSeen,
    forget: forget,
    serializeRemembered: serializeRemembered,
    filesToCheck: filesToCheck,
    parseExisting: parseExisting,
    buildRows: buildRows,
    runningServices: runningServices,
    classifyError: classifyError,
    browseUrl: browseUrl,
    addressFor: addressFor,
    probeUrls: probeUrls,
    probeArgs: probeArgs,
    parseProbes: parseProbes,
    probeCode: probeCode,
    probeIsHttp: probeIsHttp,
    probeLabel: probeLabel,
    probeTone: probeTone,
    composeArgs: composeArgs,
    serviceArgs: serviceArgs,
    findService: findService,
    logsArgs: logsArgs,
    terminalLogsArgs: terminalLogsArgs,
    cleanMessage: cleanMessage,
    languageFor: languageFor,
    pluralPick: pluralPick,
    shortPath: shortPath
  }
}
