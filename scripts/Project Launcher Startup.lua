-- ReaSet Selector · arranque
-- 1) Acumula horas de REAPER abierto y de grabación en usage.json (lo lee la app).
-- 2) Si REAPER arrancó sin proyecto, abre el selector en lugar del diálogo nativo.
--
-- A prueba de actualizaciones: vive en el resource path del usuario y no depende
-- de la versión de REAPER ni del bundle de la aplicación.

local SEP = package.config:sub(1, 1)

local function supportDir()
  return (os.getenv("HOME") or "") .. "/Library/Application Support/Project Launcher"
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
-- forward: el loop de tick los usa antes de que exista el bloque de comandos
local pollAcc = 0
local pollInbox = nil

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
  pollAcc = pollAcc + 1
  if pollAcc >= 8 then pollAcc = 0; if pollInbox then pollInbox() end end
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


-- --------------------------------------------------------- canal de comandos
-- La app deja órdenes en inbox.txt y este loop las ejecuta dentro de REAPER:
-- así el launcher puede abrir con FX offline o traer los FX online sin
-- depender de la UI de REAPER. Se revisa cada ~0.25 s (no por tick).
local INBOX = DIR .. "/inbox.txt"

local function allOfflineFX()
  local list = {}
  for ti = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, ti)
    if tr then
      for fi = 0, reaper.TrackFX_GetCount(tr) - 1 do
        if reaper.TrackFX_GetOffline(tr, fi) then list[#list + 1] = { tr, fi } end
      end
    end
  end
  -- master
  local master = reaper.GetMasterTrack(0)
  if master then
    for fi = 0, reaper.TrackFX_GetCount(master) - 1 do
      if reaper.TrackFX_GetOffline(master, fi) then list[#list + 1] = { master, fi } end
    end
  end
  return list
end

-- Trae los FX online de a uno, imitando "Bring FX online after load".
local function bringOnlineStaggered(list, idx)
  idx = idx or 1
  if not list or idx > #list then return end
  local it = list[idx]
  if it[1] and reaper.ValidatePtr2(0, it[1], "MediaTrack*") then
    reaper.TrackFX_SetOffline(it[1], it[2], false)
  end
  reaper.defer(function() bringOnlineStaggered(list, idx + 1) end)
end

local function openProject(mode, path)
  local prefix = ""
  if mode == "fxoffline" or mode == "fxoffline-online" then prefix = "fxoffline:" end
  reaper.Main_openProject(prefix .. path)
  if mode == "fxoffline-online" then
    -- el proyecto carga con FX offline; en cuanto aparezcan, se traen online
    -- de a uno. Se reintenta hasta ~5 s por si el proyecto es grande.
    local tries = 0
    local function wait()
      tries = tries + 1
      local list = allOfflineFX()
      if #list > 0 then bringOnlineStaggered(list); return end
      if tries < 300 then reaper.defer(wait) end
    end
    reaper.defer(wait)
  end
end

local function handleCommand(line)
  local cmd, rest = line:match("^([%w%-]+)%s*(.*)$")
  if not cmd then return end
  if cmd == "open" then
    local mode, path = rest:match("^([%w%-]+)%s+(.+)$")
    if path then openProject(mode, path) end
  elseif cmd == "fxonline" then
    bringOnlineStaggered(allOfflineFX())
  elseif cmd == "dump" then
    local out = {}
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
        local _, name = reaper.TrackFX_GetFXName(tr, fx, "")
        out[#out + 1] = string.format("track %d fx %d offline=%s %s", i + 1, fx + 1,
          tostring(reaper.TrackFX_GetOffline(tr, fx) and true or false), name)
      end
    end
    writeFile(DIR .. "/fxstate.txt", table.concat(out, "\n") .. "\n")
  end
end

pollInbox = function()
  local raw = readFile(INBOX)
  if raw and raw ~= "" then
    os.remove(INBOX)
    for line in raw:gmatch("[^\r\n]+") do
      if line ~= "" then handleCommand(line) end
    end
  end
end

reaper.defer(tick)
reaper.defer(flusher)

-- --------------------------------------------------- selector al arrancar
-- Sólo si REAPER quedó sin proyecto (arranque "en blanco"). Si el usuario abrió
-- un .rpp desde Finder, el proyecto ya está cargado y no se muestra nada.
local function selectorApp()
  local home = os.getenv("HOME") or ""
  local cands = { home .. "/Applications/Project Launcher.app", home .. "/Applications/ReaLauncher.app" }
  for _, p in ipairs(cands) do
    local f = io.open(p .. "/Contents/MacOS/ProjectLauncher", "r") or io.open(p .. "/Contents/MacOS/ReaSetSelector", "r")
    if f then f:close(); return p end
  end
  return nil
end

-- -------------------------------------------------- Action List (una vez)
-- AddRemoveReaScript es la vía soportada: agrega el lanzador a la Action List
-- sin tocar reaper-kb.ini a mano. Si REAPER se actualiza, el bloque se repone.
if reaper.GetExtState("ProjectLauncher", "action") ~= "1" then
  local launcher = reaper.GetResourcePath() .. "/Scripts/Reaset Scripts/Project Launcher.lua"
  if reaper.file_exists(launcher) then
    reaper.AddRemoveReaScript(true, 0, launcher, true)
    reaper.SetExtState("ProjectLauncher", "action", "1", true)
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
