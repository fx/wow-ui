local _, ns = ...
local UI = LibStub("FxUI-1.0")

-- Item IDs across qualities that exist in the retail item database.
local ITEMS = {
  2770, 2771, 2772, 3858, 10620, 2840, 3575, 3860, 12359, 12360,
  2589, 2592, 4306, 4338, 14047, 13463, 13464, 13467, 13468, 8831,
  7078, 7076, 12808, 13444, 13446, 6149, 6948, 117, 4540, 159,
  3300, 4865, 18832, 19364, 19019, 17182, 32837, 49623, 71086, 77949,
}

local TAGS = {
  { text = "New", tone = "up" },
  { text = "Hot", tone = "warn" },
  { text = "Watch", tone = "info" },
  { text = "Low", tone = "down" },
}

-- Deterministic pseudo-random numbers so the demo looks the same each time.
local seed = 12345
local function rand(lo, hi)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return lo + seed % (hi - lo + 1)
end

local function buildRows(n)
  local rows = {}
  for i = 1, n do
    rows[i] = {
      id = i,
      item = ITEMS[rand(1, #ITEMS)],
      qty = rand(1, 200),
      price = rand(5, 4000000),
      change = rand(-30, 30),
      tag = rand(1, 6) <= #TAGS and TAGS[rand(1, #TAGS)] or nil,
    }
  end
  return rows
end

local function walk(n, start, spread)
  local out, v = {}, start
  for i = 1, n do
    v = math.max(v + rand(-spread, spread), 1)
    out[i] = v
  end
  return out
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

local function Card(title, props)
  props = props or {}
  local t = {
    gap = props.gap or 12,
    padding = 16,
    surface = "card",
    flex = props.flex,
    height = props.height,
    UI.Text { text = title, style = "label", color = "muted" },
  }
  for i, child in ipairs(props) do t[#t + 1] = child end
  return UI.VStack(t)
end

local function Row(props)
  props.gap = props.gap or 8
  props.align = props.align or "center"
  return UI.HStack(props)
end

-- A row of chips or buttons that wraps onto new lines when it runs out of room.
local function Flow(props)
  props.wrap = true
  props.rowGap = props.rowGap or 8
  return Row(props)
end

local function LabeledMoney(label, value, opts)
  opts = opts or {}
  return Row {
    UI.Text { text = label, color = "muted", width = 150 },
    UI.Money { value = value, compact = opts.compact, signed = opts.signed, tone = opts.tone },
  }
end

---------------------------------------------------------------------------
-- Controls page
---------------------------------------------------------------------------

local ControlsPage = UI.component("DemoControls", {
  init = function(ctx)
    ctx.state.busy = false
    ctx.state.compact = true
    ctx.state.extras = false
    ctx.state.spent = 12400000
    ctx.state.minPrice = 50000
    ctx.state.level = 3
  end,
  render = function(_, ctx)
    local s = ctx.state
    local cap = 50000000
    return Row {
      align = "stretch",
      gap = 16,
      padding = 16,
      UI.VStack {
        flex = 1,
        gap = 16,
        Card("Buttons", {
          Flow {
            UI.Button { text = "Primary", variant = "primary", onClick = function() UI.toast("Primary clicked", { tone = "gold" }) end },
            UI.Button { text = "Secondary" },
            UI.Button { text = "Delete", variant = "danger" },
            UI.Button { text = "Details", variant = "ghost" },
            UI.Button { text = "Disabled", disabled = true },
          },
          Flow {
            UI.Button { text = "Small", size = "sm" },
            UI.Button { text = "Medium", size = "md" },
            UI.Button { text = "Large action", size = "lg", variant = "primary" },
          },
          Flow {
            UI.Button {
              text = "Load data",
              busy = s.busy and "Loading\226\128\166" or nil,
              onClick = function()
                ctx:setState({ busy = true })
                ctx:after(2, function() ctx:setState({ busy = false }) end)
              end,
            },
            UI.Button {
              text = "Secure action",
              variant = "primary",
              secure = true,
              tooltip = "Runs inside the real click. Disabled in combat.",
              onClick = function()
                UI.toast("Handled synchronously inside the click", { tone = "info" })
              end,
            },
            UI.Text { text = UI.inCombat() and "In combat" or "Out of combat", color = UI.inCombat() and "down" or "muted" },
          },
        }),
        Card("Badges", {
          Flow {
            UI.Badge { text = "New", tone = "up" },
            UI.Badge { text = "Info", tone = "info" },
            UI.Badge { text = "Gold", tone = "gold" },
            UI.Badge { text = "+9%", tone = "warn" },
            UI.Badge { text = "Low", tone = "down" },
            UI.Badge { text = "Stale" },
          },
          Flow {
            UI.Badge { text = "Solid", tone = "gold", solid = true },
            UI.Badge { text = "Ready", tone = "up", solid = true },
            UI.Badge { text = "Error", tone = "down", solid = true },
          },
        }),
        Card("Toggles", {
          UI.Toggle { label = "Compact money above 100g", checked = s.compact, onChange = function(v) ctx:setState({ compact = v }) end },
          UI.Toggle { label = "Extra tooltip lines on items", checked = s.extras, onChange = function(v) ctx:setState({ extras = v }) end },
          UI.Toggle { label = "Disabled toggle", checked = true, disabled = true },
        }),
        Card("Help", {
          Row { gap = 8,
            UI.Text { text = "Hover the marks", color = "muted" },
            UI.Help { title = "Help icons", text = "A small ? that explains something in FxUI's own tooltip, instead of a line of text." },
            UI.Help { text = "Text alone, without a title." },
          },
        }),
        Card("Toggle group", {
          UI.ToggleGroup { label = "PERIOD", value = s.period or "day",
            items = { { id = "hour", text = "Hour" }, { id = "day", text = "Day" }, { id = "week", text = "Week" }, { id = "month", text = "Month", disabled = true, tooltip = "Not enough history yet." } },
            onChange = function(id) ctx:setState({ period = id }) end },
        }),
        Card("Pressable", {
          Row { gap = 8,
            UI.Pressable { tooltip = "Any content can be a click target.", padding = { 2, 6 }, align = "end",
              onClick = function() ctx:setState({ pressed = (s.pressed or 0) + 1 }) end,
              UI.Money { value = 1234500 },
              UI.Text { text = "clicked " .. (s.pressed or 0) .. "\195\151", style = "small", color = "muted" },
            },
            UI.Pressable { disabled = true, padding = { 2, 6 }, UI.Text { text = "Disabled", color = "muted" } },
            UI.Pressable { padding = { 2, 6 }, tooltip = "Opens a context menu.",
              onClick = function(frame)
                UI.showMenu(frame, {
                  { text = "Reset the count", onClick = function() ctx:setState({ pressed = 0 }) end },
                  { divider = true },
                  { text = "Not available", disabled = true },
                }, { title = "MENU" })
              end,
              UI.Text { text = "Menu\226\128\166" },
            },
          },
        }),
        Card("Sliders", {
          UI.Slider { label = "At least", values = { 0, 10000, 50000, 100000, 500000, 1000000, 5000000 }, value = s.minPrice,
            format = function(v) return UI.formatMoney(v, { short = true }) end,
            onChange = function(v) ctx:setState({ minPrice = v }) end },
          UI.Slider { label = "Level", min = 0, max = 10, value = s.level, onChange = function(v) ctx:setState({ level = v }) end },
          UI.Slider { label = "Disabled", min = 0, max = 10, value = 7, disabled = true },
        }),
      },
      UI.VStack {
        flex = 1,
        gap = 16,
        Card("Money", {
          gap = 8,
          LabeledMoney("123456 copper", 123456),
          LabeledMoney("Large, compact", 12403456, { compact = s.compact }),
          LabeledMoney("Signed gain", 1840, { signed = true, tone = "up" }),
          LabeledMoney("Loss", -320, { tone = "down" }),
          LabeledMoney("Exactly 5 silver", 500),
          LabeledMoney("Nothing", 0),
        }),
        Card("Meter", {
          UI.Meter {
            label = "Spend",
            valueText = UI.formatMoney(s.spent, { compact = true }) .. " / " .. UI.formatMoney(cap, { compact = true }),
            value = s.spent,
            max = cap,
            tone = s.spent > cap * 0.8 and "down" or "gold",
          },
          Flow {
            UI.Button { text = "\226\136\146500g", size = "sm", onClick = function() ctx:setState({ spent = math.max(s.spent - 5000000, 0) }) end },
            UI.Button { text = "+500g", size = "sm", onClick = function() ctx:setState({ spent = math.min(s.spent + 5000000, cap) }) end },
          },
        }),
        Card("Toasts", {
          Flow {
            UI.Button { text = "Info", size = "sm", onClick = function() UI.toast("Something worth knowing", { tone = "info" }) end },
            UI.Button { text = "Success", size = "sm", onClick = function() UI.toast("Saved", { tone = "up" }) end },
            UI.Button { text = "Warning", size = "sm", onClick = function() UI.toast("Prices moved since the last scan", { tone = "warn" }) end },
            UI.Button { text = "Error", size = "sm", onClick = function() UI.toast("That did not work", { tone = "down" }) end },
          },
        }),
      },
    }
  end,
})

---------------------------------------------------------------------------
-- Items page: a virtualized list of 5,000 rows
---------------------------------------------------------------------------

local ROWS

local function priceTooltip(row)
  return function(tt)
    tt:AddLine(" ")
    tt:AddDoubleLine("Demo price", UI.formatMoney(row.price, { colored = true }), 0.6, 0.63, 0.66, 1, 1, 1)
    tt:AddDoubleLine("Quantity", tostring(row.qty), 0.6, 0.63, 0.66, 1, 1, 1)
  end
end

local function itemName(r)
  return (C_Item.GetItemInfo(r.item)) or r.item
end

local function itemColumns(onInspect)
  return {
    {
      key = "item", title = "Item", flex = 1, sortValue = itemName,
      render = function(r) return UI.ItemCell { item = r.item, qty = r.qty, flex = 1, tooltip = priceTooltip(r) } end,
    },
    {
      key = "price", title = "Price", width = 110, align = "RIGHT",
      render = function(r) return UI.Money { value = r.price, compact = true, justify = "RIGHT" } end,
    },
    {
      key = "change", title = "Change", width = 64, align = "RIGHT",
      render = function(r)
        return UI.Text {
          text = (r.change > 0 and "+" or "") .. r.change .. "%",
          style = "mono",
          color = r.change > 0 and "up" or (r.change < 0 and "down" or "muted"),
          justify = "RIGHT",
        }
      end,
    },
    {
      key = "tag", title = "Tag", width = 72,
      sortValue = function(r) return r.tag and r.tag.text end,
      render = function(r) return r.tag and UI.Badge { text = r.tag.text, tone = r.tag.tone } or nil end,
    },
    {
      key = "actions", title = "", width = 72, sortable = false,
      render = function(r) return UI.Button { text = "Inspect", size = "sm", width = 72, onClick = function() onInspect(r) end } end,
    },
  }
end

local ItemsPage = UI.component("DemoItems", {
  init = function(ctx)
    ROWS = ROWS or buildRows(5000)
    ctx.state.stats = select(2, UI.stats())
    local function tick()
      ctx:setState({ stats = select(2, UI.stats()) })
      ctx:after(0.5, tick)
    end
    ctx:after(0.5, tick)
  end,
  render = function(props, ctx)
    local st = ctx.state.stats
    ctx.columns = ctx.columns or itemColumns(props.onInspect)
    return UI.VStack {
      gap = 0,
      UI.Table {
        flex = 1,
        columns = ctx.columns,
        items = ROWS,
        key = "id",
        rowHeight = 36,
        striped = true,
        selected = ctx.state.selected,
        onSelect = function(row, _, key)
          ctx:setState({ selected = key })
          if props.onSelectRow then props.onSelectRow(row) end
        end,
      },
      UI.Divider {},
      Flow {
        padding = { 10, 16 },
        gap = 24,
        rowGap = 4,
        UI.Text { text = UI.groupDigits(#ROWS) .. " rows \194\183 click a header to sort, a row to select", color = "muted" },
        UI.Text {
          text = string.format("regions: %d in use \194\183 %d pooled \194\183 %d created", st.active, st.pooled, st.created),
          style = "mono",
          color = "muted",
        },
      },
    }
  end,
})

---------------------------------------------------------------------------
-- Charts page
---------------------------------------------------------------------------

local SERIES = {
  { item = 12359, color = "gold" },
  { item = 14047, color = "info" },
  { item = 13468, color = "up" },
  { item = 12360, color = "warn" },
  { item = 13446, color = "down" },
  { item = 3858, color = "gold" },
  { item = 7078, color = "info" },
}

local CANDLE = 3 -- points per candle

local function timeLabel(i, minutes)
  local t = 12 * 60 + (i - 1) * minutes
  return string.format("%02d:%02d", math.floor(t / 60) % 24, t % 60)
end

local function series()
  local out = {}
  for i, s in ipairs(SERIES) do
    local start = rand(2000, 90000)
    local values = walk(60, start, math.floor(start / 14))
    local labels, candles, changes, candleLabels = {}, {}, {}, {}
    for k = 1, #values do labels[k] = timeLabel(k, 5) end
    for k = 1, #values, CANDLE do
      local o, h, l, c = values[k], values[k], values[k], values[math.min(k + CANDLE - 1, #values)]
      for j = k, math.min(k + CANDLE - 1, #values) do
        h, l = math.max(h, values[j]), math.min(l, values[j])
      end
      candles[#candles + 1] = { o = o, h = h, l = l, c = c }
      changes[#changes + 1] = c - o
      candleLabels[#candleLabels + 1] = timeLabel(k, 5)
    end
    local hi, lo = -math.huge, math.huge
    for _, v in ipairs(values) do
      hi, lo = math.max(hi, v), math.min(lo, v)
    end
    out[i] = {
      def = s, values = values, labels = labels, candles = candles, changes = changes,
      candleLabels = candleLabels, floor = math.floor(start * 0.9), hi = hi, lo = lo,
    }
  end
  return out
end

-- Chart props for a series in the current mode.
local function chartProps(d, mode, height)
  local p = { height = height, color = d.def.color, mode = mode }
  if mode == "candles" then
    p.candles, p.labels, p.reference = d.candles, d.candleLabels, d.floor
  elseif mode == "bars" then
    p.values, p.labels = d.changes, d.candleLabels
  else
    p.values, p.labels, p.reference = d.values, d.labels, d.floor
  end
  return p
end

local function legendFor(d, mode)
  local last = d.values[#d.values]
  if mode == "bars" then
    local up, down = 0, 0
    for _, c in ipairs(d.changes) do
      if c >= 0 then up = up + 1 else down = down + 1 end
    end
    return UI.Legend { items = {
      { label = "Change per 15m", color = d.def.color, shape = "line" },
      { label = "Up", value = tostring(up), color = d.def.color },
      { label = "Down", value = tostring(down), color = "down" },
    } }
  end
  return UI.Legend { items = {
    { label = "Last", value = UI.Money { value = last, short = true, style = "monoSmall" }, color = d.def.color, shape = "line" },
    { label = "Floor", value = UI.Money { value = d.floor, short = true, style = "monoSmall" }, shape = "dash" },
    { label = "High", value = UI.Money { value = d.hi, short = true, style = "monoSmall" }, color = "up" },
    { label = "Low", value = UI.Money { value = d.lo, short = true, style = "monoSmall" }, color = "down" },
  } }
end

local function changeBadge(d)
  local first, last = d.values[1], d.values[#d.values]
  local pct = math.floor((last - first) / first * 100 + 0.5)
  return UI.Badge { text = (pct > 0 and "+" or "") .. pct .. "%", tone = pct >= 0 and "up" or "down" }
end

local function ChartCard(d, mode, height, flex)
  return UI.VStack {
    flex = flex,
    gap = 8,
    padding = 12,
    surface = "card",
    Row { UI.ItemCell { item = d.def.item, flex = 1 }, changeBadge(d) },
    UI.Chart(chartProps(d, mode, height)),
    legendFor(d, mode),
  }
end

local MODES = { { "line", "Line" }, { "candles", "Candles" }, { "bars", "Bars" } }

local ChartsPage = UI.component("DemoCharts", {
  init = function(ctx)
    ctx.state.data = series()
    ctx.state.mode = "line"
  end,
  render = function(_, ctx)
    local data, mode = ctx.state.data, ctx.state.mode
    local modeButtons = {}
    for i, m in ipairs(MODES) do
      modeButtons[i] = UI.Button {
        text = m[2],
        size = "sm",
        variant = m[1] == mode and "primary" or "ghost",
        onClick = function() ctx:setState({ mode = m[1] }) end,
      }
    end
    local small = {}
    for i = 2, #data do small[#small + 1] = ChartCard(data[i], mode, 72, 1) end
    return UI.VStack {
      gap = 12,
      padding = 12,
      Row {
        UI.Text { text = "Hover a chart for the crosshair and readout.", color = "muted" },
        UI.Spacer {},
        UI.HStack { gap = 2, modeButtons },
        UI.Button { text = "Randomize", size = "sm", onClick = function() ctx:setState({ data = series() }) end },
      },
      ChartCard(data[1], mode, 200),
      Row { align = "stretch", gap = 12, small[1], small[2], small[3] },
      Row { align = "stretch", gap = 12, small[4], small[5], small[6] },
    }
  end,
})

---------------------------------------------------------------------------
-- Theme page
---------------------------------------------------------------------------

local SWATCH_GROUPS = {
  { "Surfaces", { "ground", "panel", "raised", "line" } },
  { "Text and accents", { "text", "muted", "gold", "info", "up", "down", "warn" } },
  { "Item quality", { "poor", "common", "uncommon", "rare", "epic", "legendary" } },
}

local function Swatch(token, theme)
  local c = theme[token]
  return UI.VStack {
    width = 96,
    gap = 6,
    align = "stretch",
    UI.HStack { height = 28, bg = token, border = "line", radius = "r4" },
    UI.Text { text = token, style = "strong" },
    UI.Text { text = c.hex, style = "mono", color = "muted" },
  }
end

local function SwatchCard(group, theme, flex)
  return Card(group[1], {
    flex = flex,
    Row { gap = 12, rowGap = 14, wrap = true, align = "start", UI.map(group[2], function(token) return Swatch(token, theme) end) },
  })
end

-- Buttons for a set of choices; the active one is primary.
local function Choices(list, active, onPick)
  local out = {}
  for i, c in ipairs(list) do
    out[i] = UI.Button {
      text = c.title,
      size = "sm",
      variant = c.name == active and "primary" or "secondary",
      onClick = function() onPick(c.name) end,
    }
  end
  return Flow { gap = 6, out }
end

local ThemePage = UI.component("DemoTheme", function(props, ctx)
  local theme = ctx.theme
  local windowChoices = { { name = "global", title = "Global" } }
  for _, t in ipairs(UI.listThemes()) do windowChoices[#windowChoices + 1] = t end
  return UI.VStack {
    gap = 12,
    padding = 12,
    Row {
      align = "stretch",
      gap = 12,
      SwatchCard(SWATCH_GROUPS[1], theme, 1),
      Card("Type", {
        flex = 1,
        gap = 8,
        UI.Text { text = "Display 28", style = "display" },
        UI.Text { text = "Title 18", style = "title" },
        UI.Text { text = "Body 13: the quick brown fox jumps over the lazy dog.", wrap = true },
        UI.Text { text = "Strong 13", style = "strong" },
        UI.Text { text = "Label 11", style = "label", color = "muted" },
        UI.Money { value = 12403456 },
      }),
      Card("Theme", {
        flex = 1,
        UI.Text { text = "Global theme", color = "muted", wrap = true },
        Choices(UI.listThemes(), UI.themeName, function(name) UI.setTheme(name) end),
        UI.Text { text = "This window only", color = "muted", wrap = true },
        Choices(windowChoices, props.windowTheme or "global", function(name)
          if props.onWindowTheme then props.onWindowTheme(name ~= "global" and name or nil) end
        end),
      }),
    },
    SwatchCard(SWATCH_GROUPS[2], theme),
    SwatchCard(SWATCH_GROUPS[3], theme),
  }
end)

---------------------------------------------------------------------------
-- Scroll page: content larger than its box in each direction
---------------------------------------------------------------------------

local ScrollPage = UI.component("DemoScroll", function()
  local rows = {}
  for i = 1, 30 do
    rows[i] = Row {
      height = 28,
      padding = { 0, 4 },
      UI.Text { text = "Row " .. i, width = 70 },
      UI.Money { value = i * 12345 },
      UI.Spacer {},
      UI.Badge { text = TAGS[(i % #TAGS) + 1].text, tone = TAGS[(i % #TAGS) + 1].tone },
    }
  end

  local chips = {}
  for i = 1, 24 do
    chips[i] = UI.Button { text = "Chip " .. i, size = "sm", width = 84 }
  end

  local grid = {}
  for r = 1, 14 do
    local cells = {}
    for c = 1, 10 do
      cells[c] = UI.HStack {
        width = 84,
        height = 28,
        padding = { 0, 8 },
        bg = (r + c) % 2 == 0 and "raised" or nil,
        UI.Text { text = string.char(64 + c) .. r, style = "mono", color = "muted" },
      }
    end
    grid[r] = UI.HStack { gap = 0, cells }
  end

  return UI.VStack {
    gap = 12,
    padding = 12,
    Row {
      align = "stretch",
      gap = 12,
      Card("Vertical: 30 rows", { flex = 1, UI.ScrollView { height = 200, gap = 0, rows } }),
      Card("Both ways (Shift+wheel: sideways)", {
        flex = 1,
        UI.ScrollView { height = 200, direction = "both", gap = 0, grid },
      }),
    },
    Card("Horizontal: 24 chips", { UI.ScrollView { height = 40, direction = "horizontal", gap = 8, align = "center", chips } }),
    UI.Text {
      text = "Window bodies scroll the same way when their content is taller than the window: shrink this window to try it.",
      color = "muted",
      wrap = true,
    },
  }
end)

---------------------------------------------------------------------------
-- App
---------------------------------------------------------------------------

local TABS = {
  { id = "controls", text = "Controls" },
  { id = "items", text = "Items", count = "5,000" },
  { id = "charts", text = "Charts" },
  { id = "theme", text = "Theme" },
  { id = "scroll", text = "Scroll" },
}

local mainFrame
local root, inspectorRoot

local Inspector = UI.component("DemoInspector", function(props)
  local r = props.row
  return UI.Window {
    title = "Inspect",
    theme = FxUIDevCharDB and FxUIDevCharDB.demoTheme,
    dock = props.dock,
    width = 300,
    height = 300,
    onClose = props.onClose,
    UI.VStack {
      gap = 14,
      padding = 16,
      UI.ItemCell { item = r.item, iconSize = 36, style = "title" },
      UI.Divider {},
      LabeledMoney("Price", r.price),
      LabeledMoney("Stack of 20", r.price * 20, { compact = true }),
      Row { UI.Text { text = "Change", color = "muted", width = 150 }, UI.Badge { text = r.change .. "%", tone = r.change >= 0 and "up" or "down" } },
      Row { UI.Text { text = "Quantity", color = "muted", width = 150 }, UI.Text { text = tostring(r.qty), style = "mono" } },
      UI.Text { text = "Docked to the right edge of the main window.", color = "muted", wrap = true },
    },
  }
end)

local function closeInspector()
  if inspectorRoot then
    inspectorRoot:unmount()
    inspectorRoot = nil
  end
end

local function inspect(row)
  local el = Inspector { row = row, dock = mainFrame, onClose = closeInspector }
  if inspectorRoot then
    inspectorRoot:update(el)
  else
    inspectorRoot = UI.mount(UIParent, el)
  end
end

local App = UI.component("DemoApp", {
  init = function(ctx)
    ctx.state.tab = FxUIDevCharDB.tab or "controls"
  end,
  render = function(props, ctx)
    local tab = ctx.state.tab
    local page
    if tab == "items" then
      page = ItemsPage {
        flex = 1,
        onInspect = inspect,
        onSelectRow = function(row) if inspectorRoot then inspect(row) end end,
      }
    elseif tab == "charts" then
      page = ChartsPage { flex = 1 }
    elseif tab == "theme" then
      page = ThemePage {
        flex = 1,
        windowTheme = FxUIDevCharDB.demoTheme,
        onWindowTheme = function(name)
          FxUIDevCharDB.demoTheme = name
          ctx:forceUpdate()
          if inspectorRoot then inspectorRoot:update() end
        end,
      }
    elseif tab == "scroll" then
      page = ScrollPage { flex = 1 }
    else
      page = ControlsPage { flex = 1 }
    end
    return UI.Window {
      title = "FxUI",
      theme = FxUIDevCharDB.demoTheme,
      width = 980,
      height = 660,
      minWidth = 760,
      minHeight = 520,
      saved = FxUIDevCharDB.window,
      ref = function(f) mainFrame = f end,
      onClose = props.onClose,
      status = { "1.0." .. UI.MINOR, "theme: " .. (FxUIDevCharDB.demoTheme or UI.themeName) },
      UI.TabBar {
        tabs = TABS,
        selected = tab,
        onSelect = function(id)
          FxUIDevCharDB.tab = id
          ctx:setState({ tab = id })
        end,
      },
      page,
    }
  end,
})

local open = false
local toggle

local function render()
  if not open then
    closeInspector()
    if root then
      root:unmount()
      root = nil
    end
    return
  end
  local el = App { onClose = function() toggle() end }
  if root then root:update(el) else root = UI.mount(UIParent, el) end
end

toggle = function()
  open = not open
  render()
  if ns.onDemoChanged then ns.onDemoChanged(open) end
end

-- For the dev window in Dev.lua.
ns.demo = {
  toggle = toggle,
  isOpen = function() return open end,
}

UI.registerCommand("demo", toggle, "open or close the component demo")

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    FxUIDevCharDB = FxUIDevCharDB or {}
    FxUIDevCharDB.window = FxUIDevCharDB.window or {}
    print("|cffE2B04AFxUI|r dev tools loaded: |cffE2B04A/fx demo|r, |cffE2B04A/fx dev|r.")
  elseif root then
    render()
  end
end)
