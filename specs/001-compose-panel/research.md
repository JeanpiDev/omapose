# Research: restricciones de plataforma (insumo para /speckit-plan)

Fuentes: https://plugins.omarchy.org/develop.html, `/usr/share/omarchy/shell`, plugins instalados (2026-11-22).

| Decisión | Por qué |
|---|---|
| `kinds: ["bar-widget"]`; `BarWidget.qml` carga `Panel.qml` con `Loader` (patrón del tutorial oficial y de `omarchy.clock`). Sin kind `panel` aparte. | Contrato de Quattro; open/close/toggle/closeForPopoutSwitch enrutan click y `summon`/`hide`. |
| Click con `WidgetButton { onPressed }`; nunca solo `triggerPress()`. | Shibumi no llama `triggerPress` (Port Watch quedó sin click). |
| Lógica de datos dentro del propio widget/panel (como OmaWarden: `property alias service`), no `bar.shell.serviceFor(...)`. | Shibumi inyecta su propio `bar` (`WidgetSlot.qml:668`); `serviceFor` solo resuelve el plugin que llama (`shell.qml: pluginOwnsTarget`) → devuelve `null` (Screen Time queda en 0m). |
| Color del icono en barra: si `bar.visualTokens.widgetContentColor` existe (Shibumi) → `bar.visualTokens.widgetContentColor(settings, bar.urgent)`; si no (barra nativa) → `bar.barForeground`. Estado activo: `Color.accent`. Panel: tokens `qs.Commons` (`Color.popups.*`, `Style.*`). Sin colores fijos. | En Shibumi `barForeground` = `tokens.ink` (blanco); sus widgets usan `widgetInk` = `widgetContentColor(...)` (sello/rojo o el color configurado). Verificado parcheando omaports: el icono pasó de blanco a rojo. |
| `KeyboardPanel` + `PanelKeyCatcher`, contenido en `Flickable`/`ListView` con indicador de scroll. | Fondo opaco, Esc, anclaje y animación del kit; omaports corta la lista sin indicador. |
| Modelo con actualización incremental (`ListModel` con `set`/`move` por clave), no reasignar arreglos derivados. | omaports recalcula `rows` en cada refresco → el `ListView` pierde scroll y foco. |
| Todo `Text` con `textFormat: Text.PlainText`; límites de tamaño a salida de `docker`. | Guía *Plugin UI Safety*. |
| Duraciones con `Style.duration(ms)`, `Style.easeOut`, ≤300 ms. | Guía *Plugin Motion*. |
| `i18n/en.json` + `i18n/es.json` vía `Commons.Translations`. | Guía *Translations*. |
| Procesos con `Process` acotado, nunca interpolar valores en `bash -c` (fuente de datos: ver Fase 0). | Sin dependencias extra; seguro. |
| Referencia Shibumi validada: `io.github.iammhador.claude-pulse` (solo `bar-widget`, datos dentro del widget, `WidgetButton.onPressed`, `PlainText` en todo). Su color no sigue a Shibumi (usa `barForeground`); ver regla de color. | Click y datos funcionan en la barra Shibumi del usuario. |
| About en ajustes: tarjeta con nombre · versión, nota de privacidad y enlace al repo (`Qt.openUrlExternally`); `"homepage"` en `manifest.json`. | Patrón de `rimuru.screentime` (`SettingsView.qml`, sección About). |
| ID `io.github.jeanpidev.omarchy-compose`; repo `github.com/JeanpiDev/omarchy-compose`. | Third-party no puede usar `omarchy.*`; sin symlinks. |
| Validación: `omarchy plugin validate`, `qmllint -I "$OMARCHY_PATH/shell"`; probar click, Esc, summon/hide, disable/enable, restart, remove en Shibumi y barra nativa. | Checklist de la guía. |

## Fase 0 (plan): decisiones con alternativas

| Decisión | Por qué | Alternativas descartadas |
|---|---|---|
| Fuente única `docker ps -a --filter label=com.docker.compose.project` con plantilla JSON por etiqueta (`{{json (.Label "…")}}`). | 1 proceso por refresco (SC-001); incluye working_dir y config_files para `up` tras `down`. `Labels` crudo separa por `,` y `config_files` puede contener `,`. | `docker compose ls` + `ps` por proyecto (N+1 procesos); parsear `.Labels`. |
| Refresco por `docker events` (filtro compose) + respaldo `idleRefreshSec` (60 s). | CPU en reposo ~0 (SC-005) y cambios al instante. | Timer de 5 s como omaports/Dockarchy. |
| Acciones con `docker compose -p … --project-directory … -f …` (de las etiquetas). | Funciona con proyecto bajado y con overrides. | `docker compose` con `cwd` (no admite `-f` múltiples ambiguos); `docker start/stop` (no cubre `up`/`down`). |
| Logs en panel con `docker logs --tail N -f <id>`; terminal con `xdg-terminal-exec docker compose … logs -f`. | Un solo contenedor por servicio en v1; terminal por defecto de Omarchy. | `docker compose logs` en panel (mezcla servicios). |
| Ajustes y «Acerca de» como vista propia del panel; `homepage` en manifiesto. | `schema` solo admite `string`/`integer`/`enum`/`boolean`/`path`. | Solo `schema` (no hay tipo link). |
| `ListModel` sincronizado por clave (`project/service`), una sola reconstrucción por ciclo. | Lección de omaports: dos rebuilds por refresco y arreglos nuevos reiniciaban el scroll. | Reasignar arreglos derivados. |
| Desarrollo con `scripts/dev-sync.sh` (rsync + `omarchy restart shell`). | Carpetas de plugin no admiten symlinks; la recarga en caliente no reinstancia de forma fiable. | Symlink al repo; editar en `~/.config`. |
