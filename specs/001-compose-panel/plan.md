# Implementation Plan: Panel de proyectos Docker Compose

**Branch**: `001-compose-panel` | **Date**: 2026-11-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-compose-panel/spec.md`

## Summary

Plugin `bar-widget` de Omarchy Quattro (`io.github.jeanpidev.omapose`) que lista los proyectos docker compose con sus servicios, estado, salud y puertos (con sondeo HTTP), y permite levantar/bajar/reiniciar proyectos y servicios y ver logs desde un `KeyboardPanel`. Datos con un único `docker ps -a` filtrado por etiquetas compose, refresco disparado por `docker events` (sin sondeo continuo), proyectos recordados en un archivo de estado, y estilo 100 % de tokens del tema/barra con la regla de color de Shibumi.

## Technical Context

**Language/Version**: QML (Qt 6, Quickshell del shell Omarchy Quattro) + JavaScript ES5 compatible con QML (`Model.js`, sin APIs de Qt para poder testearlo en node).

**Primary Dependencies**: kit del shell `qs.Ui` (`BarWidget`, `WidgetButton`, `Panel`, `KeyboardPanel`, `PanelKeyCatcher`, `PanelHero`, `ConfirmDialog`, `TextField`), `qs.Commons` (`Color`, `Style`, `Translations`, `I18n`), `Quickshell.Io` (`Process`, `StdioCollector`, `FileView`, `IpcHandler`). Externas: `docker` + `docker compose` v2 (5.6.1 instalado), `curl`, `xdg-terminal-exec`.

**Storage**: `~/.local/state/omarchy/omapose/projects.json` (proyectos recordados). Ajustes en `shell.json` vía `barWidget.schema` del manifiesto.

**Testing**: `node --test tests/` sobre `Model.js` (parsers, agregados, sondeo, merge de recordados, texto con marcado); `omarchy plugin validate`; `qmllint -I /usr/share/omarchy/shell`; checklist manual en `quickstart.md` (Shibumi y barra nativa).

**Target Platform**: Omarchy Quattro (Arch Linux, Hyprland), barra Shibumi (`hancore.shibumi.bar`) y barra nativa `omarchy.bar`.

**Project Type**: plugin de escritorio (repositorio instalable con `omarchy plugin add <git-url>`).

**Performance Goals**: panel con estado en < 1 s con 10 proyectos / 30 servicios (SC-001); 1 proceso `docker ps` por refresco.

**Constraints**: CPU en reposo < 1 % (SC-005): sin timers rápidos con el panel cerrado; procesos con salida acotada; nunca interpolar valores en `sh -c`; todo `Text` en `PlainText`; sin red externa.

**Scale/Scope**: ~10 proyectos, ~30 servicios, ~20 puertos publicados.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` sin ratificar (plantilla). Gates aplicados = restricciones de plataforma de `research.md`:

| Gate | Estado |
|---|---|
| Contrato Quattro (bar-widget + Panel por Loader, open/close/toggle/closeForPopoutSwitch) | ✅ diseño |
| Click con `WidgetButton.onPressed`, sin depender de `triggerPress` | ✅ |
| Sin `bar.shell.serviceFor` (Shibumi): store instanciado dentro del widget | ✅ |
| Color: `widgetContentColor` en Shibumi / `barForeground` nativa; panel con tokens | ✅ |
| UI Safety: `PlainText`, salida acotada, argv sin interpolación | ✅ |
| Motion `Style.duration`, i18n `en`/`es` | ✅ |

Re-check post-diseño: sin violaciones; Complexity Tracking vacío.

## Project Structure

### Documentation (this feature)

```text
specs/001-compose-panel/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/interfaces.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
manifest.json             # id io.github.jeanpidev.omapose, kinds [bar-widget], homepage, schema
BarWidget.qml             # WidgetButton + contador + color Shibumi; crea ComposeStore; Loader de Panel; IpcHandler
Panel.qml                 # Panel + KeyboardPanel + PanelKeyCatcher; vistas: lista | logs | ajustes
ComposeStore.qml          # Process docker ps / events / acciones / sondeo; FileView de recordados; ListModel incremental
Strings.qml               # catálogo i18n propio con ajuste de idioma (auto/en/es)
PluginIpc.qml             # IpcHandler (refresh/status/forget) aparte: qmllint falla con IpcHandler tipado
Model.js                  # lógica pura (parse, agregados, merge, sondeo, etiquetas) — testeable en node
components/
├── ProjectRow.qml        # cabecera de proyecto (estado agregado, acciones, desplegar)
├── ServiceRow.qml        # servicio: estado/salud, acciones, puertos
├── PortChip.qml          # puerto + etiqueta HTTP/TCP + abrir/copiar
├── LogView.qml           # últimas N líneas en vivo + abrir en terminal
└── SettingsView.qml      # ajustes + tarjeta «Acerca de» (versión, privacidad, repo)
i18n/en.json, i18n/es.json
tests/model.test.mjs
scripts/dev-sync.sh       # copia el repo al directorio de plugins (sin symlinks) y reinicia el shell
README.md, LICENSE (MIT), preview.png
```

**Structure Decision**: repositorio con el plugin en la raíz (layout instalable por `omarchy plugin add`). Toda la lógica no visual en `Model.js` para testearla sin Qt; `ComposeStore.qml` es la única capa que ejecuta procesos.

## Complexity Tracking

Sin violaciones.
