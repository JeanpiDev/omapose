# Feature Specification: Panel de proyectos Docker Compose

**Feature Branch**: `001-compose-panel`

**Created**: 2026-11-22

**Status**: Draft

**Input**: User description: "Plugin de Omarchy para gestionar proyectos docker compose desde la barra, como un modal sin abrir una app (alternativa a lazydocker/Docker Desktop). Por proyecto: estado, levantar, bajar, reiniciar y logs por servicio. Debe seguir el tema de Omarchy (los colores cambian con el tema) y funcionar con la barra Shibumi. Mejora de Dockarchy, solo Docker local."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver el estado de mis proyectos de un vistazo (Priority: P1)

Desde la barra veo cuántos servicios tengo en marcha; al hacer click se abre un panel con cada proyecto compose (nombre, carpeta, estado agregado) y, al desplegarlo, sus servicios con estado y puertos publicados.

**Why this priority**: Es el reemplazo directo de abrir lazydocker solo para mirar; sin esto el resto no tiene sentido.

**Independent Test**: Con un proyecto en marcha y otro detenido, abrir el panel y comprobar que ambos aparecen con el estado y los puertos correctos.

**Acceptance Scenarios**:

1. **Given** `shop-suite` en marcha con 10 servicios, **When** miro la barra, **Then** el indicador muestra el número de servicios en marcha.
2. **Given** el panel cerrado, **When** hago click en el icono de la barra (Shibumi u Omarchy), **Then** el panel se abre junto al icono.
3. **Given** un proyecto desplegado, **When** un servicio publica el puerto 8081, **Then** veo `8081` y puedo abrirlo en el navegador con un click.

---

### User Story 2 - Controlar proyectos y servicios (Priority: P2)

Puedo levantar, bajar y reiniciar un proyecto completo, e iniciar, detener o reiniciar un servicio concreto, sin salir del panel.

**Why this priority**: Convierte el panel de un monitor en una herramienta; es lo que hoy obliga a abrir una terminal.

**Independent Test**: Bajar un proyecto, confirmar que sigue listado como detenido, y volver a levantarlo desde el panel.

**Acceptance Scenarios**:

1. **Given** un proyecto en marcha, **When** pulso «Bajar», **Then** se pide confirmación y, tras confirmar, el proyecto queda detenido y sigue en la lista.
2. **Given** una acción en curso, **When** espero, **Then** la fila muestra estado «ocupado» y no admite otra acción hasta terminar.
3. **Given** una acción que falla, **When** termina, **Then** veo el error legible en la fila, sin cerrar el panel.

---

### User Story 3 - Ver los logs de un servicio (Priority: P3)

Desde un servicio abro sus últimas líneas de log dentro del panel, siguiéndolas en vivo, con opción de abrirlas en la terminal.

**Why this priority**: Útil para diagnosticar rápido, pero se puede cubrir con la terminal mientras tanto.

**Independent Test**: Abrir los logs de un servicio activo y ver aparecer líneas nuevas.

**Acceptance Scenarios**:

1. **Given** un servicio activo, **When** abro sus logs, **Then** veo las últimas 200 líneas y las nuevas se añaden al final.
2. **Given** los logs abiertos, **When** pulso «Abrir en terminal», **Then** se abre la terminal por defecto siguiendo esos logs.

---

### Edge Cases

