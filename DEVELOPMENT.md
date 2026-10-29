# Project Launcher

Selector de proyectos de REAPER. Reemplaza el diálogo nativo *Choose Project*
por una ventana propia con biblioteca, carpetas y etiquetas virtuales, pin,
backups por proyecto y métricas de uso.

## Qué se instala

| Pieza | Ruta |
|---|---|
| App nativa (WKWebView) | `~/Applications/Project Launcher.app` |
| Lanzador (Action List) | `~/Library/Application Support/REAPER/Scripts/Reaset Scripts/Project Launcher.lua` |
| Arranque + métricas | `~/Library/Application Support/REAPER/Scripts/Reaset Scripts/Project Launcher Startup.lua` |
| Gancho de arranque | `~/Library/Application Support/REAPER/Scripts/__startup.lua` (bloque marcado) |
| Biblioteca del launcher | `~/Library/Application Support/Project Launcher/library.json` |
| Horas de uso | `~/Library/Application Support/Project Launcher/usage.json` |

## Cómo funciona

1. REAPER arranca con `loadlastproj=19` (proyecto nuevo, **sin** el diálogo nativo).
2. `Scripts/__startup.lua` carga el bloque de ReaSet Selector.
3. Ese bloque arranca dos cosas:
   - el **tracker**: acumula segundos con REAPER abierto y segundos en grabación
     (`GetPlayState() & 4`), y escribe `usage.json` cada 15 s y al salir;
   - el **selector**: sólo si REAPER quedó sin proyecto. Si abriste un `.rpp`
     desde Finder, no aparece nada.
4. Al elegir un proyecto, la app lo abre con REAPER (`open -a REAPER <rpp>`) y se
   cierra. Si REAPER no estaba corriendo, arranca directamente con ese proyecto.

## A prueba de actualizaciones

- Nada vive dentro de `REAPER.app`: actualizar REAPER no borra nada.
- Los scripts están en el *resource path del usuario*, que REAPER nunca reescribe.
- La ruta se resuelve con `reaper.GetResourcePath()` y `$HOME`, sin versiones fijas.
- El bloque de `__startup.lua` es idempotente: reinstalar no lo duplica.
- La acción se registra con `reaper.AddRemoveReaScript()` (API oficial), no
  editando `reaper-kb.ini` a mano. Si REAPER se actualiza y pierde el registro,
  el propio script lo vuelve a agregar en el siguiente arranque.
- La app se reconstruye con `./build.sh` y no depende de Xcode completo
  (Command Line Tools basta).

## Instalar / revertir

```bash
cd ~/dev/project-launcher
./install.sh            # compila, copia scripts, engancha el arranque
./install.sh --revert   # deja REAPER como estaba (loadlastproj=20, sin bloque ni scripts)
```

Ambos respaldan `REAPER.ini` y `__startup.lua` con marca de tiempo.

## Detalles de uso

- **Biblioteca inicial**: en la primera ejecución se siembra desde la lista de
  recientes de `REAPER.ini`, descartando rutas que ya no existen.
- **Carpetas y etiquetas** son del launcher: no mueven ni renombran `.rpp`.
- **Eliminar proyecto** (inspector) pide confirmación y manda el `.rpp` a la
  Papelera con `FileManager.trashItem`; después lo saca de la biblioteca. Es
  recuperable desde la Papelera.
- **Quitar del launcher** (menú de 3 puntos) sólo borra la entrada: el `.rpp`
  sigue en disco.
- **Barra inferior**: proyectos · carpetas · LED de REAPER (violeta = abierto,
  gris = cerrado) · horas abierto · horas grabando.
- **Backups**: se detectan los `<proyecto>.rpp-bak*` que REAPER deja junto al
  proyecto; se abren o se muestran en Finder desde la fila desplegable.
- **Horas**: `usage.json` lo escribe el tracker Lua; la app lo refresca cada 30 s.

