# Contracts

## Manifest (`manifest.json`)

```json
{
  "schemaVersion": 1,
  "id": "io.github.jeanpidev.omarchy-compose",
  "name": "Compose",
  "version": "0.1.0",
  "author": "JeanpiDev",
  "license": "MIT",
  "homepage": "https://github.com/JeanpiDev/omarchy-compose",
  "description": "Docker Compose projects in the Omarchy bar: status, up/down/restart, ports and logs.",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "Compose",
    "category": "Developer Tools",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": { "idleRefreshSec": 60, "logLines": 200, "probePorts": true, "showStopped": true },
    "schema": [
      { "key": "idleRefreshSec", "type": "integer", "label": "Fallback refresh (seconds)", "min": 15, "max": 3600, "step": 15, "defaultValue": 60 },
      { "key": "logLines", "type": "integer", "label": "Log lines", "min": 50, "max": 2000, "step": 50, "defaultValue": 200 },
      { "key": "probePorts", "type": "boolean", "label": "Check whether ports answer HTTP", "defaultValue": true },
      { "key": "showStopped", "type": "boolean", "label": "Show stopped projects", "defaultValue": true }
    ]
  }
}
```

## IPC (`IpcHandler target: "io.github.jeanpidev.omarchy-compose"`)

| Función | Efecto |
|---|---|
| `open()` / `close()` / `toggle()` | panel (también vía `omarchy-shell shell summon|hide <id>`) |
| `refresh()` | fuerza lectura de `docker ps` |
| `status(): string` | JSON corto `{projects, running, error}` para diagnóstico |

## Comandos externos (siempre argv, nunca `sh -c` con valores interpolados)

| Uso | argv |
|---|---|
| Listado | `docker ps -a --no-trunc --filter label=com.docker.compose.project --format <tpl>` con `tpl` = objeto JSON por línea usando `{{json .ID}}`, `{{json (.Label "com.docker.compose.project")}}`, `…service`, `…project.working_dir`, `…project.config_files`, `…oneoff`, `{{json .State}}`, `{{json .Status}}`, `{{json .Ports}}` |
| Cambios | `docker events --filter type=container --filter label=com.docker.compose.project --format {{json .}}` (proceso largo; reinicio con backoff 2→60 s) |
| Proyecto | `docker compose -p <name> --project-directory <dir> -f <f1> [-f <fN>] up -d` · `… down` · `… restart` |
| Servicio | `docker compose -p <name> --project-directory <dir> -f … start|stop|restart <service>` |
| Logs (panel) | `docker logs --tail <N> -f <containerId>` (salida acotada a N líneas en memoria) |
| Logs (terminal) | `xdg-terminal-exec docker compose -p <name> --project-directory <dir> -f … logs -f <service>` |
| Sondeo | `sh -c '<script fijo>' compose-probe <url>…` (curl `--max-time 1`, ≤ 64 URLs, cada ≥ 10 s, solo con panel abierto) |
| Repo (About) | `Qt.openUrlExternally(manifest.homepage)` |

Salidas de proceso: `head -c 262144` equivalente (descartar el exceso); stderr a `Action.message` (≤ 512).
