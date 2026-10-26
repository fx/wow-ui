local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local TONE_COLORS = { neutral = "muted", gold = "gold", info = "info", up = "up", down = "down", warn = "warn" }

local ToastStack = UI.component("FxToastStack", {
  init = function(ctx)
    ctx.state.items = {}
  end,
  render = function(_, ctx)
    local rows = {}
    for i, t in ipairs(ctx.state.items) do
      rows[i] = UI.HStack {
        key = t.id,
        gap = 10,
        padding = { 10, 16 },
        surface = "toast",
        UI.Dot { color = TONE_COLORS[t.tone] or t.tone or "gold" },
        UI.Text { text = t.text },
      }
    end
    return UI.VStack { gap = 8, align = "center", rows }
  end,
})

-- One toast stack for every copy of the library: an upgrade keeps it.
I.toast = I.toast or { nextId = 0 }
local T = I.toast

-- Show a transient one-line notice at the top of the screen.
-- opts: tone (neutral|gold|info|up|down|warn), duration (seconds, default 4).
function UI.toast(text, opts)
  opts = opts or {}
  if not T.host then
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("DIALOG")
    host:SetSize(640, 400)
    host:SetPoint("TOP", UIParent, "TOP", 0, -140)
    I.followScale(host, false)
    T.host = host
    T.root = UI.mount(host, ToastStack {})
  end
  local ctx = T.root.node.ctx
  T.nextId = T.nextId + 1
  local id = T.nextId
  local items = ctx.state.items
  items[#items + 1] = { id = id, text = text, tone = opts.tone }
  while #items > 5 do table.remove(items, 1) end
  ctx:setState({})
  C_Timer.After(opts.duration or 4, function()
    for i, t in ipairs(ctx.state.items) do
      if t.id == id then
        table.remove(ctx.state.items, i)
        break
      end
    end
    ctx:setState({})
  end)
end
