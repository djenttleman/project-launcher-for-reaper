-- ReaSet Selector · lanzador
-- Abre la app nativa del selector de proyectos.
-- A prueba de actualizaciones: no toca el bundle de REAPER ni rutas fijas de versión.

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

local function home()
  return os.getenv("HOME") or ""
end

local CANDIDATES = {
  home() .. "/Applications/ReaLauncher.app",
  "/Applications/ReaSet Selector.app",
}

local function findApp()
  for _, p in ipairs(CANDIDATES) do
    if exists(p .. "/Contents/MacOS/ReaLauncher") or exists(p .. "/Contents/MacOS/ReaSetSelector") then return p end
  end
  return nil
end

local function quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local app = findApp()
if not app then
  reaper.MB(
    "No encuentro «ReaLauncher.app».\n\n" ..
    "Buscado en:\n  ~/Applications/ReaLauncher.app\n  /Applications/ReaLauncher.app\n\n" ..
    "Instalalo de nuevo con el instalador.",
    "ReaLauncher", 0)
  return
end

-- Si ya está abierta, `open -a` la trae al frente en vez de duplicarla.
reaper.ExecProcess("/usr/bin/open -a " .. quote(app), 0)

if not reaper.GetExtState("ReaLauncher", "aviso") or
   reaper.GetExtState("ReaLauncher", "aviso") ~= "1" then
  reaper.SetExtState("ReaLauncher", "aviso", "1", true)
  reaper.defer(function()
    reaper.ShowConsoleMsg("ReaLauncher: lanzado (" .. app .. ")\n")
  end)
end