## Arranque
Objetivo: abrir sin flash y en lo posible instantáneo. Medido con `log show`:

| | antes | ahora |
|---|---|---|
| snapshot de la biblioteca | 1.180 ms | **19–28 ms** |
| ventana visible | 1,5 s (y con parpadeo) | **0,37 s** |

Tres cambios:
1. **`snapshot()` ya no hace I/O pesado.** Regiones, pistas, tempo y copias de
   seguridad se guardan en `library.json` con su `mtime`+`size`, y se refrescan
   en segundo plano (`refreshScans`). Al terminar se empuja una actualización
   silenciosa (`_update`) que solo repinta el inspector.
2. **La ventana no se muestra hasta que la UI está pintada.** El JS avisa con
   `ready` después del primer `renderAll()`; hasta entonces la ventana existe
   pero no está en pantalla. Respaldo por timeout a los 4 s.
3. **Tema y acento antes del primer pintado.** `WKUserScript` en
   `documentStart` inyecta `data-theme`/`data-accent` leídos de `prefs.json`,
   más `underPageBackgroundColor` y `backgroundColor` de la ventana: el primer
   frame ya sale del color correcto, sin salto de tema ni blanco.

Ojo: `requestAnimationFrame` no corre en un WKWebView oculto; por eso el aviso
de `ready` es directo y no dentro de un rAF.

**Nada de I/O en el hilo principal.** El snapshot ya no hace ni un `stat`: el
tamaño sale de `scanSize` cacheado. Un solo `attributesOfItem` sobre una carpeta
protegida por TCC (o un volumen lento) bloqueaba el arranque hasta 10 s, el
tiempo que tarda en aparecer el diálogo de permisos de macOS. Todo el I/O vive
en la cola de fondo.

**Capa de fondo.** La ventana usa un `NSView` contenedor con el color del tema y
una capa opaca encima del `WKWebView` que se retira en el momento de mostrar la
ventana: aunque WebKit pinte su blanco inicial, ese frame nunca llega a pantalla.

## Atajos y ausencia en el Dock
La app corre como agente (`LSUIElement` + `NSApp.setActivationPolicy(.accessory)`):
no aparece en el Dock ni en ⌘Tab, y no tiene barra de menú. Por eso los atajos se
resuelven con un `NSEvent.addLocalMonitorForEvents`: ⌘Q (sale y cierra REAPER),
⌘W, ⌘C, ⌘V, ⌘X, ⌘A y ⌘Z se reenvían al responder chain.

Consecuencia: al no tener menú, si otro proceso tiene el foco los atajos no
llegan hasta que se hace clic en la ventana. macOS 14 además no permite que una
app agente se active sola desde segundo plano.

## Abrir con FX offline (1.1)
El diálogo nativo `Open project` tiene cuatro casillas: *Open in new project tab*,
*Open read-only*, *Open with FX offline (recovery mode)* y *Bring FX online after
load*. De esas, el API de ReaScript sólo documenta la de FX:

- `reaper.Main_openProject("fxoffline:" .. path)` → carga con todos los FX offline.
- CLI: `REAPER -fxoffline path` → lo mismo al arrancar REAPER cerrado.
- `new tab` y `read-only` no están en el API; por eso el launcher no las ofrece.

### Botón partido del inspector
`Abrir proyecto` es un `.rk-split` del kit: la mitad izquierda abre normal (⌥-clic
fuerza recovery mode) y el segmento de tres puntos despliega las demás formas de
apertura con `openMenuAt`. Si se agrega una opción de apertura nueva, va en ese
menú y no hace falta tocar el clic derecho.

### Canal de comandos app → REAPER
Como con REAPER abierto no se pueden pasar flags, la app escribe una línea en
`~/Library/Application Support/Project Launcher/inbox.txt` y `Project Launcher Startup.lua`
la consume desde su `defer` (cada ~8 ticks):

