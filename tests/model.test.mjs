import { test } from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"
import { readFileSync } from "node:fs"

const require = createRequire(import.meta.url)
const M = require("../Model.js")
const manifest = JSON.parse(readFileSync(new URL("../manifest.json", import.meta.url)))

const line = (o) => JSON.stringify(Object.assign({
  id: "49f2a52e9bbd006a94cd5a880698c25d976ca68fd4359967f6bf4bc38fd9d3ab",
  project: "shop", service: "api", workingDir: "/home/u/shop",
  configFiles: "/home/u/shop/compose.yml", oneoff: "False",
  state: "running", status: "Up 2 hours (healthy)", ports: "127.0.0.1:8081->8081/tcp"
}, o))

test("manifest and Model agree on id, version and homepage", () => {
  assert.equal(manifest.id, M.PLUGIN_ID)
  assert.equal(manifest.version, M.VERSION)
  assert.equal(manifest.homepage, M.HOMEPAGE)
})

test("docker ps template extracts labels one by one (no raw .Labels)", () => {
  const argv = M.dockerPsArgs()
  const tpl = argv[argv.length - 1]
  assert.ok(tpl.includes('(.Label "com.docker.compose.project.config_files")'))
  assert.ok(!tpl.includes(".Labels"))
})

test("capped wraps argv without interpolating values", () => {
  const argv = M.capped(["docker", "ps", "--format", "$(rm -rf ~)"])
  assert.equal(argv[0], "sh")
  assert.equal(argv[2], "\"$@\" | head -c " + M.MAX_OUTPUT_BYTES)
  assert.equal(argv[argv.length - 1], "$(rm -rf ~)")
})

test("parseContainers keeps config files that contain commas split correctly", () => {
  const raw = line({ configFiles: "/a/b/compose.yml,/a/b/compose.override.yml" })
  const [c] = M.parseContainers(raw)
  assert.deepEqual(c.configFiles, ["/a/b/compose.yml", "/a/b/compose.override.yml"])
})

test("parseContainers drops invalid, one-off and garbage lines", () => {
  const raw = [
    line({}),
    line({ project: "Bad Name" }),
    line({ id: "zzz" }),
    line({ oneoff: "True" }),
    "not json",
    "",
    line({ service: "<img src=x>" })
  ].join("\n")
  const out = M.parseContainers(raw)
  assert.equal(out.length, 1)
  assert.equal(out[0].health, "healthy")
})

test("parseContainers bounds status length and unknown states", () => {
  const [c] = M.parseContainers(line({ status: "x".repeat(500), state: "weird" }))
  assert.equal(c.status.length, 128)
  assert.equal(c.state, "dead")
})

test("markup-shaped text stays plain data", () => {
  const [c] = M.parseContainers(line({ status: "<b>Up</b> <img src=\"https://example.invalid/t\">" }))
  assert.equal(c.status, "<b>Up</b> <img src=\"https://example.invalid/t\">")
})

test("parsePorts: published only, IPv4 preferred over IPv6, ranges", () => {
  const ports = M.parsePorts("80/tcp, 0.0.0.0:8081->8081/tcp, :::8081->8081/tcp, 127.0.0.1:3000-3002->4000-4002/tcp, [::1]:9000->9000/udp")
  assert.deepEqual(ports.map(p => [p.host, p.hostPort, p.containerPort, p.proto]), [
    ["127.0.0.1", 3000, 4000, "tcp"],
    ["127.0.0.1", 3001, 4001, "tcp"],
    ["127.0.0.1", 3002, 4002, "tcp"],
    ["0.0.0.0", 8081, 8081, "tcp"],
    ["::1", 9000, 9000, "udp"]
  ])
})

test("parsePorts rejects huge ranges and bad ports", () => {
  assert.deepEqual(M.parsePorts("0.0.0.0:1000-9000->1000-9000/tcp, 1.2.3.4:99999->1/tcp"), [])
})

