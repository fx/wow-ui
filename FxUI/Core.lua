local ADDON, ns = ...

local MAJOR, MINOR = "FxUI-1.0", 1

local UI = LibStub:NewLibrary(MAJOR, MINOR)
ns.FxUI = UI or false
if not UI then return end

UI.MAJOR, UI.MINOR = MAJOR, MINOR

-- Shared between FxUI's own files; not part of the public API. A newer copy
-- loading over an older one keeps this table, so live state (mounted roots,
-- pools, scale followers, settings) carries over; each file keeps its state
-- tables (`I.x = I.x or ...`) and replaces only the functions.
local I = UI._internal or {}
UI._internal = I

-- Resolve the folder this copy was loaded from, so media paths work both for
-- the standalone addon and for a copy embedded in another addon.
local function resolveRoot()
  local stack = debugstack and debugstack(1, 1, 0) or ""
  local path = stack:match("[Aa][Dd][Dd][Oo][Nn][Ss][/\\](.-)[/\\]Core%.lua")
  if not path or path:find("%.%.%.") then
    path = ADDON
  end
  return "Interface\\AddOns\\" .. path:gsub("/", "\\") .. "\\"
end

I.root = resolveRoot()
I.media = I.root .. "Media\\"

function I.noop() end

function I.wipe(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

function I.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function I.round(v)
  return math.floor(v + 0.5)
end

-- The last errors FxUI reported, newest last, for dev tools.
I.errors = I.errors or {}

-- Report an error through the client's handler (BugSack and friends pick it
-- up) without unwinding the caller.
function I.report(err)
  local errors = I.errors
  errors[#errors + 1] = { time = time and time() or 0, message = tostring(err) }
  if #errors > 50 then table.remove(errors, 1) end
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(err) else print(err) end
end

function I.safecall(fn, ...)
  local n, args = select("#", ...), { ... }
  local ok, a, b, c = xpcall(function() return fn(unpack(args, 1, n)) end, function(e)
    return debugstack and (tostring(e) .. "\n" .. debugstack(2)) or tostring(e)
  end)
  if not ok then
    I.report(a)
    return false
  end
  return true, a, b, c
end

-- Library-wide client event dispatch. An upgrade keeps the frame and drops
-- the older copy's handlers and combat listeners, which the newer copy's files
-- register again as they load.
I.events = I.events or CreateFrame("Frame")
I.eventHandlers = {}

I.events:SetScript("OnEvent", function(_, event, ...)
  local handlers = I.eventHandlers[event]
  if not handlers then return end
  for fn in pairs(handlers) do
    I.safecall(fn, event, ...)
  end
end)

function I.on(event, fn)
  local handlers = I.eventHandlers[event]
  if not handlers then
    handlers = {}
    I.eventHandlers[event] = handlers
    I.events:RegisterEvent(event)
  end
  handlers[fn] = true
end

-- Combat state, updated before any combat listener runs.
I.inCombat = InCombatLockdown() and true or false
I.combatListeners = {}

local function combatChanged(event)
  I.inCombat = event == "PLAYER_REGEN_DISABLED"
  for fn in pairs(I.combatListeners) do
    I.safecall(fn, I.inCombat)
  end
end

I.on("PLAYER_REGEN_DISABLED", combatChanged)
I.on("PLAYER_REGEN_ENABLED", combatChanged)

function UI.inCombat()
  return I.inCombat
end