```
open normal <path>            # abre el proyecto en la pestaña actual
open fxoffline <path>         # recovery mode
open fxoffline-online <path>  # recovery mode y luego trae los FX online de a uno
fxonline                      # trae online los FX que estén offline
dump                          # escribe fxstate.txt (diagnóstico)
```

El modo `fxoffline-online` reintenta hasta ~5 s hasta que aparecen FX offline y
después los habilita uno por uno con `TrackFX_SetOffline`.

Verificado con un `.rpp` de prueba: `offline=true` al abrir en los tres caminos y
`offline=false` después de `fxonline` / `fxoffline-online`.

### Trampa de Lua en ReaScript
Las variables locales usadas dentro de un `defer` tienen que declararse **antes**
de la función que las usa: si no, Lua las resuelve como globales (`nil`) y el
script muere con "attempt to perform arithmetic on a nil value".

## Vigilante del aviso de licencia (sólo local, no se distribuye)

REAPER sin licencia abre la ventana `About REAPER…` ~1 s después de arrancar y no se puede
cerrar por configuración: ni un flag ni una preferencia la suprimen. En esta máquina hay un
vigilante que la manda fuera de pantalla antes de que se vea, espera a que el botón se
habilite y le hace clic.

- Vive en `~/Library/Application Support/Project Launcher/quiet-reaper.applescript`, **fuera
  del repo**. Si el archivo no existe, la app no hace nada: una instalación de terceros nunca
  ve este comportamiento ni pide permisos por él.
- Necesita permiso de **Accesibilidad** para `Project Launcher`. El build firma con la
  identidad local `Auri Local Signing` cuando existe (`certificate leaf`, no `cdhash`), así el
  permiso sobrevive a las recompilaciones; sin esa identidad cae a firma ad-hoc y macOS vuelve
  a pedir el permiso en cada build.
- El contador del diálogo **sólo avanza con REAPER al frente** (~7,4 s, ~1,6 s por unidad).
  Por eso durante ese rato el launcher no reclama el foco: `claimFocus()` se rinde si el
  vigilante está activo.
- Al terminar el vigilante deja la marca `quiet-done`; la app la consume y recupera el foco
  (cuando macOS lo permite: una app de agente lanzada en segundo plano no puede activarse sola).

## Toast con deshacer

`toast(msg, undoFn)` acepta una acción opcional. Con acción vive **5 s**, muestra el botón
**Deshacer** (icono Phosphor `arrow-counter-clockwise`), una barra verde que se agota y se
pausa mientras el cursor está encima. Sin acción dura 2.6 s y el botón queda oculto.

Acciones con deshacer: fijar, archivar, quitar/volver a recientes (también desde la X del
slim), mover a carpeta, quitar del launcher y eliminar proyecto.

Deshacer de "quitar del launcher" usa `restoreProject` (vuelve la entrada y borra el
tombstone); el de "eliminar" usa `undelete`, que saca el .rpp de la Papelera y lo devuelve
a su ruta original — por eso el comando `delete` ahora responde con `trashPath`.

## Diálogos y menús

**WKWebView bloquea `confirm()` y `prompt()`** salvo que el `WKUIDelegate` implemente
`runJavaScriptConfirmPanel` / `runJavaScriptTextInputPanel`; sin eso devuelven `false`
y `null` en silencio. Por eso "mover a carpeta", "eliminar proyecto" y "quitar del
launcher" no hacían nada. Todo pasa ahora por `askSheet()` en `selector.html`:
`askConfirm()`, `askText()` y `askFolder()`, con el mismo kit visual, Enter/Escape y
foco automático.

**El id del puente se parsea con `NSNumber`**: `body["id"] as? Int` puede fallar con los
números que entrega `WKScriptMessage`, y entonces la respuesta sale sin `_id`, la promesa
del JS nunca resuelve y el handler queda colgado antes de repintar. Se resuelve con
`(body["id"] as? NSNumber)?.intValue`. Aun así, las mutaciones se pintan primero y el
`update` viaja detrás (optimista), con un timeout de 4 s como red de seguridad.