test("health is derived from status", () => {
  assert.equal(M.healthFromStatus("Up 3 minutes (unhealthy)"), "unhealthy")
  assert.equal(M.healthFromStatus("Up 3 seconds (health: starting)"), "starting")
  assert.equal(M.healthFromStatus("Exited (0) 2 hours ago"), "")
})

test("groupProjects aggregates state and keeps the most alive container", () => {
  const raw = [
    line({ service: "api" }),
    line({ service: "db", id: "a".repeat(64), state: "exited", status: "Exited (137) 1 hour ago" }),
    line({ project: "other", service: "web", id: "b".repeat(64), state: "running", status: "Up" }),
    line({ project: "sick", service: "web", id: "c".repeat(64), status: "Up (unhealthy)" }),
    line({ project: "sick", service: "web", id: "d".repeat(64), state: "exited", status: "Exited (1)" })
  ].join("\n")
  const projects = M.groupProjects(M.parseContainers(raw))
  const byName = Object.fromEntries(projects.map(p => [p.name, p]))
  assert.equal(byName.shop.state, "partial")
  assert.equal(byName.shop.running, 1)
  assert.equal(byName.other.state, "running")
  assert.equal(byName.sick.services.length, 1)
  assert.equal(byName.sick.state, "unhealthy")
  assert.equal(M.runningServices(projects), 3)
})

test("any stopped service makes a running project partial (no exit-code heuristic)", () => {
  const projects = M.groupProjects(M.parseContainers([
    line({ service: "cache" }),
    line({ service: "init", id: "f".repeat(64), state: "exited", status: "Exited (0) 25 hours ago", ports: "" })
  ].join("\n")))
  assert.equal(projects[0].state, "partial")
  assert.equal(projects[0].running, 1)
})

test("remembered projects survive `down` and flag missing compose files", () => {
  const remembered = M.parseRemembered(JSON.stringify({
    version: 1,
    projects: {
      gone: { workingDir: "/w/gone", configFiles: ["/w/gone/compose.yml"] },
      down: { workingDir: "/w/down", configFiles: ["/w/down/compose.yml"] },
      "Bad Name": { configFiles: ["/x"] }
    }
  })).projects
  assert.deepEqual(Object.keys(remembered).sort(), ["down", "gone"])
  const files = M.filesToCheck([], remembered)
  assert.deepEqual(files.sort(), ["/w/down/compose.yml", "/w/gone/compose.yml"])
  const existing = M.parseExisting("/w/down/compose.yml\n")
  const merged = M.mergeRemembered([], remembered, existing)
  const byName = Object.fromEntries(merged.map(p => [p.name, p]))
  assert.equal(byName.down.state, "stopped")
  assert.equal(byName.gone.state, "missing")
})

test("parseRemembered tolerates corrupt JSON", () => {
  assert.deepEqual(M.parseRemembered("{oops"), { ok: false, projects: {} })
  assert.equal(M.parseRemembered("").ok, true)
})

test("rememberSeen only reports a change when something new is seen", () => {
  const projects = M.groupProjects(M.parseContainers(line({})))
  const first = M.rememberSeen({}, projects, "2026-11-22T00:00:00Z")
  assert.equal(first.changed, true)
  const second = M.rememberSeen(first.projects, projects, "2026-11-23T00:00:00Z")
  assert.equal(second.changed, false)
  assert.deepEqual(Object.keys(M.forget(first.projects, "shop")), [])
})

