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
| ID `io.github.jeanpidev.omapose`; repo `github.com/Jxanpi/omapose`. | Third-party no puede usar `omarchy.*`; sin symlinks. |
| Validación: `omarchy plugin validate`, `qmllint -I "$OMARCHY_PATH/shell"`; probar click, Esc, summon/hide, disable/enable, restart, remove en Shibumi y barra nativa. | Checklist de la guía. |

## Fase 0 (plan): decisiones con alternativas

| Decisión | Por qué | Alternativas descartadas |
|---|---|---|
| Fuente única `docker ps -a --filter label=com.docker.compose.project` con plantilla JSON por etiqueta (`{{json (.Label "…")}}`). | 1 proceso por refresco (SC-001); incluye working_dir y config_files para `up` tras `down`. `Labels` crudo separa por `,` y `config_files` puede contener `,`. | `docker compose ls` + `ps` por proyecto (N+1 procesos); parsear `.Labels`. |
| Refresco por `docker events` (filtro compose) + respaldo `idleRefreshSec` (60 s). | CPU en reposo ~0 (SC-005) y cambios al instante. | Timer de 5 s como omaports/Dockarchy. |
| Acciones con `docker compose -p … --project-directory … -f …` (de las etiquetas). | Funciona con proyecto bajado y con overrides. | `docker compose` con `cwd` (no admite `-f` múltiples ambiguos); `docker start/stop` (no cubre `up`/`down`). |
| Logs en panel con `docker logs --tail N -f <id>`; terminal con `xdg-terminal-exec docker logs -f <id>`. | Un solo contenedor por servicio en v1; terminal por defecto de Omarchy. | `docker compose logs` en panel (mezcla servicios). |
| Ajustes y «Acerca de» como vista propia del panel; `homepage` en manifiesto. | `schema` solo admite `string`/`integer`/`enum`/`boolean`/`path`. | Solo `schema` (no hay tipo link). |
| `ListModel` sincronizado por clave (`project/service`), una sola reconstrucción por ciclo. | Lección de omaports: dos rebuilds por refresco y arreglos nuevos reiniciaban el scroll. | Reasignar arreglos derivados. |
| Desarrollo con `scripts/dev-sync.sh` (rsync + `omarchy restart shell`). | Carpetas de plugin no admiten symlinks; la recarga en caliente no reinstancia de forma fiable. | Symlink al repo; editar en `~/.config`. |
| Acciones de servicio por contenedor (`docker start|stop|restart <id>`); `down`/`restart` de proyecto con `--profile "*"` y `down --remove-orphans`; `up` sin perfiles extra. | En el proyecto real, compose respondía «no such service» para servicios en `profiles:` y para huérfanos (contenedores de servicios que ya no están en el archivo). | Acciones de servicio con `docker compose … <service>`; `up` con todos los perfiles (arrancaría servicios de test). |
| Sondeo HTTP al abrir el panel, cada 60 s con el panel abierto y al aparecer un puerto nuevo. | Cada sondeo es un `GET /` que aparece en el log de acceso de la app. | Cada 10 s (llenaba los logs de ruido). |
| Sin heurística «init terminado» (`Exited (0)`): cualquier servicio detenido deja el proyecto en `partial`, con `n/m` visible. | `docker stop` también sale con 0 y los contenedores detenidos no reportan puertos: no se distinguen. | Contar `Exited (0)` como completado. |
| Atajos: `→`/`l` abre (logs o desplegar), `←`/`h` vuelve, `x`/Supr baja o detiene. | `PanelKeyCatcher` reserva h/j/k/l, flechas y x/Supr; no emite `textKey` para ellas. | `l` como atajo de logs. |
| Idioma propio (`Strings.qml`, misma API `t`/`tn`) con ajuste `language` = `auto`/`en`/`es`. | `Commons.Translations` siempre sigue el idioma de Omarchy y no admite forzar otro. | Solo `Commons.Translations`. |
| Etiqueta del id de traducciones distinta de la propiedad (`tr`, no `strings`). | `strings: strings` dentro de un componente se resuelve a sí mismo (binding vacío): se veían claves sin traducir. | — |
| `IpcHandler` en `PluginIpc.qml`, instanciado por `BarWidget`. | `qmllint` (Quattro) termina con código 255 sin mensaje ante cualquier `IpcHandler` con funciones tipadas (también en omaports y rimuru); separado, el paso de la guía `qmllint BarWidget.qml Panel.qml` pasa. Abrir/cerrar los enruta el shell a `BarWidget.open()/close()`. | Dejarlo en `BarWidget.qml` (falla la validación de la guía). |
| Tab / Shift+Tab → panel vecino (`switchPanel`); `/` enfoca el buscador; ↓ desde el buscador entra a la lista. | Convención de todos los paneles nativos y del ejemplo de `develop.html`. | Tab para alternar buscador/lista. |
| RAM total con `docker stats --no-stream` sobre los contenedores en marcha, solo con el panel abierto y cada 10 s. | `docker stats` muestrea ~1–2 s; en segundo plano no bloquea la lista ni gasta CPU con el panel cerrado. | `docker stats` en streaming permanente (proceso extra siempre vivo). |
| Nombre «Omapose» (ID `io.github.jeanpidev.omapose`). | «Omacompose» ya existe en el marketplace (otro uso: tecla Compose de X); «Compose» a secas se confundía. Sigue la convención `oma*`. | Compose, Compachy, Dockside, Berth, Convoy. |
| Motor fijado: endpoint del contexto + ID del motor resueltos por refresco; `-H <endpoint>` en todos los comandos; acciones con guarda que re-comprueba el ID; `Down` confirma sobre una copia (proyecto + motor) de lo mostrado. | Revisión del marketplace (Medium): si el contexto de Docker cambiaba antes de confirmar, `down` podía actuar sobre otro motor con un proyecto homónimo. Probado: con el contexto cambiado, `Down` actuó sobre el motor mostrado. | Usar el contexto activo al ejecutar; guardar solo el nombre del proyecto. |
| Shell en el contenedor con limpieza por token (`OMAPOSE_SESSION`) al cerrar la terminal (`trap HUP`) o al salir. | Probado: al cerrar la terminal, Docker no termina el proceso `exec` y la shell queda huérfana dentro del contenedor; con el envoltorio queda limpio en ~2 s. | `docker exec -it` directo (deja shells huérfanas). |
| RAM por servicio con el mismo `docker stats` de la cabecera (sin procesos extra), en la línea de estado del servicio. | Coste cero adicional; se actualiza cada 10 s con el panel abierto. | Un `docker stats` por servicio. |
| Motor y proyectos se publican juntos en `finalize()`; cada proyecto lleva el ID de su motor y la foto de una acción solo existe si coinciden (`Model.snapshotFor`); un refresco espera a la comprobación de archivos. | Segunda revisión del marketplace (Medium): el motor nuevo se publicaba antes de que la comprobación asíncrona de recordados reemplazara la lista vieja, y abrir `Down` en ese intervalo mezclaba proyecto viejo y motor nuevo. | Publicar el motor en `handlePs`. |
