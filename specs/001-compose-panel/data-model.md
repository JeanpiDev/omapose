# Data Model

## Project

| Campo | Tipo | Origen / regla |
|---|---|---|
| `name` | string | etiqueta `com.docker.compose.project`; clave única |
| `workingDir` | string | `com.docker.compose.project.working_dir` |
| `configFiles` | string[] | `com.docker.compose.project.config_files` (separado por `,`) |
| `services` | Service[] | contenedores con el mismo `name`, `oneoff=False` |
| `state` | enum | derivado: `running` (todos activos), `partial`, `stopped`, `unhealthy` (algún servicio con salud `unhealthy`), `missing` (recordado y `configFiles` no existen) |
| `remembered` | bool | presente en `projects.json` |
| `busy` | Action\|null | acción en curso sobre el proyecto |

Validación: `name` ≤ 128 chars `[a-z0-9_-]` (regla de compose); rutas absolutas ≤ 4096; máximo 64 proyectos, 256 contenedores.

## Service

| Campo | Tipo | Origen / regla |
|---|---|---|
| `project` | string | FK → Project.name |
| `name` | string | `com.docker.compose.service` |
| `containerId` | string | `.ID` (12+ hex) |
| `state` | enum | `.State`: `running`, `exited`, `restarting`, `paused`, `created`, `dead` |
| `health` | enum | `.Status` → `healthy`, `unhealthy`, `starting`, `""` |
| `status` | string | `.Status` literal (texto plano, ≤ 128) |
| `ports` | Port[] | `.Ports` (solo publicados en host) |
| `busy` | Action\|null | |

## Port

| Campo | Tipo | Regla |
|---|---|---|
| `host` | string | IP de host (`0.0.0.0`/`::` → `127.0.0.1`/`[::1]` para abrir) |
| `hostPort` | int | 1–65535 |
| `containerPort` | int | |
| `proto` | `tcp`\|`udp` | solo `tcp` se sondea |
| `probe` | string | `http:<código>` \| `tcp` \| `down` \| `""` (sin sondear) — mismo contrato que el parche de omaports |

## Action

| Campo | Tipo | Regla |
|---|---|---|
| `target` | `project`\|`service` | |
| `kind` | enum | proyecto: `up`, `down`(confirmación), `restart`; servicio: `start`, `stop`, `restart` |
| `status` | `running`\|`ok`\|`error` | una acción a la vez por objetivo (FR US2-2) |
| `message` | string | stderr acotado a 512 chars, texto plano |

Transición: `idle → running → ok|error → idle` (error visible hasta la siguiente acción o 8 s).

## RememberedProjects (`projects.json`)

```json
{ "version": 1, "projects": { "<name>": { "workingDir": "/abs", "configFiles": ["/abs/compose.yml"], "lastSeen": "2026-11-22T13:00:00Z" } } }
```

Se añade/actualiza cada vez que el proyecto aparece en `docker ps`; «Olvidar» lo elimina. Lectura tolerante: JSON inválido → se renombra a `.corrupt-<ts>` y se empieza vacío.