test("buildRows: stable roles, collapse, filter and showStopped", () => {
  const projects = M.groupProjects(M.parseContainers([
    line({}),
    line({ project: "idle", service: "web", id: "e".repeat(64), state: "exited", status: "Exited (0)" })
  ].join("\n")))
  const collapsed = M.buildRows(projects, { showStopped: true })
  assert.deepEqual(collapsed.map(r => r.key), ["p:shop", "p:idle"])
  const keys = Object.keys(collapsed[0]).sort()
  for (const r of collapsed) assert.deepEqual(Object.keys(r).sort(), keys)
  const open = M.buildRows(projects, { showStopped: false, expanded: { shop: true } })
  assert.deepEqual(open.map(r => r.key), ["p:shop", "s:shop/api"])
  const filtered = M.buildRows(projects, { showStopped: false, query: "WEB" })
  assert.deepEqual(filtered.map(r => r.key), ["p:idle", "s:idle/web"])
  const ports = JSON.parse(open[1].portsJson)
  assert.equal(ports[0].url, "http://127.0.0.1:8081")
})

test("buildRows signature changes only when content changes", () => {
  const projects = M.groupProjects(M.parseContainers(line({})))
  const a = M.buildRows(projects, { showStopped: true, expanded: { shop: true } })
  const b = M.buildRows(projects, { showStopped: true, expanded: { shop: true } })
  assert.equal(a[1].sig, b[1].sig)
  const c = M.buildRows(projects, { showStopped: true, expanded: { shop: true }, probes: { "http://127.0.0.1:8081": "http:200" } })
  assert.notEqual(a[1].sig, c[1].sig)
})

test("classifyError recognises daemon and permission problems", () => {
  assert.equal(M.classifyError("Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"), "daemon")
  assert.equal(M.classifyError("permission denied while trying to connect"), "permission")
  assert.equal(M.classifyError("boom"), "generic")
  assert.equal(M.classifyError(""), "")
})

test("browseUrl normalises wildcard and IPv6 hosts", () => {
  assert.equal(M.browseUrl({ host: "0.0.0.0", hostPort: 80 }), "http://127.0.0.1:80")
  assert.equal(M.browseUrl({ host: "::", hostPort: 8443 }), "https://[::1]:8443")
  assert.equal(M.browseUrl({ host: "::1", hostPort: 9 }), "http://[::1]:9")
  assert.equal(M.addressFor("http://127.0.0.1:80"), "127.0.0.1:80")
})

test("probe parsing and labels", () => {
  const p = M.parseProbes([
    "http://127.0.0.1:8081\t200\t0",
    "http://127.0.0.1:3307\t000\t1",
    "http://127.0.0.1:9\t000\t7",
    "http://127.0.0.1:5489\t401\t0",
    "http://127.0.0.1:8082\t404\t0",
    "<img src=x>\t200\t0"
  ].join("\n"))
  assert.deepEqual(p, {
    "http://127.0.0.1:8081": "http:200",
    "http://127.0.0.1:3307": "tcp",
    "http://127.0.0.1:9": "down",
    "http://127.0.0.1:5489": "http:401",
    "http://127.0.0.1:8082": "http:404"
  })
  assert.deepEqual(M.probeLabel("http:401"), { key: "probe.auth", code: 401 })
  assert.deepEqual(M.probeLabel("http:404"), { key: "probe.api", code: 404 })
  assert.deepEqual(M.probeLabel("tcp"), { key: "probe.tcp", code: 0 })
  assert.equal(M.probeTone("http:200"), "ok")
  assert.equal(M.probeTone("http:500"), "warn")
  assert.equal(M.probeTone("down"), "down")
  assert.equal(M.probeIsHttp("tcp"), false)
})

test("probeArgs passes URLs as argv only and probes running tcp ports", () => {
  const projects = M.groupProjects(M.parseContainers([
    line({}),
    line({ project: "idle", service: "web", id: "e".repeat(64), state: "exited", ports: "0.0.0.0:9999->80/tcp" })
  ].join("\n")))
  const urls = M.probeUrls(projects)
  assert.deepEqual(urls, ["http://127.0.0.1:8081"])
  const argv = M.probeArgs(urls)
  assert.equal(argv[0], "sh")
  assert.ok(!argv[2].includes("127.0.0.1"))
  assert.equal(argv[argv.length - 1], "http://127.0.0.1:8081")
})

