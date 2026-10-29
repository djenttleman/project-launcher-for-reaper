#!/usr/bin/env bash
# Instalador de ReaSet Selector
#   · app nativa en ~/Applications
#   · scripts Lua en el resource path de REAPER (sobreviven a actualizaciones)
#   · __startup.lua idempotente (bloque marcado)
#   · loadlastproj=0 para que REAPER no muestre el diálogo nativo
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$HOME/Library/Application Support/REAPER"
SCRIPTS="$RES/Scripts"
SCRIPTS_DIR="$SCRIPTS/Reaset Scripts"
STARTUP="$SCRIPTS/__startup.lua"
INI="$RES/REAPER.ini"
TS="$(date +%Y%m%d-%H%M%S)"

# ---- revertir -------------------------------------------------------------
if [ "${1:-}" = "--revert" ]; then
  if pgrep -x REAPER >/dev/null 2>&1; then
    echo "✗ Cierra REAPER antes de revertir."; exit 1
  fi
  if [ -f "$SCRIPTS/__startup.lua" ]; then
    cp "$SCRIPTS/__startup.lua" "$SCRIPTS/__startup.lua.bak-$TS"
    awk 'BEGIN{skip=0}
         /^-- >>> (ReaSet Selector|ReaLauncher)/{skip=1}
         !skip{print}
         /^-- <<< (ReaSet Selector|ReaLauncher) <<</{skip=0}' \
      "$SCRIPTS/__startup.lua.bak-$TS" > "$SCRIPTS/__startup.lua"
    echo "  bloque del selector quitado de __startup.lua"
  fi
  if [ -f "$INI" ]; then
    cp "$INI" "$INI.bak-$TS"
    /usr/bin/sed -i '' 's/^loadlastproj=.*/loadlastproj=20/' "$INI"
    echo "  loadlastproj devuelto a 20 (diálogo nativo)"
  fi
  rm -f "$SCRIPTS_DIR/ReaSet Selector.lua" "$SCRIPTS_DIR/ReaSet Selector Startup.lua" \
        "$SCRIPTS_DIR/ReaLauncher.lua" "$SCRIPTS_DIR/ReaLauncher Startup.lua"
  echo "  scripts del selector eliminados (la app y los datos quedan)"
  exit 0
fi

say() { printf '  %s\n' "$*"; }

REAPER_ABIERTO=0
if pgrep -x REAPER >/dev/null 2>&1; then
  REAPER_ABIERTO=1
  echo "! REAPER está abierto: se instala todo salvo la preferencia de REAPER.ini"
fi

echo "== 1/5 app =="
if [ "${1:-}" != "--no-build" ]; then
  "$HERE/build.sh" >/dev/null
  say "compilada y firmada ad-hoc"
fi
say "$HOME/Applications/ReaLauncher.app"

echo "== 1b/5 migración de datos y limpieza =="
OLD_SUP="$HOME/Library/Application Support/ReaSet Selector"
NEW_SUP="$HOME/Library/Application Support/ReaLauncher"
if [ -d "$OLD_SUP" ] && [ ! -d "$NEW_SUP" ]; then
  mv "$OLD_SUP" "$NEW_SUP"; say "biblioteca y horas migradas a ReaLauncher/"
fi
if [ -d "$HOME/Applications/ReaSet Selector.app" ]; then
  rm -rf "$HOME/Applications/ReaSet Selector.app"; say "app anterior (ReaSet Selector.app) eliminada"
fi

echo "== 2/5 scripts Lua =="
mkdir -p "$SCRIPTS_DIR"
# limpiar la generación anterior del nombre
rm -f "$SCRIPTS_DIR/ReaSet Selector.lua" "$SCRIPTS_DIR/ReaSet Selector Startup.lua"

for f in "ReaLauncher.lua" "ReaLauncher Startup.lua"; do
  cp "$HERE/scripts/$f" "$SCRIPTS_DIR/$f"
  if command -v luac >/dev/null 2>&1; then
    luac -p "$SCRIPTS_DIR/$f" && say "$f · sintaxis OK"
  else
    say "$f"
  fi
done

echo "== 3/5 __startup.lua =="
touch "$STARTUP"
cp "$STARTUP" "$STARTUP.bak-$TS"
BLOCK_BEGIN="-- >>> ReaLauncher (no editar dentro de este bloque) >>>"
BLOCK_END="-- <<< ReaLauncher <<<"
# quitar bloques anteriores (ReaSet Selector / ReaLauncher) y volver a escribir
if grep -qE "^-- >>> (ReaSet Selector|ReaLauncher)" "$STARTUP" 2>/dev/null; then
  awk 'BEGIN{skip=0}
       /^-- >>> (ReaSet Selector|ReaLauncher)/{skip=1}
       !skip{print}
       /^-- <<< (ReaSet Selector|ReaLauncher) <<</{skip=0}' \
    "$STARTUP" > "$STARTUP.tmp" && mv "$STARTUP.tmp" "$STARTUP"
  say "bloque anterior reemplazado (backup: __startup.lua.bak-$TS)"
fi
{
  printf '\n%s\n' "$BLOCK_BEGIN"
  printf 'local _sel = "%s/ReaLauncher Startup.lua"\n' "$SCRIPTS_DIR"
  printf 'if reaper.file_exists(_sel) then dofile(_sel) end\n'
  printf '%s\n' "$BLOCK_END"
} >> "$STARTUP"

echo "== 4/5 preferencia de arranque =="
if [ "$REAPER_ABIERTO" = "1" ]; then
  say "omitido (REAPER abierto) · loadlastproj actual: $(grep -m1 '^loadlastproj=' "$INI" | cut -d= -f2)"
else
cp "$INI" "$INI.bak-$TS"
CUR="$(grep -m1 '^loadlastproj=' "$INI" | cut -d= -f2 || echo "")"
say "loadlastproj actual: ${CUR:-?} (20 = preguntar, el diálogo nativo)"
/usr/bin/sed -i '' 's/^loadlastproj=.*/loadlastproj=19/' "$INI"
say "→ 19 (proyecto nuevo sin diálogo; REAPER normaliza este valor)"
say "backup: REAPER.ini.bak-$TS · revertir: install --revert"
fi

echo "== 5/5 resumen =="
say "app:     $HOME/Applications/ReaLauncher.app"
say "scripts: $SCRIPTS_DIR/ReaLauncher.lua"
say "         $SCRIPTS_DIR/ReaLauncher Startup.lua"
say "hook:    $STARTUP"
say "datos:   $HOME/Library/Application Support/ReaLauncher/"
echo
echo "Para tenerlo en la Action List: Actions → Show action list → New action →"
echo "Load ReaScript… → Scripts/Reaset Scripts/ReaLauncher.lua"
