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

local host, root
local nextId = 0

-- Show a transient one-line notice at the top of the screen.
-- opts: tone (neutral|gold|info|up|down|warn), duration (seconds, default 4).
function UI.toast(text, opts)
  opts = opts or {}
  if not host then
    host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("DIALOG")
    host:SetSize(640, 400)
    host:SetPoint("TOP", UIParent, "TOP", 0, -140)
    I.followScale(host, false)
    root = UI.mount(host, ToastStack {})
  end
  local ctx = root.node.ctx
  nextId = nextId + 1
  local id = nextId
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