test("composeArgs: all profiles + orphans for down/restart, default profile for up", () => {
  const project = { name: "shop", workingDir: "/w/k", configFiles: ["/w/k/compose.yml", "/w/k/override.yml"] }
  assert.deepEqual(M.composeArgs(project, "up"), ["docker", "compose", "-p", "shop", "--project-directory", "/w/k", "-f", "/w/k/compose.yml", "-f", "/w/k/override.yml", "up", "-d"])
  assert.deepEqual(M.composeArgs(project, "down").slice(-4), ["--profile", "*", "down", "--remove-orphans"])
  assert.deepEqual(M.composeArgs(project, "restart").slice(-3), ["--profile", "*", "restart"])
  assert.equal(M.composeArgs(project, "rm"), null)
  assert.equal(M.composeArgs(project, "start"), null)
  assert.equal(M.composeArgs({ name: "shop", configFiles: ["relative.yml"] }, "up"), null)
  assert.equal(M.composeArgs({ name: "shop", configFiles: [] }, "up"), null)
})

test("service actions act on the container (works for profiles and orphans)", () => {
  const id = "a".repeat(64)
  assert.deepEqual(M.serviceArgs(id, "stop"), ["docker", "stop", id])
  assert.deepEqual(M.serviceArgs(id, "restart"), ["docker", "restart", id])
  assert.equal(M.serviceArgs(id, "down"), null)
  assert.equal(M.serviceArgs("nope; rm -rf ~", "stop"), null)
  const projects = M.groupProjects(M.parseContainers(line({})))
  assert.equal(M.findService(projects, "shop", "api").containerId, "49f2a52e9bbd006a94cd5a880698c25d976ca68fd4359967f6bf4bc38fd9d3ab")
  assert.equal(M.findService(projects, "shop", "missing"), null)
})

test("logs argv are bounded and validated", () => {
  assert.deepEqual(M.logsArgs("a".repeat(64), 5), ["docker", "logs", "--tail", "10", "-f", "a".repeat(64)])
  assert.equal(M.logsArgs("nope", 100), null)
  assert.deepEqual(M.terminalLogsArgs("b".repeat(64)), ["xdg-terminal-exec", "docker", "logs", "-f", "--tail", "200", "b".repeat(64)])
  assert.equal(M.terminalLogsArgs("x y"), null)
})

test("cleanMessage keeps the last meaningful stderr lines, bounded", () => {
  assert.equal(M.cleanMessage("\n a \n\n b \n c \n d \n"), "b · c · d")
  assert.ok(M.cleanMessage("x".repeat(2000)).length <= 512)
  assert.equal(M.shortPath("/home/u/proj", "/home/u"), "~/proj")
})

test("language: override, Omarchy language and English fallback", () => {
  assert.equal(M.languageFor("auto", "es-CO"), "es")
  assert.equal(M.languageFor("auto", "en-US"), "en")
  assert.equal(M.languageFor("auto", "da"), "en")
  assert.equal(M.languageFor("es", "en-US"), "es")
  assert.equal(M.languageFor("fr", "es"), "es")
  assert.equal(M.languageFor("", ""), "en")
})

test("pluralPick and catalogs: one/other and same keys in en and es", () => {
  assert.equal(M.pluralPick({ one: "%1 service", other: "%1 services" }, 1), "%1 service")
  assert.equal(M.pluralPick({ one: "%1 service", other: "%1 services" }, 3), "%1 services")
  assert.equal(M.pluralPick({ one: "a", other: "b" }, -1), "b")
  assert.equal(M.pluralPick("plain", 1), "plain")
  assert.equal(M.pluralPick(undefined, 1), "")
  const en = JSON.parse(readFileSync(new URL("../i18n/en.json", import.meta.url)))
  const es = JSON.parse(readFileSync(new URL("../i18n/es.json", import.meta.url)))
  assert.deepEqual(Object.keys(en).sort(), Object.keys(es).sort())
})
