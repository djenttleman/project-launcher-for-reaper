# ReaLauncher

Selector de proyectos de REAPER. Reemplaza el diálogo nativo *Choose Project*
por una ventana propia con biblioteca, carpetas y etiquetas virtuales, pin,
backups por proyecto y métricas de uso.

## Qué se instala

| Pieza | Ruta |
|---|---|
| App nativa (WKWebView) | `~/Applications/ReaLauncher.app` |
| Lanzador (Action List) | `~/Library/Application Support/REAPER/Scripts/Reaset Scripts/ReaLauncher.lua` |
| Arranque + métricas | `~/Library/Application Support/REAPER/Scripts/Reaset Scripts/ReaLauncher Startup.lua` |
| Gancho de arranque | `~/Library/Application Support/REAPER/Scripts/__startup.lua` (bloque marcado) |
| Biblioteca del launcher | `~/Library/Application Support/ReaLauncher/library.json` |
| Horas de uso | `~/Library/Application Support/ReaLauncher/usage.json` |

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
cd ~/dev/realauncher
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
`~/Library/Application Support/ReaLauncher/inbox.txt` y `ReaLauncher Startup.lua`
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