- El daemon de Docker no corre o el usuario no tiene permiso: el panel lo dice con la acción para resolverlo, sin errores en cadena.
- No hay ningún proyecto: estado vacío con una explicación breve.
- La carpeta o el `compose.yml` de un proyecto recordado ya no existe: se marca como no disponible y se puede olvidar.
- Proyecto con muchos servicios o muchos proyectos: la lista se desplaza con un indicador visible y nada se corta.
- Nombres, logs o salidas con texto con forma de marcado: se muestran como texto plano.
- Cambio de tema con el panel abierto: los colores se actualizan sin cerrarlo.
- Llega un refresco mientras me desplazo o escribo en el buscador: la vista no salta ni pierde el foco.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema MUST listar todos los proyectos compose que Docker conoce (en marcha y detenidos) con nombre, carpeta y estado agregado.
- **FR-002**: El sistema MUST recordar los proyectos vistos para que un proyecto bajado (sin contenedores) siga listado y se pueda volver a levantar.
- **FR-003**: Por cada servicio MUST mostrar estado (en marcha, detenido, reiniciando, con fallo de salud) y puertos publicados.
- **FR-003a**: Cada puerto publicado MUST indicar si responde por HTTP (código, p. ej. 200, o 401/404 como «API»), si solo acepta TCP (p. ej. base de datos) o si no responde; «Abrir en el navegador» solo se ofrece cuando responde por HTTP. La comprobación es local y con tiempo límite corto.
- **FR-004**: Users MUST be able to levantar, bajar y reiniciar un proyecto, e iniciar, detener y reiniciar un servicio; bajar requiere confirmación.
- **FR-005**: El sistema MUST mostrar las últimas líneas de log de un servicio, en vivo, y ofrecer abrirlas en la terminal.
- **FR-006**: El indicador de la barra MUST mostrar los servicios en marcha y funcionar igual (click, datos, apertura del panel) tanto en la barra Shibumi como en la nativa.
- **FR-007**: El icono y el texto de la barra MUST tomar el color de primer plano de la barra que lo aloja (p. ej. el acento de Shibumi), y el panel los colores del tema activo; todo se actualiza en vivo al cambiar tema o estilo de barra. El fondo del panel MUST ser opaco (sin texto de ventanas detrás).
- **FR-012**: Los refrescos automáticos MUST conservar la posición del scroll, el elemento seleccionado, el foco y el texto del buscador; solo cambian las filas afectadas.
- **FR-015**: La cabecera del panel MUST mostrar, bajo el número de contenedores en marcha, la CPU de Docker (% del sistema) y su RAM (uso, % y total del equipo).
- **FR-014**: Los ajustes del plugin MUST incluir una sección «Acerca de» con nombre, versión, una nota de privacidad (solo Docker local, nada sale del equipo) y el enlace al repositorio, que se abre en el navegador.
- **FR-013**: El plugin MUST abrirse y cerrarse también por comando del shell (`summon`/`hide`) y sobrevivir a desactivar, reactivar, reiniciar el shell y desinstalar sin dejar procesos.
- **FR-008**: El panel MUST manejarse completo con teclado (navegar, desplegar, acciones, cerrar con Esc).
- **FR-009**: El estado MUST refrescarse solo mientras el panel está abierto y con un intervalo configurable en reposo.
- **FR-010**: Los textos MUST estar en español e inglés; por defecto siguen el idioma de Omarchy y el usuario MUST poder fijar uno en los ajustes.
- **FR-011**: El sistema MUST operar solo sobre el Docker local, sin acceso a red externa.

### Key Entities

- **Proyecto**: nombre compose, archivos de configuración, carpeta, estado agregado, recordado sí/no.
- **Servicio**: nombre, proyecto, estado, salud, puertos publicados, contenedor.
- **Acción**: objetivo (proyecto o servicio), tipo, estado (en curso, ok, error) y mensaje.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: El panel abre y muestra el estado en menos de 1 s con 10 proyectos y 30 servicios.
- **SC-002**: Levantar, bajar o reiniciar un proyecto requiere como máximo 2 clicks (3 con confirmación).
- **SC-003**: Tras `omarchy theme set`, el 100 % de los colores del plugin coincide con el nuevo tema sin reiniciar el shell.
- **SC-004**: El click en la barra abre el panel en el 100 % de los intentos con Shibumi y con la barra nativa.
- **SC-005**: En reposo (panel cerrado) el plugin no supera el 1 % de CPU.

## Assumptions

- Docker y el plugin `docker compose` v2 están instalados y el usuario está en el grupo `docker`.
- Hosts remotos por SSH, Podman, Kubernetes y edición del `compose.yml` quedan fuera de la v1.
- Construir imágenes (`build`) y `pull` quedan fuera; `up` usa las imágenes existentes.
- La terminal por defecto de Omarchy es la que abre los logs.
