---

description: "Task list for 001-compose-panel"
---

# Tasks: Panel de proyectos Docker Compose

**Input**: `/specs/001-compose-panel/` (plan, spec, research, data-model, contracts, quickstart)

**Tests**: `node --test` sobre `Model.js` (definido en plan.md) + checklist manual de quickstart.md.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [ ] T001 Crear `manifest.json` según contracts/interfaces.md (id, homepage, schema, defaults)
- [ ] T002 [P] Añadir `LICENSE` (MIT, JeanpiDev) y `.gitignore`
- [ ] T003 [P] Crear `scripts/dev-sync.sh` (rsync del repo a `~/.config/omarchy/plugins/io.github.jeanpidev.omarchy-compose`, excluye `.git`/`specs`/`.specify`/`.claude`/`tests`, luego `omarchy restart shell`)
- [ ] T004 [P] Crear `i18n/en.json` e `i18n/es.json` con las claves base (título, estados, acciones, errores, vacío)

---

## Phase 2: Foundational (bloquea todas las historias)

- [ ] T005 Implementar en `Model.js` el parser de `docker ps` con plantilla JSON por etiqueta (`parseContainers`, límites 256 filas / 262144 bytes / longitudes) y `dockerPsArgs()`
- [ ] T006 Implementar en `Model.js` `parsePorts` (`.Ports` → Port[] solo publicados, IPv4/IPv6, rangos) y `browseUrl`
- [ ] T007 Implementar en `Model.js` `groupProjects` (Project/Service, estado agregado, salud desde `.Status`) y `mergeRemembered` (recordados → `stopped`/`missing`)
- [ ] T008 [P] Tests en `tests/model.test.mjs` para T005–T007: config_files con comas, IPv6, texto con forma de marcado, entradas truncadas, proyecto recordado sin contenedores
- [ ] T009 Crear `ComposeStore.qml`: `Process` de `docker ps` con una sola reconstrucción por ciclo, `ListModel` de proyectos y servicios sincronizado por clave (`set`/`insert`/`remove`, nunca reasignar), `errorText` (daemon caído / permiso con acción sugerida)
- [ ] T010 En `ComposeStore.qml`: `FileView` de `~/.local/state/omarchy/omarchy-compose/projects.json` (lectura tolerante a JSON corrupto, escritura al ver proyectos, `forget(name)`)
- [ ] T011 En `ComposeStore.qml`: proceso largo `docker events` (filtro compose) → refresco con debounce 300 ms; reinicio con backoff 2→60 s; respaldo `idleRefreshSec`; terminar procesos en `Component.onDestruction`
- [ ] T012 Crear `BarWidget.qml`: `WidgetButton` con `onPressed` (izquierdo: toggle; derecho: refresh), `inkColor` = `widgetContentColor` en Shibumi / `barForeground` nativa, contador de servicios activos, instancia `ComposeStore`, `Loader` de `Panel.qml` con inyección (`bar`, `anchorItem`, `hostWidget`, `store`), `IpcHandler` (open/close/toggle/refresh/status)
- [ ] T013 Crear `Panel.qml`: `Panel` + `KeyboardPanel` + `PanelKeyCatcher` (Esc, Tab entre paneles), `PanelHero`, contenedor de vistas (lista | logs | ajustes), fondo opaco con tokens `Color.popups.*`

**Checkpoint**: widget en la barra con contador y panel vacío que abre/cierra en Shibumi y en barra nativa.

---

## Phase 3: User Story 1 - Ver el estado de mis proyectos (P1) 🎯 MVP

**Goal**: lista de proyectos y servicios con estado, salud y puertos con etiqueta HTTP/TCP.

**Independent Test**: con `shop-suite` activo y otro proyecto detenido, ambos aparecen con estado y puertos correctos (quickstart 1–4, 8).

- [ ] T014 [P] [US1] Añadir a `Model.js` `parseProbes`, `probeLabel`, `probeTone`, `probeIsHttp` (contrato del parche de omaports) + tests en `tests/model.test.mjs`
- [ ] T015 [US1] En `ComposeStore.qml`: sondeo HTTP (`sh -c` con script fijo y URLs por argv, curl 1 s, ≤ 64, cada ≥ 10 s, solo con panel abierto y `probePorts`)
- [ ] T016 [P] [US1] Crear `components/PortChip.qml` (puerto, etiqueta con tono, abrir solo si HTTP, copiar dirección)
- [ ] T017 [P] [US1] Crear `components/ServiceRow.qml` (nombre, estado/salud con color de tema, chips de puertos; todo `PlainText`)
- [ ] T018 [P] [US1] Crear `components/ProjectRow.qml` (nombre, carpeta abreviada, estado agregado, desplegar/plegar)
- [ ] T019 [US1] En `Panel.qml`: `ListView` sobre el `ListModel` con secciones por proyecto, `ScrollIndicator`, buscador que filtra sin perder foco, navegación con teclado (↑/↓/j/k, Enter, Tab), estado vacío y de error; posición y selección preservadas entre refrescos
- [ ] T020 [US1] Respetar `showStopped` y mostrar `missing` con acción «Olvidar»

