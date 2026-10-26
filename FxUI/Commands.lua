local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

-- One /fx slash command shared by every addon using FxUI: each registers a
-- subcommand (/fx demo, /fx dev, ...). Survives library upgrades.
UI.commands = UI.commands or {}

-- name: one word, case-insensitive. handler(args) gets the rest of the line.
function UI.registerCommand(name, handler, help)
  assert(type(name) == "string" and name:match("^%w[%w_-]*$"), "FxUI: command name must be one word")
  assert(type(handler) == "function", "FxUI: command needs a handler")
  UI.commands[name:lower()] = { name = name:lower(), handler = handler, help = help }
end

function UI.unregisterCommand(name)
  UI.commands[name:lower()] = nil
end

local function printHelp()
  local names = {}
  for name in pairs(UI.commands) do names[#names + 1] = name end
  table.sort(names)
  print("|cffE2B04A/fx|r commands:")
  if #names == 0 then
    print("  none registered")
    return
  end
  for _, name in ipairs(names) do
    local c = UI.commands[name]
    print("  |cffE2B04A/fx " .. name .. "|r" .. (c.help and ("  " .. c.help) or ""))
  end
end

function I.runCommand(msg)
  local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  name = (name or ""):lower()
  if name == "" or name == "help" then
    printHelp()
    return
  end
  local c = UI.commands[name]
  if not c then
    print("|cffE2B04A/fx|r: no command '" .. name .. "'.")
    printHelp()
    return
  end
  I.safecall(c.handler, rest or "")
end

SLASH_FXUI_COMMANDS1 = "/fx"
SlashCmdList.FXUI_COMMANDS = function(msg) I.runCommand(msg) end