**Los menús se colocan con `placeMenu()`**: el límite inferior es el borde superior de la
barra de estado, no el viewport (la barra vive dentro de la página y tapaba el último
ítem). Si no cabe abajo se abre hacia arriba, si no cabe a la derecha se corre a la
izquierda, y la altura se limita con scroll.

**Tombstones**: `library.ignored` guarda las rutas quitadas con "Quitar del launcher…".
`pickProject` y el seed desde `REAPER.ini` las saltan, así un proyecto quitado a mano no
vuelve a la lista al abrirlo desde fuera.

## Modo slim (1.2)

La ventana puede entrar en un modo de lista angosta de 380 × 620, pensado para dejar el launcher abierto al costado mientras trabajás.

**Lado nativo (`Selector.swift`)**
- El comando `slim` del canal `sel` llama a `setSlimWindow(_:)`.
- Al entrar guarda el marco actual en `fullFrame`, desactiva el autosave (`setFrameAutosaveName("")`) para que el tamaño slim no quede como tamaño por defecto, baja `minSize` a 340 × 420 y centra la ventana conservando el borde superior.
- Al salir restaura el marco guardado, vuelve a `minSize` 900 × 600 y reactiva el autosave.
- **Se recuerda entre sesiones**: el modo se guarda en `prefs.json` como `slim`. Al arrancar con `slim: true`, la ventana se ajusta antes de mostrar el WebView (`animate: false`, `persist: false`), así no hay salto de tamaño ni parpadeo, y el marco completo que había queda en `fullFrame` para volver con FULL.

**Lado web (`Resources/selector.html`)**
- `body.is-slim` oculta `.window` y muestra `<section class="slim">`.
- `renderSlim()` arma la lista: fijados primero y después el resto, ambos ordenados por última apertura. Usa `folderLabel()` para que las carpetas por defecto salgan en el idioma activo.
- Cada fila: punto de color de la carpeta, nombre, flecha verde, y en hover el pin a la izquierda y la X al extremo derecho.
- Fijar y quitar de recientes son **optimistas**: se muta el objeto local, se re-renderiza al instante y el `update` viaja después. Si se espera la respuesta nativa, la lista no se reordena hasta el siguiente refresco.
- Clic izquierdo abre el proyecto; clic derecho abre `slimMenu()` con Abrir, FX offline, FX online y Mostrar en Finder.
- `renderAll()` re-renderiza el slim cuando corresponde, así los cambios desde el modo full se reflejan sin volver a entrar.
- El nativo inyecta `data-slim="1"` en el `<html>` cuando la sesión anterior quedó en slim, y el JS arranca con `setSlim(true, false)`.

## Idioma (ES / EN)
- Un botón `EN`/`ES` en la barra inferior, junto al sol y la paleta, sin caja.
- `T(clave, vars)` traduce contra un diccionario cuyo **origen es el texto en
  español**; las cadenas compuestas usan marcadores (`{n}`, `{v}`, `{name}`).
- El marcado estático lleva `data-en`, `data-en-ph`, `data-en-title` y
  `data-en-aria`; `applyStaticI18n()` guarda el original y alterna.
- `ago()`, `hrs()` y `mb()` respetan el idioma (separador decimal y plurales).
- El idioma vive en `prefs.json` (`lang`) y se inyecta en `documentStart`
  (`data-lang`) junto al tema, así que el primer frame ya sale en el idioma
  correcto. Los nombres de carpetas, etiquetas y proyectos nunca se traducen:
  son datos del usuario.

## Portabilidad
No hay rutas de esta máquina en el código: `~` se expande con el home real que
entrega la app (`DB.home`), los scripts Lua usan `reaper.GetResourcePath()` y
`$HOME`, y la biblioteca arranca sembrada desde los recientes de REAPER. La
caché (`scanMtime`+`scanSize`) es por máquina y se reconstruye sola.

