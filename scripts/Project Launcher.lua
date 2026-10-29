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
  home() .. "/Applications/Project Launcher.app",
  "/Applications/ReaSet Selector.app",
}

local function findApp()
  for _, p in ipairs(CANDIDATES) do
    if exists(p .. "/Contents/MacOS/ProjectLauncher") or exists(p .. "/Contents/MacOS/ReaSetSelector") then return p end
  end
  return nil
end

local function quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local app = findApp()
if not app then
  reaper.MB(
    "No encuentro «Project Launcher.app».\n\n" ..
    "Buscado en:\n  ~/Applications/Project Launcher.app\n  /Applications/Project Launcher.app\n\n" ..
    "Instalalo de nuevo con el instalador.",
    "Project Launcher", 0)
  return
end

-- Si ya está abierta, `open -a` la trae al frente en vez de duplicarla.
reaper.ExecProcess("/usr/bin/open -a " .. quote(app), 0)

if not reaper.GetExtState("ProjectLauncher", "aviso") or
   reaper.GetExtState("ProjectLauncher", "aviso") ~= "1" then
  reaper.SetExtState("ProjectLauncher", "aviso", "1", true)
  reaper.defer(function()
    reaper.ShowConsoleMsg("Project Launcher: lanzado (" .. app .. ")\n")
  end)
end