**Checkpoint**: MVP utilizable solo para mirar (reemplaza abrir lazydocker para consultar).

---

## Phase 4: User Story 2 - Controlar proyectos y servicios (P2)

**Goal**: up/down/restart por proyecto; start/stop/restart por servicio.

**Independent Test**: bajar un proyecto (con confirmación), sigue listado como detenido y se vuelve a levantar (quickstart 5–6).

- [ ] T021 [P] [US2] Añadir a `Model.js` `composeArgs(project, verb, service?)` (`-p`, `--project-directory`, `-f` por archivo; valida nombres/rutas) + tests
- [ ] T022 [US2] En `ComposeStore.qml`: cola de acciones (una por objetivo), estado `running|ok|error`, stderr acotado a 512, limpieza del error a los 8 s, refresco al terminar
- [ ] T023 [US2] Botones y atajos de acción en `ProjectRow.qml` y `ServiceRow.qml` (estado «ocupado», deshabilitar durante la acción)
- [ ] T024 [US2] `ConfirmDialog` para «Bajar» en `Panel.qml` (tokens `Color.menu.*`, foco y teclado)

---

## Phase 5: User Story 3 - Ver logs de un servicio (P3)

**Goal**: últimas N líneas en vivo dentro del panel y abrir en terminal.

**Independent Test**: abrir logs de un servicio activo y ver llegar líneas nuevas; «Abrir en terminal» los sigue (quickstart 7).

- [ ] T025 [US3] Crear `components/LogView.qml`: `Process` `docker logs --tail N -f <id>` con búfer circular de `logLines`, `PlainText` monoespaciado, autoscroll que se pausa si el usuario sube, terminar el proceso al salir de la vista
- [ ] T026 [US3] Botón «Abrir en terminal» (`xdg-terminal-exec docker compose … logs -f <service>` por argv) y navegación lista ↔ logs con Esc/Backspace

---

## Phase 6: Polish & cross-cutting

- [ ] T027 [P] Crear `components/SettingsView.qml`: ajustes del `schema` (vía `omarchy bar set`) y tarjeta «Acerca de» (nombre · versión desde manifest, nota de privacidad, enlace a `homepage` con `Qt.openUrlExternally`) — FR-014
- [ ] T028 [P] Completar `i18n/es.json` y plurales (`tn`) para contadores; fechas con `Commons.I18n.formatLocale`
- [ ] T029 [P] Animaciones solo con `Style.duration` / `Style.easeOut` (≤ 300 ms) y revisión de que no haya colores fijos
- [ ] T030 [P] `README.md` (instalación con `omarchy plugin add`, requisitos, privacidad, capturas) y `preview.png`
- [ ] T031 Validar: `node --test tests/`, `omarchy plugin validate .`, `qmllint -I /usr/share/omarchy/shell` sobre todos los QML
- [ ] T032 Ejecutar checklist completo de quickstart.md en Shibumi y en `omarchy.bar`, incluidos cambio de tema, `pgrep -af "docker events"` tras desactivar/desinstalar, y medición de CPU en reposo (SC-005)

---

## Dependencies & Execution Order

- Setup (T001–T004) → Foundational (T005–T013) → US1 (T014–T020) → US2 (T021–T024) → US3 (T025–T026) → Polish (T027–T032).
- Dentro de Foundational: T005–T007 antes de T008 y T009; T009 antes de T010–T011; T012 y T013 después de T009.
- US2 y US3 dependen de US1 (filas y lista); entre sí son independientes.

## Parallel Examples

- Setup: T002, T003, T004 juntos.
- US1: T014, T016, T017, T018 juntos; luego T015 y T019.
- Polish: T027–T030 juntos; T031–T032 al final.

## Implementation Strategy

MVP = Phases 1–3 (mirar estado sin abrir lazydocker), validar con quickstart 1–4 y 8 en Shibumi; después US2, US3 y pulido, validando cada fase antes de la siguiente.