## Tema y acento
- Dos iconos Phosphor (bold) al extremo derecho de la barra inferior, sin caja:
  sol/luna para claro-oscuro y paleta para el esquema de color.
- Esquemas: Reapertips (violeta), **ReaSet Pro** (`#1ED760` y la paleta del kit),
  Cian, Ámbar y Rosa. Se guardan en `localStorage` (`sel.theme`, `sel.accent`) y
  el color del cromo de la ventana se sincroniza con `native('chrome')`.
- El tema claro redefine solo los tokens neutros (`html[data-theme="light"]`); los
  componentes del kit se adaptan sin tocar reglas.

## Menús contextuales
- Clic derecho nativo de WebKit desactivado (`contextmenu` + `selectstart`) y
  selección de texto bloqueada fuera de los campos.
- En la biblioteca: abrir, Finder, fijar, archivar, copias, mover a carpeta,
  quitar de recientes, eliminar proyecto.
- En la barra lateral (carpetas): abrir, renombrar, color e icono, nueva carpeta,
  eliminar carpeta (los proyectos pasan a «Sin carpeta»).
- Las carpetas guardan `folderMeta` (color + icono) en `library.json`.
- El selector de iconos usa 18 glifos **Phosphor Bold** (folder, folder-open,
  vinyl-record, music-notes, microphone, guitar, piano-keys, metronome,
  speaker-high, sliders, projector-screen, monitor-play, users-three, star,
  lightning, calendar-blank, ticket, gear) en una rejilla de 6 columnas.
- Los iconos del tema y del acento viven en la barra inferior sin contenedor:
  sin fondo, borde ni caja; solo cambian de color.

## Aspecto

- Barra de título integrada: `titlebarAppearsTransparent` + `titleVisibility .hidden`
  + `backgroundColor` igual al cromo (`#1F1F1F`) y sin separador. La franja superior
  y el contenido parecen una sola pieza; los semáforos quedan sobre la barra lateral.
- **Una sola línea de cabecera**: `REAPER`, `Biblioteca` y el título del inspector
  comparten token (`--rk-section`, 800 20px/1.25) y padding superior de 14 px, así
  que arrancan a la misma altura y con la misma baseline. La vista actual
  («Recientes», «Carpeta · X») va como sufijo atenuado del título.
- Rendimiento: `scan()` lee como máximo 4 MB con `FileHandle` y cachea por
  ruta+mtime+tamaño. Sin eso, un `.rpp` grande bloqueaba el pintado en cada refresco.
- Densidad: filas de tabla 34 px, cabecera 30, botones 30, topbar 9/9.
- Columnas: 260 / flexible / 344 px. Por debajo de 1380 pasan a 244 / flexible / 320
  y a 1080 el inspector se vuelve cajón. Con eso las tres columnas caben desde
  ~1100 px de ancho de ventana.

## Comportamiento conocido

- Con `loadlastproj=19`, REAPER abre un proyecto vacío antes de mostrar el
  selector. Al elegir otro proyecto queda esa pestaña vacía: se cierra con ⌘W
  (o arrancando REAPER desde el selector, que lo hace sin pestaña vacía).
- El nag de evaluación de REAPER sigue saliendo ~1 vez al día y no depende de
  esta app (`~/bin/reaper-clean-launch` y su vigilante lo descartan).

## Desarrollo

```bash
./build.sh     # compila Selector.swift y arma el .app firmado ad-hoc
```

- `Selector.swift` — ventana, WKWebView, puente JS y almacén JSON.
- `Resources/selector.html` — UI (kit ReaSet + paleta Reapertips).
- `Resources/selector.css`, `Resources/reaset-kit.css`.
- `scripts/*.lua` — lanzador y arranque/métricas.
