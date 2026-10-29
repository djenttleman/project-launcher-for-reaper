-- ReaSet Selector · arranque
-- 1) Acumula horas de REAPER abierto y de grabación en usage.json (lo lee la app).
-- 2) Si REAPER arrancó sin proyecto, abre el selector en lugar del diálogo nativo.
--
-- A prueba de actualizaciones: vive en el resource path del usuario y no depende
-- de la versión de REAPER ni del bundle de la aplicación.

local SEP = package.config:sub(1, 1)

local function supportDir()
  return (os.getenv("HOME") or "") .. "/Library/Application Support/ReaLauncher"
end

local function ensureDir(path)
  os.execute("/bin/mkdir -p " .. string.format("%q", path))
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function writeFile(path, text)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return false end
  f:write(text); f:close()
  os.rename(tmp, path)
  return true
end

local function numberAfter(s, key)
  if not s then return 0 end
  local v = s:match('"' .. key .. '"%s*:%s*([%-%d%.eE]+)')
  return tonumber(v) or 0
end

-- ---------------------------------------------------------------- usage
local DIR = supportDir()
ensureDir(DIR)
local USAGE = DIR .. "/usage.json"

local prior = readFile(USAGE)
local secondsOpen = numberAfter(prior, "secondsOpen")
local secondsRec = numberAfter(prior, "secondsRec")

local dirty = false
local last = reaper.time_precise()

local function flush()
  if not dirty then return end
  writeFile(USAGE, string.format(
    '{\n  "secondsOpen" : %.3f,\n  "secondsRec" : %.3f,\n  "updatedAt" : %.0f\n}\n',
    secondsOpen, secondsRec, os.time()))
  dirty = false
end

local function tick()
  local now = reaper.time_precise()
  local dt = now - last
  last = now
  if dt > 0 and dt < 30 then
    secondsOpen = secondsOpen + dt
    if reaper.GetPlayState() & 4 ~= 0 then secondsRec = secondsRec + dt end
    dirty = true
  end
  reaper.defer(tick)
end

reaper.atexit(flush)

-- flush cada 15 s (sin crear otro defer loop)
local acc = 0
local function flusher()
  acc = acc + 1
  if acc >= 15 then acc = 0; flush() end
  reaper.defer(flusher)
end

reaper.defer(tick)
reaper.defer(flusher)

-- --------------------------------------------------- selector al arrancar
-- Sólo si REAPER quedó sin proyecto (arranque "en blanco"). Si el usuario abrió
-- un .rpp desde Finder, el proyecto ya está cargado y no se muestra nada.
local function selectorApp()
  local home = os.getenv("HOME") or ""
  local cands = { home .. "/Applications/ReaLauncher.app", "/Applications/ReaSet Selector.app" }
  for _, p in ipairs(cands) do
    local f = io.open(p .. "/Contents/MacOS/ReaLauncher", "r") or io.open(p .. "/Contents/MacOS/ReaSetSelector", "r")
    if f then f:close(); return p end
  end
  return nil
end

-- -------------------------------------------------- Action List (una vez)
-- AddRemoveReaScript es la vía soportada: agrega el lanzador a la Action List
-- sin tocar reaper-kb.ini a mano. Si REAPER se actualiza, el bloque se repone.
if reaper.GetExtState("ReaLauncher", "action") ~= "1" then
  local launcher = reaper.GetResourcePath() .. "/Scripts/Reaset Scripts/ReaLauncher.lua"
  if reaper.file_exists(launcher) then
    reaper.AddRemoveReaScript(true, 0, launcher, true)
    reaper.SetExtState("ReaLauncher", "action", "1", true)
  end
end

local function maybeLaunchSelector(tries)
  tries = tries or 0
  local _, proj = reaper.EnumProjects(-1, "")
  if proj and proj ~= "" then return end          -- hay proyecto: no molestar
  if tries < 4 then                                  -- dar tiempo al arranque
    reaper.defer(function() maybeLaunchSelector(tries + 1) end)
    return
  end
  local app = selectorApp()
  if not app then return end
  reaper.ExecProcess("/usr/bin/open -a " .. string.format("%q", app), 0)
end

reaper.defer(function() maybeLaunchSelector(0) end)
