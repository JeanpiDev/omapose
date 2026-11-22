# Contracts

## Manifest (`manifest.json`)

```json
{
  "schemaVersion": 1,
  "id": "io.github.jeanpidev.omapose",
  "name": "Omapose",
  "version": "0.1.0",
  "author": "JeanpiDev",
  "license": "MIT",
  "homepage": "https://github.com/JeanpiDev/omapose",
  "description": "Docker Compose projects in the Omarchy bar: status, up/down/restart, ports and logs.",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "Omapose",
    "category": "Developer Tools",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": { "idleRefreshSec": 60, "logLines": 200, "probePorts": true, "showStopped": true, "language": "auto" },
    "schema": [
      { "key": "idleRefreshSec", "type": "integer", "label": "Fallback refresh (seconds)", "min": 15, "max": 3600, "step": 15, "defaultValue": 60 },
      { "key": "logLines", "type": "integer", "label": "Log lines", "min": 50, "max": 2000, "step": 50, "defaultValue": 200 },
      { "key": "probePorts", "type": "boolean", "label": "Check whether ports answer HTTP", "defaultValue": true },
      { "key": "showStopped", "type": "boolean", "label": "Show stopped projects", "defaultValue": true },
      { "key": "language", "type": "enum", "label": "Language", "options": ["auto", "en", "es"], "defaultValue": "auto" }
    ]
  }
}
```

## IPC (`PluginIpc.qml`, `IpcHandler target: "io.github.jeanpidev.omapose"`)

| Función | Efecto |
|---|---|
| `open()` / `close()` / `toggle()` | panel (también vía `omarchy-shell shell summon|hide <id>`) |
| `refresh()` | fuerza lectura de `docker ps` |
| `status(): string` | JSON corto `{projects, running, error, events}` para diagnóstico |
| `forget(name: string)` | olvida un proyecto recordado |

## Comandos externos (siempre argv, nunca `sh -c` con valores interpolados)

| Uso | argv |
|---|---|
| Listado | `docker ps -a --no-trunc --filter label=com.docker.compose.project --format <tpl>` con `tpl` = objeto JSON por línea usando `{{json .ID}}`, `{{json (.Label "com.docker.compose.project")}}`, `…service`, `…project.working_dir`, `…project.config_files`, `…oneoff`, `{{json .State}}`, `{{json .Status}}`, `{{json .Ports}}` |
| Cambios | `docker events --filter type=container --filter label=com.docker.compose.project --format {{.Action}}` (solo dispara un refresco con debounce de 300 ms; proceso largo; reinicio con backoff 2→60 s) |
| Proyecto | `docker compose -p <name> --project-directory <dir> -f <f1> [-f <fN>] up -d` · `… --profile "*" down --remove-orphans` · `… --profile "*" restart` (`up` sin perfiles extra) |
| Servicio | `docker start|stop|restart <containerId>` (por contenedor: funciona con servicios en `profiles` y huérfanos, donde compose responde «no such service») |
| Logs (panel) | `docker logs --tail <N> -f <containerId>` (salida acotada a N líneas en memoria) |
| Logs (terminal) | `xdg-terminal-exec docker logs -f --tail 200 <containerId>` |
| Sondeo | `sh -c '<script fijo>' compose-probe <url>…` (curl `--max-time 1`, ≤ 64 URLs; al abrir el panel, cada 60 s con el panel abierto y al aparecer un puerto nuevo) |
| Memoria | `docker stats --no-stream --format {{.ID}}\t{{.MemUsage}} <ids en marcha>` (solo con el panel abierto, cada 10 s; suma del uso) |
| Repo (About) | `Qt.openUrlExternally(manifest.homepage)` |

Salidas de proceso: `head -c 262144` equivalente (descartar el exceso); stderr a `Action.message` (≤ 512).
