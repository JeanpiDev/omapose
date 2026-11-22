# Quickstart (desarrollo y verificación)

```sh
cd ~/Develop/personal/omarchy-compose
node --test tests/                                   # Model.js
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml ComposeStore.qml components/*.qml
scripts/dev-sync.sh                                  # copia a ~/.config/omarchy/plugins/io.github.jeanpidev.omarchy-compose y reinicia el shell
omarchy plugin enable io.github.jeanpidev.omarchy-compose
```

La recarga en caliente no siempre reinstancia widgets: tras cambios de QML usar `omarchy restart shell` (lo hace `dev-sync.sh`).

## Checklist manual (Shibumi y luego `omarchy bar use omarchy.bar`)

1. Click en el icono abre/cierra; `omarchy-shell shell summon|hide <id>` también; Esc cierra.
2. Icono del color de los demás widgets de Shibumi; en barra nativa, color de la barra. `omarchy theme set <otro>` con el panel abierto → colores cambian sin cerrar.
3. Fondo del panel opaco (ventana con texto detrás no se lee).
4. `shop-suite` aparece con 10 servicios; puertos con etiqueta (8081 `HTTP 200`, 3307 `TCP only`).
5. Bajar un proyecto → confirma → queda «detenido» y sigue listado; levantarlo de nuevo.
6. Reiniciar un servicio → fila «ocupado» → vuelve a activo; un error se muestra en la fila.
7. Logs de un servicio (→ sobre el servicio): llegan líneas nuevas; «Abrir en terminal» sigue los logs.
8. Desplazarse y escribir en el buscador durante 30 s: sin saltos ni pérdida de foco.
9. Ajustes → idioma (Automático/English/Español) cambia los textos al instante; «Acerca de»: versión, nota de privacidad, link abre el repo.
10. Docker detenido (`sudo systemctl stop docker`) → mensaje claro; al arrancar se recupera.
11. Desactivar, reactivar, reiniciar shell y desinstalar: sin procesos `docker events` huérfanos (`ps -eo args | grep -c '^/usr/bin/docker events'`). Tras reactivar sin reiniciar, el shell puede no remontar el widget (también pasa con otros plugins): `omarchy restart shell`.

Atajos: `PanelKeyCatcher` reserva h/j/k/l, flechas y x/Supr → `→`/`l` abre (logs o desplegar), `←`/`h` vuelve, `x` baja/detiene.
