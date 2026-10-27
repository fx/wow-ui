-- Run with: mise run test   (or lua tests/run.lua from the repository root)
local W = dofile("tests/wow.lua")

local tests, failures = {}, 0

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function ok(v, msg)
  if not v then error(msg or "assertion failed", 2) end
end

W.loadAddon("FxUI", "FxUI")
-- The theme addons load after FxUI, as the client loads them.
W.loadAddon("FxUI_Theme_Teal", "FxUI_Theme_Teal")
W.loadAddon("FxUI_Theme_Classic", "FxUI_Theme_Classic")
local UI = LibStub("FxUI-1.0")
local I = UI._internal

local function walk(node, fn)
  if not node then return end
  fn(node)
  if node.child then walk(node.child, fn) end
  for _, list in ipairs({ node.children or {}, node.headerChildren or {}, node.footerChildren or {} }) do
    for _, c in ipairs(list) do walk(c, fn) end
  end
end

local function find(root, hostName, pred)
  local out = {}
  walk(root.node, function(n)
    if n.host and n.host.name == hostName and (not pred or pred(n)) then out[#out + 1] = n end
  end)
  return out
end

local function fx(msg)
  SlashCmdList.FXUI_COMMANDS(msg)
end

local function frameCount()
  return (W.created.Frame or 0) + (W.created.Button or 0) + (W.created.FontString or 0) + (W.created.Texture or 0)
end

---------------------------------------------------------------------------
-- Library
---------------------------------------------------------------------------

test("layout: wrapped text squeezed to zero width still has a finite height", function()
  local holder = CreateFrame("Frame", nil, UIParent)
  local fs = holder:CreateFontString(nil, "ARTWORK")
  I.setText(fs, "A long line of text that has to wrap somewhere", "body")
  fs:SetWordWrap(true)
  local _, h = I.measureString(fs, 0, true)
  ok(h < math.huge and h == h, "finite height, got " .. tostring(h))
end)

test("stub: integer formats overflow at 2^31 like the client", function()
  ok(not pcall(string.format, "%d", 2995914700), "%d past 2^31 raises")
  eq(string.format("%d", 2147483647), "2147483647")
  eq(string.format("%.0f", 2995914700), "2995914700")
end)

test("money: 123456 copper reads 12g 34s 56c", function()
  eq(UI.formatMoney(123456), "12g 34s 56c")
end)

test("money: compact drops silver and copper above 100g", function()
  eq(UI.formatMoney(12403456, { compact = true }), "1,240g")
  eq(UI.formatMoney(123456, { compact = true }), "12g 34s 56c")
end)

test("money: signed and negative values", function()
  eq(UI.formatMoney(-320), "\226\136\1463s 20c")
  eq(UI.formatMoney(1840, { signed = true }), "+18s 40c")
  eq(UI.formatMoney(0), "0c")
  eq(UI.formatMoney(500), "5s")
end)

test("money: short keeps the largest denomination with one decimal", function()
  local function short(v) return UI.formatMoney(v, { short = true }) end
  eq(short(74000), "7.4g")
  eq(short(70000), "7g", "no trailing .0")
  eq(short(1240000), "124g")
  eq(short(12403456), "1.2kg", "thousands of gold in k")
  eq(short(123456789), "12.3kg")
  eq(short(4523), "45s")
  eq(short(450), "4.5s")
  eq(short(56), "56c")
  eq(short(0), "0c")
  eq(short(-74000), "\226\136\1467.4g")
  eq(UI.formatMoney(74999, { short = true }), "7.4g", "rounds down, never overstates")
end)

test("theme: text, muted and quality colors reach 4.5:1 on panel", function()
  for _, token in ipairs({ "text", "muted", "poor", "common", "uncommon", "rare", "epic", "legendary" }) do
    ok(UI.contrast(token, "panel") >= 4.5, token .. " fails contrast: " .. UI.contrast(token, "panel"))
  end
end)

test("render: re-render keeps frames and updates only what changed", function()
  local host = CreateFrame("Frame")
  host:SetSize(400, 800)
  local Row = UI.component("TestRow", function(p)
    return UI.HStack { gap = 8, UI.Text { text = p.label }, UI.Spacer {}, UI.Money { value = p.value } }
  end)
  local function view(data)
    return UI.VStack { UI.map(data, function(d) return Row { key = d.id, label = d.label, value = d.value } end) }
  end
  local data = {}
  for i = 1, 20 do data[i] = { id = i, label = "Row " .. i, value = i * 100 } end
  local root = UI.mount(host, view(data))
  local before = frameCount()
  data[5] = { id = 5, label = "Changed", value = 500 }
  root:update(view(data))
  eq(frameCount(), before, "frames created on re-render")
  local texts = find(root, "Text")
  eq(texts[5].region:GetText(), "Changed")
  root:unmount()
end)

test("layout: a wrapping row flows children onto new lines inside its width", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 600)
  local kids = {}
  for i = 1, 7 do kids[i] = UI.HStack { width = 96, height = 40 } end
  local root = UI.mount(host, UI.VStack { align = "stretch", UI.HStack { wrap = true, gap = 12, rowGap = 8, kids } })
  local row = find(root, "HStack", function(n) return n.el.props.wrap end)[1]
  eq(row.h, 4 * 40 + 3 * 8, "four lines of two")
  for i, c in ipairs(row.children) do
    ok(c.x + c.w <= 300, "child " .. i .. " inside the row")
    eq(c.y, math.floor((i - 1) / 2) * 48, "child " .. i .. " line")
  end
  root:unmount()
end)

test("scroll: a window body scrolls when its content is taller; flex fills when it fits", function()
  local rows = {}
  for i = 1, 10 do rows[i] = UI.HStack { height = 40, UI.Text { text = "Row " .. i } } end
  local root = UI.mount(UIParent, UI.Window { title = "Tall", width = 300, height = 248, rows })
  local win = find(root, "Window")[1]
  local sc = win.region.body.fxScroller
  ok(win.scroll, "scrolls")
  eq(sc.maxY, 400 - 200, "scroll range = content - view")
  eq(sc.maxX, 0, "no horizontal scrolling in a window body")
  ok(sc.thumbY:IsShown() and not sc.thumbX:IsShown(), "vertical scrollbar only")
  win.region.body:_fire("OnMouseWheel", -1)
  eq(sc.offsetY, 48, "wheel scrolls")
  eq(sc.content._points[1][5], 48, "content moved, not re-laid out")
  for _ = 1, 20 do win.region.body:_fire("OnMouseWheel", -1) end
  eq(sc.offsetY, sc.maxY, "clamped at the end")
  root:unmount()

  local items = {}
  for i = 1, 50 do items[i] = { id = i } end
  root = UI.mount(UIParent, UI.Window { title = "Fits", width = 300, height = 448,
    UI.Text { text = "Header" },
    UI.List { flex = 1, items = items, key = "id", rowHeight = 20, render = function(it) return UI.Text { text = tostring(it.id) } end },
  })
  win = find(root, "Window")[1]
  ok(not win.scroll, "fits without scrolling")
  local list = find(root, "List")[1]
  ok(list.h > 300, "flex list fills the body: " .. tostring(list.h))
  root:unmount()
end)

test("scroll: a window scrolls when a flexible child's content is taller than the body", function()
  local Page = UI.component("TestTallPage", function()
    local rows = {}
    for i = 1, 12 do rows[i] = UI.HStack { height = 40 } end
    return UI.VStack { gap = 0, rows }
  end)
  local root = UI.mount(UIParent, UI.Window { title = "Tabs", width = 300, height = 348,
    UI.HStack { height = 40 },
    Page { flex = 1 },
  })
  local win = find(root, "Window")[1]
  ok(win.scroll, "scrolls although the page is flex")
  eq(win.region.body.fxScroller.maxY, 40 + 480 - 300, "range covers the page's content")
  root:unmount()
  root = UI.mount(UIParent, UI.Window { title = "Tabs", width = 300, height = 648,
    UI.HStack { height = 40 },
    Page { flex = 1 },
  })
  win = find(root, "Window")[1]
  ok(not win.scroll, "no scrolling when it fits")
  local page = find(root, "VStack")[1]
  eq(page.h, 600 - 40, "the flexible page still fills the body")
  root:unmount()
end)

test("scroll: ScrollView scrolls vertically, horizontally and both ways", function()
  local host = CreateFrame("Frame")
  host:SetSize(200, 100)
  local kids = {}
  for i = 1, 6 do kids[i] = UI.HStack { height = 30 } end
  local root = UI.mount(host, UI.ScrollView { gap = 0, kids })
  local sc = find(root, "ScrollView")[1].region.fxScroller
  eq(sc.maxY, 80, "vertical range")
  eq(sc.maxX, 0, "no horizontal range")
  root:unmount()

  local chips = {}
  for i = 1, 8 do chips[i] = UI.HStack { width = 50, height = 30 } end
  root = UI.mount(host, UI.ScrollView { direction = "horizontal", gap = 10, chips })
  local view = find(root, "ScrollView")[1]
  sc = view.region.fxScroller
  eq(sc.maxX, 8 * 50 + 7 * 10 - 200, "horizontal range")
  eq(sc.maxY, 0, "no vertical range")
  ok(sc.thumbX:IsShown() and not sc.thumbY:IsShown(), "horizontal scrollbar only")
  eq(view.children[2].x, 60, "children laid out in a row")
  view.region:_fire("OnMouseWheel", -1)
  eq(sc.offsetX, 48, "plain wheel scrolls horizontally when there is no vertical range")
  eq(sc.content._points[1][4], -48, "content moved left")
  root:unmount()

  local grid = {}
  for r = 1, 6 do
    local cells = {}
    for c = 1, 6 do cells[c] = UI.HStack { width = 60, height = 30 } end
    grid[r] = UI.HStack { gap = 0, cells }
  end
  root = UI.mount(host, UI.ScrollView { direction = "both", gap = 0, grid })
  view = find(root, "ScrollView")[1]
  sc = view.region.fxScroller
  eq(sc.maxX, 360 - 190, "both: horizontal range leaves room for the vertical bar")
  eq(sc.maxY, 180 - 90, "both: vertical range leaves room for the horizontal bar")
  view.region:_fire("OnMouseWheel", -1)
  eq(sc.offsetY, 48, "wheel scrolls vertically")
  W.shift = true
  view.region:_fire("OnMouseWheel", -1)
  W.shift = false
  eq(sc.offsetX, 48, "shift+wheel scrolls horizontally")
  root:unmount()
end)

test("render: released frames are pooled and reused", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 300)
  local el = UI.VStack { UI.Button { text = "A" }, UI.Badge { text = "B" }, UI.Text { text = "C" } }
  local root = UI.mount(host, el)
  root:unmount()
  local before = frameCount()
  root = UI.mount(host, el)
  eq(frameCount(), before, "frames created on remount")
  root:unmount()
end)

test("render: three state changes in one frame render once", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 300)
  local ctxRef
  local C = UI.component("TestBatch", {
    init = function(ctx) ctxRef = ctx; ctx.state.n = 0 end,
    render = function(_, ctx) return UI.Text { text = tostring(ctx.state.n) } end,
  })
  local root = UI.mount(host, C {})
  local node = root.node
  local renders = node.renders
  ctxRef:setState({ n = 1 })
  ctxRef:setState({ n = 2 })
  ctxRef:setState({ n = 3 })
  W.nextFrame()
  eq(node.renders - renders, 1, "renders")
  eq(find(root, "Text")[1].region:GetText(), "3")
  root:unmount()
end)

test("list: 5,000 items keep a constant number of row frames", function()
  local host = CreateFrame("Frame")
  host:SetSize(400, 540)
  local items = {}
  for i = 1, 5000 do items[i] = { id = i, text = "Item " .. i } end
  local root = UI.mount(host, UI.List {
    items = items, key = "id", rowHeight = 36,
    render = function(it) return UI.Text { text = it.text } end,
  })
  local list = find(root, "List")[1]
  local maxRows = 0
  for _ = 1, 1700 do
    list.region:_fire("OnMouseWheel", -1)
    if #list.children > maxRows then maxRows = #list.children end
  end
  ok(maxRows <= 540 / 36 + 6, "too many rows: " .. maxRows)
  eq(list.offset, 5000 * 36 - 540, "scrolled to end")
  eq(list.children[#list.children].el.key, 5000)
  root:unmount()
end)

test("table: header clicks sort ascending then descending, stable, empty last", function()
  local host = CreateFrame("Frame")
  host:SetSize(500, 400)
  local items = {
    { id = 1, name = "b", price = 30 },
    { id = 2, name = "a", price = 10 },
    { id = 3, name = "c" },
    { id = 4, name = "d", price = 10 },
  }
  local root = UI.mount(host, UI.Table {
    key = "id", items = items, rowHeight = 30,
    columns = { { key = "name", title = "Name", flex = 1 }, { key = "price", title = "Price", width = 80, align = "RIGHT" } },
  })
  local function order()
    local list = find(root, "List")[1]
    local out = {}
    for _, c in ipairs(list.children) do out[#out + 1] = c.el.key end
    return table.concat(out, ",")
  end
  local function header(text)
    return find(root, "HeaderCell", function(n) return n.el.props.text == text end)[1]
  end
  eq(order(), "1,2,3,4", "unsorted keeps item order")
  header("Price").region:_click()
  W.nextFrame()
  eq(order(), "2,4,1,3", "ascending, ties stable, empty last")
  eq(header("Price").el.props.sortDir, "asc")
  header("Price").region:_click()
  W.nextFrame()
  eq(order(), "1,2,4,3", "descending, empty still last")
  header("Name").region:_click()
  W.nextFrame()
  eq(order(), "2,1,3,4", "another column sorts ascending")
  eq(header("Price").el.props.sortDir, nil, "previous column cleared")
  root:unmount()
end)

test("table: controlled sort calls onSort", function()
  local host = CreateFrame("Frame")
  host:SetSize(400, 300)
  local got
  local root = UI.mount(host, UI.Table {
    items = { { v = 2 }, { v = 1 } }, sort = { key = "v", desc = true },
    onSort = function(key, desc) got = { key, desc } end,
    columns = { { key = "v", title = "V", flex = 1 } },
  })
  local list = find(root, "List")[1]
  eq(list.el.props.items[1].v, 2, "sorted by the controlled sort")
  find(root, "HeaderCell")[1].region:_click()
  ok(got and got[1] == "v" and got[2] == false, "onSort gets the toggled direction")
  root:unmount()
end)

test("list: hover highlight follows the cursor; clicks select the row", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(400, 300)
  local selected
  local items = {}
  for i = 1, 20 do items[i] = { id = i * 10 } end
  local function view(sel)
    return UI.List {
      items = items, key = "id", rowHeight = 30, selected = sel,
      onSelect = function(_, _, key) selected = key end,
      render = function(it) return UI.Text { text = tostring(it.id) } end,
    }
  end
  local root = UI.mount(host, view(nil))
  local list = find(root, "List")[1]
  local l, b, w, h = list.region:GetRect()
  W.cursorX, W.cursorY = l + 50, b + h - 75 -- third row
  W.nextFrame()
  eq(list.hover, 3, "hovered row")
  local bg = list.children[3].region.fxBg
  ok(bg and bg:IsShown(), "hovered row has a background")
  list.region:_fire("OnMouseDown", "LeftButton")
  eq(list.pressed, 3, "pressed state")
  list.region:_fire("OnMouseUp", "LeftButton")
  eq(selected, 30, "onSelect gets the row key")
  root:update(view(30))
  W.cursorX, W.cursorY = -100, -100
  W.nextFrame()
  eq(list.hover, nil, "hover cleared outside")
  ok(list.children[3].region.fxBg:IsShown(), "selected row keeps its background")
  ok(not (list.children[2].region.fxBg and list.children[2].region.fxBg:IsShown()), "other rows plain")
  root:unmount()
end)

test("chart: line, candles and bars draw and the crosshair reads the hovered point", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(300, 150)
  local values, labels = {}, {}
  for i = 1, 11 do values[i] = 1000 + i * 100; labels[i] = "t" .. i end
  local root = UI.mount(host, UI.Chart { values = values, labels = labels, reference = 1200 })
  local chart = find(root, "Chart")[1]
  local f = chart.region
  local g = chart.geo
  ok(g and g.n == 11, "geometry recorded")
  eq(#f.lines, 10, "line segments")
  local l, b = f:GetRect()
  W.cursorX, W.cursorY = l + g.xs[6] + 1, b + 60
  W.nextFrame()
  ok(f.cross:IsShown(), "crosshair shown on hover")
  eq(f.hoverIndex, 6, "snaps to the nearest point")
  local text = f.readout.text:GetText()
  ok(text:find("t6", 1, true) and text:find("16", 1, true), "readout shows label and value: " .. text)
  ok(f.hoverTag:IsShown() and f.lastTag:IsShown(), "price tags shown")
  W.cursorX, W.cursorY = -100, -100
  W.nextFrame()
  ok(not f.cross:IsShown(), "crosshair hidden when the mouse leaves")

  local candles = { { o = 10, h = 14, l = 9, c = 13 }, { o = 13, h = 13, l = 8, c = 9 } }
  root:update(UI.Chart { mode = "candles", candles = candles })
  g = chart.geo
  eq(#f.bodies, 2, "one body per candle")
  ok(f.bodies[1]._color[2] > f.bodies[1]._color[1], "rising candle in the up color")
  ok(f.bodies[2]._color[1] > f.bodies[2]._color[2], "falling candle in the down color")
  W.cursorX, W.cursorY = l + g.xs[2], b + 60
  W.nextFrame()
  ok(f.readout.text:GetText():find("O ", 1, true), "candle readout shows OHLC")

  -- A narrow chart falls back to a short readout that fits the plot.
  host:SetSize(130, 80)
  root:update(UI.Chart { mode = "candles", candles = candles, labels = { "12:00", "12:15" } })
  W.nextFrame()
  g = chart.geo
  l, b = f:GetRect()
  W.cursorX, W.cursorY = l + g.xs[1], b + 40
  W.nextFrame()
  ok(f.readout:GetWidth() <= g.right - g.left + 0.5, "readout fits the plot: " .. f.readout:GetWidth() .. " in " .. (g.right - g.left))
  ok(not f.readout.text:GetText():find("O ", 1, true), "short readout without OHLC")
  W.cursorX, W.cursorY = -100, -100
  W.nextFrame()
  host:SetSize(300, 150)

  root:update(UI.Chart { mode = "bars", values = { 5, -3, 8 } })
  g = chart.geo
  eq(f.bodies[3]:IsShown(), true, "three bars")
  ok(f.bodies[2]._color[1] > f.bodies[2]._color[2], "negative bar in the down color")
  ok(g.lo < 0 and g.hi > 8, "range covers the baseline and both signs")
  root:unmount()
end)

test("legend: compact chips wrap onto new lines in a narrow box", function()
  local host = CreateFrame("Frame")
  host:SetSize(140, 200)
  local items = {}
  for i = 1, 5 do items[i] = { label = "Series " .. i, value = i * 10, color = "gold" } end
  local root = UI.mount(host, UI.VStack { align = "stretch", UI.Legend { items = items } })
  local row = find(root, "HStack", function(n) return n.el.props.wrap end)[1]
  ok(row.h > 30, "wrapped onto several lines: " .. row.h)
  for _, c in ipairs(row.children) do ok(c.x + c.w <= 140.5, "chip inside the box") end
  root:unmount()
end)

test("button: secure handler runs in the click and is disabled in combat", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 100)
  local clicks = 0
  local root = UI.mount(host, UI.Button { text = "Go", secure = true, onClick = function() clicks = clicks + 1 end })
  local b = find(root, "Button")[1].region
  b:_click()
  eq(clicks, 1, "click outside combat")
  W.combat = true
  W.fireEvent("PLAYER_REGEN_DISABLED")
  eq(b:IsEnabled(), false, "disabled in combat")
  b:_click()
  b:_fire("OnClick", "LeftButton")
  eq(clicks, 1, "click in combat")
  W.combat = false
  W.fireEvent("PLAYER_REGEN_ENABLED")
  eq(b:IsEnabled(), true, "enabled after combat")
  root:unmount()
end)

test("theme: swapping restyles every mounted tree", function()
  local a, b = CreateFrame("Frame"), CreateFrame("Frame")
  a:SetSize(100, 100); b:SetSize(100, 100)
  local ra = UI.mount(a, UI.Text { text = "a", color = "gold" })
  local rb = UI.mount(b, UI.Text { text = "b", color = "gold" })
  UI.registerTheme("test", "default", { colors = { gold = "#00FF00" } })
  UI.setTheme("test")
  eq(find(ra, "Text")[1].region._color[2], 1)
  eq(find(rb, "Text")[1].region._color[2], 1)
  UI.setTheme("default")
  ra:unmount(); rb:unmount()
end)

test("commands: addons register /fx subcommands, /fx lists them", function()
  local got
  UI.registerCommand("Echo", function(args) got = args end, "test command")
  fx("echo  hello world ")
  eq(got, "hello world", "args passed trimmed")
  fx("ECHO x")
  eq(got, "x", "names are case-insensitive")
  local printed = {}
  local realPrint = print
  print = function(s) printed[#printed + 1] = s end
  fx("")
  fx("nope")
  print = realPrint
  local all = table.concat(printed, "\n")
  ok(all:find("/fx echo", 1, true), "help lists the command:\n" .. all)
  ok(all:find("no command 'nope'", 1, true), "unknown command reported")
  UI.unregisterCommand("echo")
end)

test("themes: inheritance, per-tree and per-element themes, unregistered tables", function()
  UI.registerTheme({ name = "t-base", base = "default", colors = { gold = "#112233" }, metrics = { Tab = { height = 40, pad = 9 } } })
  UI.registerTheme({ name = "t-child", base = "t-base", colors = { info = "#445566" }, metrics = { Tab = { pad = 5 } } })
  local child = I.resolve("t-child")
  eq(child.gold.hex, "#112233", "inherits overridden colors from its base")
  eq(child.info.hex, "#445566", "own colors")
  eq(child.text.hex, I.resolve("default").text.hex, "inherits the rest from default")
  eq(child.metrics.Tab.height, 40, "metrics merge per component")
  eq(child.metrics.Tab.pad, 5)

  local a, b = CreateFrame("Frame"), CreateFrame("Frame")
  a:SetSize(100, 100); b:SetSize(100, 100)
  local ra = UI.mount(a, UI.Text { text = "a", color = "gold" })
  local rb = UI.mount(b, UI.VStack {
    UI.Text { text = "b", color = "gold" },
    UI.Text { text = "c", color = "gold", theme = { name = "inline", colors = { gold = "#00FF00" } } },
  }, { theme = "t-base" })
  eq(find(ra, "Text")[1].region._color[1], I.resolve("default").gold.r, "global theme")
  local texts = find(rb, "Text")
  eq(texts[1].region._color[3], I.resolve("t-base").gold.b, "mount theme")
  eq(texts[2].region._color[2], 1, "element theme, unregistered table")
  ra:unmount(); rb:unmount()

  local before = #W.errors
  local r = UI.mount(a, UI.Text { text = "x", theme = "no-such-theme" })
  ok(#W.errors == before + 1 and W.errors[#W.errors]:find("unknown theme", 1, true), "unknown theme reported")
  UI.mount(b, UI.Text { text = "y", theme = "no-such-theme" }):unmount()
  eq(#W.errors, before + 1, "reported once")
  W.errors = {}
  r:unmount()
end)

test("tabs: one width in every state", function()
  local host = CreateFrame("Frame")
  host:SetSize(400, 60)
  local function view(sel)
    return UI.TabBar { tabs = { { id = "a", text = "Alpha" }, { id = "b", text = "Beta" } }, selected = sel }
  end
  local root = UI.mount(host, view("a"))
  local wA = find(root, "Tab")[1].w
  root:update(view("b"))
  eq(find(root, "Tab")[1].w, wA, "a tab keeps its width when deselected")
  root:unmount()
end)

test("tabs: clicks select, counts show, the line marks the selected tab", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(400, 60)
  local picked
  local root = UI.mount(host, UI.TabBar {
    tabs = { { id = "a", text = "Alpha" }, { id = "b", text = "Beta", count = 3 } },
    selected = "a", onSelect = function(id) picked = id end,
  })
  local tabs = find(root, "Tab")
  tabs[2].region:_click()
  eq(picked, "b", "onSelect gets the tab id")
  ok(tabs[2].region.count:IsShown() and tabs[2].region.count:GetText() == "3", "count shown")
  ok(not tabs[1].region.count:IsShown(), "no count without one")
  tabs[2].region:_fire("OnEnter")
  eq(tabs[2].region.label._color[1], I.resolve("default").text.r, "hover shows in the text color")
  tabs[2].region:_fire("OnLeave")
  eq(tabs[2].region.label._color[1], I.resolve("default").muted.r, "muted again")
  local rail = find(root, "TabRail")[1]
  ok(rail.region.mark:IsShown(), "the selected tab is marked on the line")
  eq(rail.region.mark._w, tabs[1].w, "mark as wide as the tab")
  root:unmount()
end)

test("window: status and actions go where the theme puts them; no forced footer", function()
  UI.registerTheme({ name = "t-footer", base = "default",
    metrics = { Window = { status = "footer", actions = "footer", md = { inset = 10 } } } })
  local clicked
  local function view(theme, status)
    return UI.Window { title = "Acts", width = 400, height = 300, theme = theme,
      actions = { { text = "Do", onClick = function() clicked = true end } },
      status = status or "status",
      UI.Text { text = "body" },
    }
  end
  local root = UI.mount(UIParent, view(nil))
  local win = find(root, "Window")[1]
  local function textsIn(list)
    local out = {}
    for _, n in ipairs(list or {}) do if n.el.props.text then out[#out + 1] = n.el.props.text end end
    return table.concat(out, ",")
  end
  eq(textsIn(win.headerChildren), "status,Do", "default theme: status and actions in the header")
  eq(textsIn(win.footerChildren), "", "nothing in the footer")
  ok(not win.region.footer:IsShown(), "no footer unless something lands in it")
  local doButton = find(root, "Button", function(n) return n.el.props.text == "Do" end)[1]
  eq(doButton.el.props.variant, "ghost", "header actions are ghost buttons")
  doButton.region:_click()
  ok(clicked, "action runs")

  root:update(view("t-footer", { UI.Badge { text = "v1" }, "3 items" }))
  win = find(root, "Window")[1]
  eq(textsIn(win.headerChildren), "", "footer theme: header keeps only the title and close")
  eq(textsIn(win.footerChildren), "v1,3 items,Do", "status elements and text, then actions, in the footer")
  ok(win.region.footer:IsShown(), "footer shown")
  local _, _, fw = win.region.footer:GetRect()
  local _, _, ww = win.region:GetRect()
  eq(fw, ww - 2 * 10, "footer spans the full width inside the border")
  doButton = find(root, "Button", function(n) return n.el.props.text == "Do" end)[1]
  eq(doButton.el.props.variant, "secondary", "footer actions are secondary buttons")
  root:unmount()

  root = UI.mount(UIParent, UI.Window { title = "F", width = 300, height = 200, footer = { UI.Text { text = "own footer" } } })
  ok(find(root, "Window")[1].region.footer:IsShown(), "an explicit footer shows")
  root:unmount()
  root = UI.mount(UIParent, UI.Window { title = "F", width = 300, height = 200, theme = "t-footer",
    footer = { UI.Text { text = "own footer" } } })
  ok(find(root, "Window")[1].region.footer:IsShown(), "in any theme")
  root:unmount()
end)

test("window: docked windows sit beside their dock; free ones save their geometry; close", function()
  local main = CreateFrame("Frame", nil, UIParent)
  main:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
  main:SetSize(300, 200)
  local root = UI.mount(UIParent, UI.Window { title = "Docked", width = 300, height = 200, dock = main })
  local f = find(root, "Window")[1].region
  eq(f:GetLeft(), main:GetRight() + 8, "8 px right of the dock")
  eq(f:GetTop(), main:GetTop(), "top aligned")
  ok(not f.grip:IsShown(), "no resize grip")
  local moved = false
  f.StartMoving = function() moved = true end
  f.header:_fire("OnDragStart")
  ok(not moved, "the header does not drag a docked window")
  root:update(UI.Window { title = "Docked", width = 300, height = 200, dock = main, dockSide = "left", dockGap = 4 })
  eq(f:GetRight(), main:GetLeft() - 4, "docked on the left")
  f.StartMoving = nil
  root:unmount()

  local saved = {}
  local closed = false
  root = UI.mount(UIParent, UI.Window { title = "Free", width = 320, height = 240, saved = saved,
    onClose = function() closed = true end })
  local node = find(root, "Window")[1]
  f = node.region
  ok(f.grip:IsShown(), "free windows have a resize grip")
  f.StartMoving = function() moved = true end
  f.header:_fire("OnDragStart")
  ok(moved, "the header drags a free window")
  f.header:_fire("OnDragStop")
  eq(saved.x, f:GetLeft(), "position saved after a drag")
  eq(saved.w, 320, "size saved")
  eq(saved.scale, 1, "with the scale")
  f.grip:_fire("OnMouseDown", "LeftButton")
  f:SetSize(400, 260)
  f.grip:_fire("OnMouseUp", "LeftButton")
  eq(saved.w, 400, "new size saved after resizing")
  f.close:_fire("OnEnter")
  f.close:_fire("OnLeave")
  f.close:_click()
  ok(closed, "onClose runs instead of hiding")
  f.StartMoving = nil
  root:unmount()

  root = UI.mount(UIParent, UI.Window { title = "Again", saved = saved })
  f = find(root, "Window")[1].region
  eq(f:GetWidth(), 400, "reopens at the saved size")
  eq(f:GetLeft(), saved.x, "and the saved spot")
  f.close:_click()
  ok(not f:IsShown(), "without onClose the close button hides the window")
  root:unmount()
end)

test("themes: Options dropdown lists themes, sets and saves the global theme", function()
  local setting = W.settings.settings.FXUI_THEME
  ok(setting and setting.dropdown, "theme dropdown registered")
  UI.registerTheme({ name = "t-opt", title = "Test Theme", base = "default", colors = { gold = "#00FF00" } })
  local names = {}
  for _, o in ipairs(setting.dropdown()) do names[o.value] = o.label end
  eq(names.default, "FxUI Dark")
  eq(names["t-opt"], "Test Theme", "registered themes are listed")
  setting:SetValue("t-opt")
  eq(UI.themeName, "t-opt")
  eq(FxUIDB.theme, "t-opt", "saved")
  UI.themeName = "default"
  I.global = I.resolve("default")
  W.fireEvent("PLAYER_LOGIN")
  eq(UI.themeName, "t-opt", "saved theme applied at login")

  -- A theme from an addon that registers it after login.
  setting:SetValue("t-late")
  eq(UI.themeName, "t-opt", "a theme that is not registered yet is not applied")
  W.loggedIn = true
  UI.registerTheme({ name = "t-late", base = "default" })
  eq(UI.themeName, "t-late", "applied as soon as it registers")
  W.loggedIn = false
  setting:SetValue("default")
  eq(UI.themeName, "default")
  eq(FxUIDB.theme, "default")
end)

test("themes: a skinned theme draws every component; pooled regions are clean afterwards", function()
  local K = UI.skinKit
  local painted = {}
  local function mark(name) return function(f) painted[name] = (painted[name] or 0) + 1; K.texture(f, name):SetColorTexture(K.color("gold")) end end
  UI.registerTheme({ name = "t-skin", base = "default",
    fonts = { body = { path = "Fonts\\FRIZQT__.TTF", size = 12, shadow = true } },
    surfaces = { card = { backdrop = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" }, bgColor = "#000000B3", borderColor = "#808080" } },
    metrics = { Meter = { barHeight = 12, inlineValue = true }, Tab = { railHighlight = true, openSelected = true, railAbove = true } },
    skins = {
      Button = { paint = mark("Button") },
      Badge = { paint = mark("Badge") },
      Toggle = { paint = mark("Toggle") },
      Slider = { paint = mark("Slider") },
      Help = { paint = mark("Help") },
      Tab = { paint = mark("Tab"), paintRail = mark("TabRail"), railGap = function(b) return b:GetLeft(), b:GetRight() end },
      ItemCell = { paintIcon = mark("ItemCell") },
      Meter = { paint = mark("Meter") },
      Chart = { tag = mark("Chart") },
      List = { paintRow = function(row, state) if state then mark("List")(row) end end },
      HeaderCell = { paint = mark("HeaderCell") },
      Scroll = { paintThumb = mark("Scroll") },
      Window = { paint = mark("Window"), paintClose = mark("WindowClose"), paintFooter = mark("WindowFooter") },
    },
  })
  W.items[17] = true
  local items = { { id = 1, v = "a" }, { id = 2, v = "b" } }
  local function view(theme)
    return UI.Window { title = "Skinned", width = 500, height = 600, theme = theme, status = "s", footer = { UI.Text { text = "f" } },
      UI.HStack { gap = 4, UI.Button { text = "Go" }, UI.Badge { text = "B" }, UI.Toggle { label = "On", checked = true } },
      UI.Slider { label = "Level", min = 0, max = 10, value = 3 },
      UI.Help { text = "Explains" },
      UI.TabBar { tabs = { { id = "x", text = "One" }, { id = "y", text = "Two" } }, selected = "x" },
      UI.ItemCell { item = 17 },
      UI.Meter { value = 5, max = 10, label = "Fill", valueText = "5/10" },
      UI.VStack { surface = "card", UI.Text { text = "card" } },
      UI.Chart { width = 200, height = 100, values = { 1, 2, 3 } },
      UI.Table { height = 120, items = items, key = "id", selected = 2, onSelect = function() end,
        columns = { { key = "v", title = "Value", flex = 1 } } },
    }
  end
  local root = UI.mount(UIParent, view("t-skin"))
  for _, name in ipairs({ "Button", "Badge", "Toggle", "Slider", "Help", "Tab", "TabRail", "ItemCell", "Meter", "Chart", "List", "HeaderCell", "Scroll", "Window", "WindowClose", "WindowFooter" }) do
    ok(painted[name], name .. " painted by the skin")
  end
  local card = find(root, "VStack", function(n) return n.el.props.surface == "card" end)[1].region
  ok(card.fxHasBackdrop and card._backdrop.bgFile, "surface role drawn as a backdrop")
  local text = find(root, "Text", function(n) return n.el.props.text == "card" end)[1].region
  eq(text:GetFont(), "Fonts\\FRIZQT__.TTF", "theme font applied")
  local button = find(root, "Button")[1].region
  ok(button.fxSkinTex.Button:IsShown(), "skin texture shown")
  root:unmount()

  root = UI.mount(UIParent, view(nil))
  button = find(root, "Button")[1].region
  ok(not button.fxSkinTex.Button:IsShown(), "pooled button: skin texture hidden under the default theme")
  ok(button.fxBg and button.fxBg:IsShown(), "default background back")
  local toggle = find(root, "Toggle")[1].region
  ok(not toggle.fxSkinTex.Toggle:IsShown() and toggle.track:IsShown(), "default toggle track back")
  local help = find(root, "Help")[1].region
  ok(not help.fxSkinTex.Help:IsShown() and help.circle:IsShown() and help.mark:IsShown(), "default help back")
  local slider = find(root, "Slider")[1].region
  ok(not slider.fxSkinTex.Slider:IsShown() and slider.track:IsShown() and slider.knob:IsShown(), "default slider track back")
  card = find(root, "VStack", function(n) return n.el.props.surface == "card" end)[1].region
  ok(not card.fxHasBackdrop and card.fxBg:IsShown(), "default card surface back")
  local win = find(root, "Window")[1].region
  ok(not win.fxSkinTex.Window:IsShown() and win.headerLine:IsShown(), "default window chrome back")
  root:unmount()
  W.items[17] = nil
end)

test("themes: a window scroller paints with the window's own theme, also after an update and when pooled", function()
  local log = {}
  local function skinOf(tag) return { Scroll = { paintThumb = function() log[#log + 1] = tag end } } end
  UI.registerTheme({ name = "t-sc-a", base = "default", skins = skinOf("A") })
  UI.registerTheme({ name = "t-sc-b", base = "default", skins = skinOf("B") })
  local rows = {}
  for i = 1, 10 do rows[i] = UI.HStack { height = 40, UI.Text { text = "Row " .. i } } end
  local function view(theme) return UI.Window { title = "Tall", width = 300, height = 248, theme = theme, rows } end
  local function only(tag, what)
    ok(#log > 0, what .. ": thumbs painted")
    for _, t in ipairs(log) do eq(t, tag, what) end
    log = {}
  end
  local root = UI.mount(UIParent, view("t-sc-a"))
  only("A", "mounted under A")
  root:update(view("t-sc-b"))
  only("B", "updated from A to B paints only B's skin")
  root:unmount()
  log = {}
  root = UI.mount(UIParent, view("t-sc-a"))
  log = {}
  root:unmount()
  root = UI.mount(UIParent, view("t-sc-b"))
  only("B", "pooled window reused under B")
  root:unmount()
end)

test("themes: textureExists probes client art and caches the answer", function()
  W.missingFiles = { ["Interface\\Missing\\Art"] = true }
  I.wipe(I.textureCache)
  ok(UI.skinKit.textureExists("Interface\\Buttons\\UI-Panel-Button-Up"), "a shipped file exists")
  ok(not UI.skinKit.textureExists("Interface\\Missing\\Art"), "a missing file does not")
  W.missingFiles = nil
  ok(not UI.textureExists("Interface\\Missing\\Art"), "the answer is cached")
  I.wipe(I.textureCache)
end)

test("theme: tokens follow the active theme; unknown tokens are errors", function()
  local host = CreateFrame("Frame")
  host:SetSize(200, 50)
  local root = UI.mount(host, UI.Text { text = "label", color = "muted" })
  UI.registerTheme({ name = "t-muted", base = "default", colors = { muted = "#123456" } })
  UI.setTheme("t-muted")
  local fs = find(root, "Text")[1].region
  ok(math.abs(fs._color[1] - 0x12 / 255) < 0.001, "label takes the new theme's muted")
  UI.setTheme("default")
  ok(math.abs(fs._color[1] - I.resolve("default").muted.r) < 0.001, "and back")
  root:unmount()
  ok(not pcall(UI.font, "no-such-font"), "unknown font token raises")
  ok(not pcall(I.rgba, "no-such-color"), "unknown color token raises")
  ok(UI.fontSpec("body"), "font spec for a token")
  local q = UI.qualityColor(7)
  ok(q and q.r, "qualities without a token use the client's color")
  ok(UI.qualityColor(nil).r, "no quality reads as common")
end)

test("money: tone colors the amount", function()
  local host = CreateFrame("Frame")
  host:SetSize(200, 50)
  local root = UI.mount(host, UI.Money { value = -320, tone = "down" })
  local fs = find(root, "Money")[1].region
  ok(fs:GetText():find("3", 1, true) and fs:GetText():find("20", 1, true), "reads the amount: " .. fs:GetText())
  eq(fs._color[1], I.resolve("default").down.r, "in the down color")
  eq(UI.formatMoney(1840, { signed = true }), "+18s 40c")
  root:unmount()
end)

test("item cell: shows a placeholder, then the item when it loads; tooltip and clicks", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(400, 40)
  local clicked
  local root = UI.mount(host, UI.HStack { UI.ItemCell { item = 4242, qty = 5, placeholder = "?", tooltip = function(tt, id) tt.fxExtra = id end,
    onClick = function(_, id) clicked = id end } })
  local cell = find(root, "ItemCell")[1]
  local f = cell.region
  eq(f.name:GetText(), "?", "placeholder until the item loads")
  eq(f.extra:GetText(), "\195\1515", "quantity")
  local w0 = cell.w
  W.loadItems()
  W.nextFrame()
  eq(f.name:GetText(), "Item 4242", "name once loaded")
  local color = UI.qualityColor(4242 % 6)
  eq(f.name._color[1], color.r, "in its quality color")
  ok(cell.w ~= w0, "layout updated")
  f:_fire("OnEnter")
  ok(GameTooltip:IsOwned(f), "tooltip shown")
  eq(GameTooltip.fxExtra, 4242, "consumer tooltip lines added")
  f:_fire("OnLeave")
  ok(not GameTooltip:IsOwned(f), "tooltip hidden")
  f:_fire("OnClick", "LeftButton")
  eq(clicked, 4242, "onClick gets the item ID")
  clicked = nil
  local realModified = IsModifiedClick
  IsModifiedClick = function() return true end
  f:_fire("OnClick", "LeftButton")
  IsModifiedClick = realModified
  eq(clicked, nil, "a modified click links the item into chat instead")
  root:update(UI.HStack { UI.ItemCell { item = "|cffffffff|Hitem:4242::|h[Item 4242]|h|r", showLevel = true } })
  eq(f.extra:GetText(), "ilvl 10", "item level")
  root:update(UI.HStack { UI.ItemCell { item = "4243", note = "note", iconSize = 16 } })
  W.loadItems()
  eq(f.extra:GetText(), "note", "note")
  root:update(UI.HStack { UI.ItemCell { placeholder = "Pick an item" } })
  eq(f.name:GetText(), "Pick an item", "no item: placeholder")
  root:unmount()
  W.items[4242], W.items[4243] = nil, nil
end)

test("meter and sparkline: fill, labels, lines and the reference", function()
  local host = CreateFrame("Frame")
  host:SetSize(200, 120)
  local root = UI.mount(host, UI.VStack { align = "stretch",
    UI.Meter { value = 3, max = 4, label = "Bags", valueText = "3/4", tone = "up" },
    UI.Meter { value = 0, max = 0 },
    UI.Sparkline { values = { 1, 3, 2, 5 }, reference = 6 },
    UI.Sparkline { values = { 2, 2, 2 } },
    UI.Sparkline { values = { 1 } },
  })
  local meters = find(root, "Meter")
  local m = meters[1]
  ok(m.region.label:IsShown() and m.region.value:IsShown(), "label and value above the bar")
  eq(m.region.fill:GetWidth(), 200 * 3 / 4, "fill follows value / max")
  ok(not meters[2].region.fill:IsShown(), "empty meter has no fill")
  eq(meters[2].h, 8, "no header without a label")
  local sparks = find(root, "Sparkline")
  local s = sparks[1].region
  eq(#s.lines, 3, "a segment between each pair of values")
  ok(#s.dashes > 0 and s.dashes[1]:IsShown(), "dashed reference line")
  ok(s.dot:IsShown(), "dot on the last value")
  ok(sparks[2].region.dot:IsShown(), "flat values still draw")
  ok(not sparks[3].region.dot:IsShown(), "one value draws nothing")
  root:update(UI.VStack { align = "stretch",
    UI.Meter { value = 3, max = 4, label = "Bags", valueText = "3/4", tone = "up" },
    UI.Meter { value = 0, max = 0 },
    UI.Sparkline { values = { 1, 2 } },
  })
  ok(s.lines[1]:IsShown() and not s.lines[2]:IsShown() and not s.dashes[1]:IsShown(), "unused segments hidden")
  root:unmount()
end)

-- A slider that keeps the value it is given, like a consumer would.
local function sliderView(props)
  return UI.component("SliderHost", {
    init = function(ctx) ctx.state.value = props.value end,
    render = function(_, ctx)
      local p = {}
      for k, v in pairs(props) do p[k] = v end
      p.value = ctx.state.value
      p.onChange = function(v)
        props.changes[#props.changes + 1] = v
        ctx:setState({ value = v })
      end
      return UI.HStack { width = 300, p.slider ~= false and UI.Slider(p) or nil }
    end,
  })
end

test("slider: stops, press and drag, wheel, value text room, disabled", function()
  local changes = {}
  local money = function(v) return v .. "g" end
  local root = UI.mount(UIParent, sliderView({ label = "Min", values = { 0, 1, 5, 10, 50, 100 }, value = 5, format = money,
    tooltip = "Hide below", changes = changes }) {})
  UI.flush()
  local node = find(root, "Slider")[1]
  local f = node.region
  eq(f.valueText:GetText(), "5g", "the value, formatted")
  eq(f.label:GetText(), "Min")
  local left, tw = f.track:GetLeft(), f.track:GetWidth()
  ok(tw > 0, "a track")
  -- The knob sits at the stop's share of the track: 5 is stop 3 of 6.
  local kl, _, kw = f.knob:GetRect()
  eq(kl + kw / 2, left + tw * 2 / 5, "knob at 2/5")
  -- Room for the widest value whatever is shown.
  local wide = f.valueText:GetWidth()
  -- Press at the left end: the first stop; drag past the right end: the last.
  local scale = f:GetEffectiveScale()
  W.cursorX, W.cursorY = (left - 20) * scale, 0
  f:_fire("OnEnter")
  ok(UI.tooltipOwner() == f, "its tooltip")
  f:_fire("OnMouseDown", "LeftButton")
  UI.flush()
  eq(changes[#changes], 0, "pressed at the start")
  W.cursorX = (left + tw + 50) * scale
  f:GetScript("OnUpdate")(f, 0.016)
  UI.flush()
  eq(changes[#changes], 100, "dragged to the end")
  local n = #changes
  f:GetScript("OnUpdate")(f, 0.016)
  eq(#changes, n, "no change while the stop stays")
  W.cursorX = (left + tw * 0.62) * scale
  f:GetScript("OnUpdate")(f, 0.016)
  UI.flush()
  eq(changes[#changes], 10, "the nearest stop under the cursor")
  f:_fire("OnMouseUp")
  eq(f:GetScript("OnUpdate"), nil, "drag ends on release")
  f:_fire("OnLeave")
  ok(UI.tooltipOwner() ~= f, "tooltip hidden")
  eq(f.valueText:GetWidth(), wide, "the value's room does not change")
  -- The wheel steps one stop, and stops at the ends.
  f:_fire("OnMouseWheel", 1)
  UI.flush()
  eq(changes[#changes], 50)
  f:_fire("OnMouseWheel", -1)
  UI.flush()
  eq(changes[#changes], 10)
  n = #changes
  f:_fire("OnMouseDown", "RightButton")
  eq(#changes, n, "right button ignored")
  root:unmount()

  -- min, max and step; disabled.
  changes = {}
  root = UI.mount(UIParent, sliderView({ min = 0, max = 1, step = 0.25, value = 0.6, disabled = true, changes = changes }) {})
  UI.flush()
  f = find(root, "Slider")[1].region
  eq(#f.fxStops, 5, "0 to 1 by 0.25")
  eq(f.valueText:GetText(), "0.5", "the nearest stop")
  eq(f:GetAlpha(), 0.5, "disabled dimmed")
  f:_fire("OnMouseDown", "LeftButton")
  f:_fire("OnMouseWheel", 1)
  eq(#changes, 0, "disabled ignores the mouse")
  ok(not f.label:IsShown(), "no label")
  root:unmount()

  -- A range of many stops measures its ends only; a bad step is 1; a
  -- maximum below the minimum is the minimum.
  changes = {}
  root = UI.mount(UIParent, sliderView({ min = 0, max = 5000, step = 0, value = 9999, changes = changes }) {})
  UI.flush()
  f = find(root, "Slider")[1].region
  ok(#f.fxStops <= 1000, "at most 1,000 stops: " .. #f.fxStops)
  eq(f.fxStops[2], 6, "the step grows to a whole multiple of the step")
  eq(f.fxStops[#f.fxStops], 5000, "ending at the maximum")
  eq(f.valueText:GetText(), "5000")
  root:unmount()
  root = UI.mount(UIParent, UI.Slider { min = 0, max = 999, value = 0, width = 200, height = 20 })
  eq(#find(root, "Slider")[1].region.fxStops, 1000, "exactly 1,000 stops keep the step")
  root:unmount()
  root = UI.mount(UIParent, UI.Slider { min = 3, max = 1, value = 3, width = 200, height = 20 })
  UI.flush()
  f = find(root, "Slider")[1].region
  eq(#f.fxStops, 1)
  ok(f.track:GetWidth() > 0, "laid out at a size given in full")
  f:_fire("OnMouseDown", "LeftButton")
  f:_fire("OnMouseUp")
  root:unmount()
  W.cursorX, W.cursorY = -100, -100
end)

test("slider: a drag notifies once per stop, ends on the left button, stops when disabled; release hides its tooltip", function()
  local changes = {}
  -- A consumer that does not take the value (yet): the slider keeps drawing 5.
  local function view(disabled)
    return UI.HStack { width = 300, UI.Slider { values = { 0, 1, 5, 10, 50, 100 }, value = 5, disabled = disabled,
      tooltip = "Explains", onChange = function(v) changes[#changes + 1] = v end } }
  end
  local root = UI.mount(UIParent, view(false))
  UI.flush()
  local f = find(root, "Slider")[1].region
  local left, tw = f.track:GetLeft(), f.track:GetWidth()
  local scale = f:GetEffectiveScale()
  W.cursorX, W.cursorY = (left + tw * 2 / 5) * scale, 0
  f:_fire("OnMouseDown", "LeftButton")
  eq(#changes, 0, "pressed on the stop it shows")
  W.cursorX = (left + tw + 50) * scale
  local drag = f:GetScript("OnUpdate")
  drag(f, 0.016)
  drag(f, 0.016)
  drag(f, 0.016)
  eq(#changes, 1, "once for the new stop, though the value stays 5")
  eq(changes[1], 100)
  W.cursorX = (left - 50) * scale
  drag(f, 0.016)
  drag(f, 0.016)
  eq(#changes, 2, "once for the next stop")
  eq(changes[2], 0)
  -- The wheel during a drag steps from the shown stop and leaves the drag's
  -- own tracking alone.
  W.cursorX = (left + tw / 5) * scale
  drag(f, 0.016)
  eq(changes[#changes], 1, "dragged to 1")
  local n = #changes
  f:_fire("OnMouseWheel", -1)
  eq(#changes, n + 1, "wheel down from the shown 5, though the drag is at 1")
  eq(changes[#changes], 1)
  f:_fire("OnMouseWheel", 1)
  eq(changes[#changes], 10, "wheel up from the shown 5")
  n = #changes
  drag(f, 0.016)
  drag(f, 0.016)
  eq(#changes, n, "the drag still knows it reached 1")
  -- Another button's release does not end the drag; the left button's does.
  f:_fire("OnMouseUp", "RightButton")
  ok(f:GetScript("OnUpdate") ~= nil, "still dragging after a right-button release")
  f:_fire("OnMouseUp", "LeftButton")
  eq(f:GetScript("OnUpdate"), nil, "the left button's release ends it")
  -- Disabled mid-drag: the drag stops and the slider no longer reports.
  f:_fire("OnMouseDown", "LeftButton")
  drag = f:GetScript("OnUpdate")
  ok(drag ~= nil, "dragging again")
  n = #changes
  root:update(view(true))
  eq(f:GetScript("OnUpdate"), nil, "turned off mid-drag, the drag ends")
  W.cursorX = (left + tw + 50) * scale
  drag(f, 0.016)
  eq(#changes, n, "a disabled slider does not report")
  ok(not f.fxDrag, "not dragging")
  -- Unmounting a hovered slider hides its tooltip.
  root:update(view(false))
  f:_fire("OnEnter")
  eq(UI.tooltipOwner(), f, "its tooltip")
  root:unmount()
  eq(UI.tooltipOwner(), nil, "hidden on release")
  W.cursorX, W.cursorY = -100, -100
end)

test("tooltip: drawn in its owner's theme", function()
  local inline = { name = "t-tip-inline", colors = { muted = "#00FF00" } }
  UI.registerTheme({ name = "t-tip-tree", base = "default", colors = { muted = "#0000FF" } })
  local host = CreateFrame("Frame", nil, UIParent)
  host:SetSize(300, 50)
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -300)
  local root = UI.mount(host, UI.HStack { gap = 8,
    UI.Help { title = "Tree", text = "The tree's theme" },
    UI.Help { title = "Own", text = "Its own theme", theme = inline },
  }, { theme = "t-tip-tree" })
  local plain = UI.mount(CreateFrame("Frame", nil, UIParent), UI.Help { title = "Global", text = "The global theme" })
  UI.flush()
  local helps = find(root, "Help")
  local tip = I.tooltip
  local function muted()
    local texts = find(tip.root, "Text")
    return texts[#texts].region._color
  end
  helps[1].region:_fire("OnEnter")
  ok(find(tip.root, "VStack")[1].theme == I.resolve("t-tip-tree"), "the mount's theme")
  ok(math.abs(muted()[3] - 1) < 0.001 and muted()[2] < 0.001, "text in the mount's muted")
  helps[1].region:_fire("OnLeave")
  helps[2].region:_fire("OnEnter")
  ok(find(tip.root, "VStack")[1].theme == I.resolve(inline), "the element's own theme")
  ok(math.abs(muted()[2] - 1) < 0.001 and muted()[3] < 0.001, "text in the element's muted")
  helps[2].region:_fire("OnLeave")
  find(plain, "Help")[1].region:_fire("OnEnter")
  eq(find(tip.root, "VStack")[1].theme, nil, "back to the global theme")
  ok(math.abs(muted()[1] - I.resolve("default").muted.r) < 0.001, "text in the global muted")
  UI.hideTooltip()
  root:unmount()
  plain:unmount()
end)

test("tooltip and help: themed, sized to content, above or below its owner, one owner at a time", function()
  local host = CreateFrame("Frame", nil, UIParent)
  host:SetSize(400, 100)
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -300)
  local root = UI.mount(host, UI.HStack { gap = 8,
    UI.Help { title = "Columns", text = "Price: the lowest listing. Qty: how many are listed." },
    UI.Help { text = "Short" },
    UI.Help { size = 18 },
  })
  UI.flush()
  local helps = find(root, "Help")
  local f = helps[1].region
  eq(helps[1].w, 14, "a small icon")
  eq(I.resolve("default").metrics.Help.size, 14, "the default theme's metric")
  eq(helps[3].w, 18, "or the size asked for")
  eq(f.mark:GetText(), "?")
  f:_fire("OnEnter")
  eq(UI.tooltipOwner(), f, "its tooltip")
  local tip = I.tooltip
  local texts = find(tip.root, "Text")
  eq(texts[1].el.props.text, "Columns", "the title")
  eq(texts[1].el.props.style, "strong")
  eq(texts[2].el.props.color, "muted", "the text under a title")
  eq(find(tip.root, "VStack")[1].el.props.surface, "tooltip", "the theme's tooltip surface")
  local w, h = tip.host:GetSize()
  ok(w > 0 and w <= 260 and h > 0, "sized to its content, at most 260 wide: " .. w .. "x" .. h)
  local at = tip.host._points[1]
  eq(at[2], f)
  eq(at[3], "TOP", "above its owner")
  -- Another owner takes it; the first leaving does not hide it.
  local g = helps[2].region
  g:_fire("OnEnter")
  eq(UI.tooltipOwner(), g)
  eq(find(tip.root, "Text")[1].el.props.color, "text", "text alone")
  f:_fire("OnLeave")
  eq(UI.tooltipOwner(), g, "only its owner hides it")
  g:_fire("OnLeave")
  eq(UI.tooltipOwner(), nil)
  -- Nothing to say: nothing shown.
  helps[3].region:_fire("OnEnter")
  eq(UI.tooltipOwner(), nil)
  helps[3].region:_fire("OnLeave")
  -- No room above: below.
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, 0)
  UI.flush()
  root:layout()
  f:_fire("OnEnter")
  eq(tip.host._points[1][3], "BOTTOM", "below its owner")
  -- Unmounting the owner hides it.
  root:unmount()
  eq(UI.tooltipOwner(), nil)
  UI.showTooltip(host, "plain text")
  eq(UI.tooltipOwner(), host)
  UI.showTooltip(host, { title = "", text = "no title" })
  eq(#find(tip.root, "Text"), 1, "an empty title draws no title row")
  eq(find(tip.root, "Text")[1].el.props.color, "text", "and the text is not muted under it")
  UI.hideTooltip()
  eq(UI.tooltipOwner(), nil, "hidden for any owner")
end)

test("controls: button variants, hover and press, busy, tooltip; badges; toggles", function()
  local host = CreateFrame("Frame")
  host:SetSize(600, 100)
  local clicks, changed = 0, nil
  local function view(busy)
    return UI.HStack { gap = 4,
      UI.Button { text = "Primary", variant = "primary", tooltip = "Does it", onClick = function() clicks = clicks + 1 end },
      UI.Button { text = "Danger", variant = "danger", size = "lg" },
      UI.Button { text = "Ghost", variant = "ghost", size = "sm" },
      UI.Button { text = "Save", busy = busy, onClick = function() clicks = clicks + 10 end },
      UI.Badge { text = "solid", tone = "gold", solid = true },
      UI.Badge { text = "info", tone = "info" },
      UI.Toggle { label = "Auto", checked = false, onChange = function(v) changed = v end },
      UI.Toggle { label = "Off", disabled = true, onChange = function() changed = "disabled" end },
      UI.Toggle {},
    }
  end
  local root = UI.mount(host, view(nil))
  local buttons = find(root, "Button")
  for i = 1, 3 do
    local b = buttons[i].region
    b:_fire("OnEnter")
    b:_fire("OnMouseDown")
    ok(b.fxPressed, buttons[i].el.props.text .. " pressed")
    b:_fire("OnMouseUp")
    b:_fire("OnLeave")
    ok(not b.fxHover, "hover cleared")
  end
  buttons[1].region:_fire("OnEnter")
  ok(UI.tooltipOwner() == buttons[1].region, "tooltip on hover")
  buttons[1].region:_fire("OnLeave")
  ok(UI.tooltipOwner() ~= buttons[1].region, "tooltip hidden")
  buttons[1].region:_click()
  eq(clicks, 1, "primary click")
  eq(buttons[2].h, 40, "large")
  eq(buttons[3].h, 24, "small")

  root:update(view("Loading\226\128\166"))
  local save = find(root, "Button", function(n) return n.el.props.text == "Save" end)[1].region
  eq(save.label:GetText(), "Loading\226\128\166", "busy text replaces the label")
  ok(not save:IsEnabled(), "busy looks disabled")
  save:_fire("OnClick", "LeftButton")
  eq(clicks, 1, "busy button ignores clicks")

  local badges = find(root, "Badge")
  eq(badges[1].region.label._color[1], I.resolve("default").onGold.r, "solid gold badge uses onGold text")
  ok(badges[2].region.fxBg:IsShown(), "tinted badge")

  local toggles = find(root, "Toggle")
  local t = toggles[1].region
  t:_fire("OnEnter")
  t:_click()
  eq(changed, true, "onChange gets the new value")
  t:_fire("OnLeave")
  toggles[2].region:_click()
  eq(changed, true, "disabled toggle ignores clicks")
  eq(toggles[2].region:GetAlpha(), 0.5, "disabled toggle dimmed")
  eq(toggles[3].w, 30, "toggle without a label is just the track")
  root:unmount()
end)

test("toast: a notice shows and is gone after its duration", function()
  UI.toast("Saved", { tone = "up" })
  W.nextFrame()
  local root
  for r in pairs(I.roots) do
    if r.node and r.node.def and r.node.def.name == "FxToastStack" then root = r end
  end
  ok(root, "toast stack mounted")
  local texts = find(root, "Text")
  eq(#texts, 1, "one notice")
  eq(texts[1].region:GetText(), "Saved")
  for i = 1, 6 do UI.toast("n" .. i, { duration = 1 }) end
  W.nextFrame()
  eq(#find(root, "Text"), 5, "at most five notices")
  W.advance(4)
  W.nextFrame()
  eq(#find(root, "Text"), 0, "gone after four seconds")
end)

test("scale: FxUI scale resizes windows, keeps their spot, persists, has a slider", function()
  local slider = W.settings.settings.FXUI_SCALE
  ok(slider and slider.slider and slider.slider.min == UI.SCALE_MIN, "scale slider registered under FxUI")
  eq(slider.slider.formatter(0.85), "85%", "slider label")
  local saved = {}
  local root = UI.mount(UIParent, UI.Window { title = "Scaled", width = 400, height = 300, saved = saved })
  local f = find(root, "Window")[1].region
  eq(f:GetScale(), 1, "starts at 100%")
  local left, top = f:GetLeft(), f:GetTop()
  UI.setScale(0.8)
  eq(f:GetScale(), 0.8, "window scaled")
  eq(FxUIDB.scale, 0.8, "saved")
  local p = f._points[1]
  ok(math.abs(p[4] - left / 0.8) < 0.01 and math.abs(p[5] - top / 0.8) < 0.01, "top-left kept on screen")
  eq(saved.scale, 0.8, "window geometry saved with its scale")
  UI.toast("Scaled")
  local toastHost
  for frame, keep in pairs(I.scaled) do
    if keep == false and frame:GetFrameStrata() == "DIALOG" then toastHost = frame end
  end
  ok(toastHost and toastHost:GetScale() == 0.8, "toasts follow the scale")
  slider:SetValue(0.5)
  eq(UI.scale, 0.5, "slider sets the scale")
  UI.setScale(9)
  eq(UI.scale, 2, "clamped to the maximum")
  UI.setScale(0.1)
  eq(UI.scale, UI.SCALE_MIN, "clamped to the minimum")
  UI.setScale(1)
  root:unmount()
  root = UI.mount(UIParent, UI.Window { title = "Scaled", saved = saved })
  f = find(root, "Window")[1].region
  eq(f:GetScale(), 1, "reopened at the current scale")
  ok(math.abs(f:GetLeft() - left) < 0.01 and math.abs(f:GetTop() - top) < 0.01, "where it was on screen")
  root:unmount()
  UI.openSettings()
  eq(W.settings.opened, I.settingsCategory:GetID(), "opens the FxUI settings")
  W.advance(5)
  W.nextFrame()
end)

test("render: conditional and mapped children, flex on component elements", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 600)
  local root = UI.mount(host, UI.VStack {
    UI.Text { text = "a" }, false, nil,
    UI.map({ 1, 2 }, function(n) return UI.Text { text = tostring(n) } end),
  })
  local texts = {}
  for _, n in ipairs(find(root, "Text")) do texts[#texts + 1] = n.region:GetText() end
  eq(table.concat(texts, ","), "a,1,2", "three Text children")
  ok(not UI.isElement({}) and UI.isElement(UI.Text {}), "isElement")
  root:unmount()

  local Page = UI.component("TestPage", function() return UI.VStack { UI.Text { text = "page" } } end)
  root = UI.mount(host, UI.VStack { UI.HStack { height = 40 }, Page { flex = 1 } })
  local page = find(root, "VStack")[2]
  eq(page.h, 560, "the page takes the stack's free space")
  root:unmount()

  root = UI.mount(host, UI.VStack { align = "stretch",
    UI.HStack { width = 300, justify = "between",
      UI.HStack { width = 50, height = 10 }, UI.HStack { width = 50, height = 10 }, UI.HStack { width = 50, height = 10 } },
    UI.HStack { width = 300, justify = "end", UI.HStack { width = 50, height = 10 } },
    UI.HStack { width = 300, justify = "center", UI.HStack { width = 50, height = 10 } },
    UI.HStack { height = 60, align = "end", UI.HStack { width = 50, height = 10 } },
    UI.Spacer { size = 12 },
    UI.Divider {},
  })
  local rows = find(root, "HStack", function(n) return n.el.props.justify == "between" end)[1].children
  eq(rows[1].x, 0, "first child at the start")
  eq(rows[3].x + rows[3].w, 300, "last child at the end")
  eq(rows[2].x - (rows[1].x + rows[1].w), rows[3].x - (rows[2].x + rows[2].w), "equal gaps")
  local endRow = find(root, "HStack", function(n) return n.el.props.justify == "end" end)[1]
  eq(endRow.children[1].x, 250, "justify end")
  local centreRow = find(root, "HStack", function(n) return n.el.props.justify == "center" end)[1]
  eq(centreRow.children[1].x, 125, "justify center")
  local low = find(root, "HStack", function(n) return n.el.props.align == "end" end)[1]
  eq(low.children[1].y, 50, "align end")
  root:unmount()
end)

test("render: lifecycle, delayed callbacks, failing renders, unmount releases everything", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 300)
  local ran, cleaned, unmounted, mountedCtx = false, false, false, nil
  local Delayed = UI.component("TestDelayed", {
    init = function(ctx) ctx.state.n = 1 end,
    mounted = function(ctx)
      mountedCtx = ctx
      ctx:after(2, function() ran = true end)
      ctx:onUnmount(function() cleaned = true end)
    end,
    unmounted = function() unmounted = true end,
    render = function(_, ctx) return UI.Text { text = tostring(ctx.state.n) } end,
  })
  local Broken = UI.component("TestBroken", function() error("render failed") end)
  local Nothing = UI.component("TestNothing", function() return nil end)
  local _, baseline = UI.stats()
  local root = UI.mount(host, UI.VStack {
    UI.Text { text = "before" }, Broken {}, Delayed {}, Nothing {}, UI.Text { text = "after" },
  })
  ok(#W.errors == 1 and W.errors[1]:find("render failed", 1, true), "the error reaches the error handler")
  W.errors = {}
  local texts = {}
  for _, n in ipairs(find(root, "Text")) do texts[#texts + 1] = n.region:GetText() end
  eq(table.concat(texts, ","), "before,1,after", "the failing component renders nothing; the rest render")
  ok(mountedCtx:isMounted(), "mounted")
  mountedCtx:forceUpdate()
  mountedCtx:setState(function(state) return { n = state.n + 1 } end)
  UI.flush()
  eq(find(root, "Text")[2].region:GetText(), "2", "functional state update")
  local _, total = UI.stats()
  ok(total.active > 0, "regions active while mounted")
  root:unmount()
  root:unmount()
  root:update(UI.Text { text = "ignored" })
  ok(unmounted and cleaned, "unmount hooks run")
  ok(not mountedCtx:isMounted(), "not mounted")
  W.advance(3)
  ok(not ran, "delayed callback never runs after unmount")
  local stats, after = UI.stats()
  eq(after.active, baseline.active, "none of its regions active")
  eq(after.pooled, after.created - after.active, "all of them pooled")
  eq(after.pooled - baseline.pooled, after.created - baseline.created, "every region it took is back in the pools")
  ok(stats.Text and stats.Text.pooled > 0, "per-host counts")

  -- A delayed callback on a live component runs; the root swaps element types.
  root = UI.mount(host, Delayed {})
  ran = false
  W.advance(3)
  ok(ran, "delayed callback runs while mounted")
  root:update(UI.Text { text = "swapped" })
  eq(find(root, "Text")[1].region:GetText(), "swapped", "root replaced by another element type")
  root:unmount()
end)

test("core: errors are reported without unwinding; combat state; unknown client API", function()
  local okCall, result = I.safecall(function(a, b) return a + b end, 1, 2)
  ok(okCall and result == 3, "safecall returns results")
  ok(not I.safecall(function() error("boom") end), "safecall reports failure")
  ok(#W.errors == 1 and W.errors[1]:find("boom", 1, true), "error reported")
  W.errors = {}
  ok(I.errors[#I.errors].message:find("boom", 1, true), "kept for dev tools")
  for i = 1, 60 do I.report("e" .. i) end
  eq(#I.errors, 50, "the error log keeps the last 50")
  W.errors = {}
  eq(UI.inCombat(), false, "out of combat")
  local f = CreateFrame("Frame")
  local passed, err = pcall(function() f:NoSuchClientMethod() end)
  ok(not passed and tostring(err):find("stub: unknown client API method NoSuchClientMethod", 1, true), "stub rejects unknown methods: " .. tostring(err))
end)

test("commands: with nothing registered, /fx says so", function()
  local saved = UI.commands
  UI.commands = {}
  local printed = {}
  local realPrint = print
  print = function(s) printed[#printed + 1] = s end
  fx("help")
  print = realPrint
  UI.commands = saved
  ok(table.concat(printed, "\n"):find("none registered", 1, true), "help says none registered")
end)

test("list: thumb drag, striped rows, scrollListTo; ScrollView thumbs drag", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(300, 200)
  local items = {}
  for i = 1, 100 do items[i] = { id = i } end
  local root = UI.mount(host, UI.List { items = items, key = function(it) return "k" .. it.id end, rowHeight = 20, striped = true,
    render = function(it) return UI.Text { text = tostring(it.id) } end })
  local list = find(root, "List")[1]
  local thumb = list.region.thumb
  thumb:_fire("OnEnter")
  W.cursorX, W.cursorY = 10, 500
  thumb:_fire("OnMouseDown")
  W.cursorY = 400
  W.nextFrame()
  ok(list.offset > 0, "dragging the thumb scrolls: " .. list.offset)
  thumb:_fire("OnMouseUp")
  thumb:_fire("OnLeave")
  UI.scrollListTo(list.region, 50)
  eq(list.offset, 49 * 20, "scrolled to row 50")
  ok(tostring(list.children[1].el.key):match("^k%d+$"), "rows keyed by the key function")
  ok(list.children[2].region.fxBg, "striped rows")
  UI.scrollListTo(nil, 1)
  root:unmount()

  local kids = {}
  for i = 1, 10 do kids[i] = UI.HStack { width = 400, height = 30 } end
  root = UI.mount(host, UI.ScrollView { direction = "both", gap = 0, kids })
  local sc = find(root, "ScrollView")[1].region.fxScroller
  for _, axis in ipairs({ "thumbY", "thumbX" }) do
    local th = sc[axis]
    th:_fire("OnEnter")
    W.cursorX, W.cursorY = 100, 500
    th:_fire("OnMouseDown")
    W.cursorX, W.cursorY = 150, 450
    W.nextFrame()
    th:_fire("OnMouseUp")
    th:_fire("OnLeave")
  end
  ok(sc.offsetY > 0 and sc.offsetX > 0, "both thumbs drag: " .. sc.offsetX .. ", " .. sc.offsetY)
  root:unmount()
end)

test("coverage: the gate fails below 80% and passes from 80%", function()
  local C = dofile("tests/coverage.lua")
  local function report(hits, missed)
    return table.concat({
      "==============================================================================",
      "Summary",
      "==============================================================================",
      "",
      "File         Hits Missed Coverage",
      "---------------------------------",
      "Lib/A.lua    " .. hits .. "   " .. missed .. "     0.00%",
      "Lib/B.lua    0    0     0.00%",
      "---------------------------------",
      "Total        " .. hits .. "   " .. missed .. "     0.00%",
      "",
    }, "\n")
  end
  ok(not C.check(report(79, 21), 80), "79 % fails")
  local passed, lines = C.check(report(80, 20), 80)
  ok(passed, "80 % passes")
  ok(lines[#lines]:find("80.00%", 1, true), "reports the total: " .. lines[#lines])
  ok(not C.check("no summary here"), "a report without a summary fails")
  ok(not C.check("\nSummary\n===\nnothing\n"), "a summary without files fails")
end)

-- Loads a copy of the library the way an addon embeds it, from source text,
-- as addon `name` from `folder` (both inside Interface/AddOns), with
-- `minor` replacing the library's minor version.
local function loadCopy(name, folder, minor)
  local ns = {}
  W.loadingAddon = folder
  for line in io.lines("FxUI/FxUI.toc") do
    if not line:match("^%s*$") and not line:match("^##") then
      local path = "FxUI/" .. line:gsub("\\", "/")
      local fh = assert(io.open(path))
      local src = fh:read("*a")
      fh:close()
      if path == "FxUI/Core.lua" then src = src:gsub('"FxUI%-1%.0", 1', '"FxUI-1.0", ' .. minor) end
      if path == "FxUI/Libs/LibStub/LibStub.lua" then
        if not LibStub then assert(loadstring(src, "=" .. folder .. "/LibStub.lua"))(name, ns) end
      else
        assert(loadstring(src, "=" .. folder .. "/" .. line))(name, ns)
      end
    end
  end
  W.loadingAddon = nil
  return ns
end

test("library: embedded copies find their media; the newest copy wins", function()
  local realLibStub, realSlash = LibStub, SlashCmdList.FXUI_COMMANDS
  LibStub = nil
  local a = loadCopy("SomeAddon", "SomeAddon/Libs/FxUI", 1)
  local libA = LibStub("FxUI-1.0")
  ok(a.FxUI == libA, "the first copy registers")
  eq(libA._internal.media, "Interface\\AddOns\\SomeAddon\\Libs\\FxUI\\Media\\", "media inside the embedding addon")
  local host = CreateFrame("Frame")
  host:SetSize(100, 100)
  local root = libA.mount(host, libA.VStack { bg = "panel", radius = 8 })
  local bg = root.node.region.fxBg
  ok(bg._texture:find("SomeAddon\\Libs\\FxUI\\Media\\Textures\\Round8", 1, true), "texture path inside the embedding addon: " .. tostring(bg._texture))
  root:unmount()

  local same = loadCopy("OtherAddon", "OtherAddon/Libs/FxUI", 1)
  eq(same.FxUI, false, "an equal copy steps aside")
  local b = loadCopy("NewerAddon", "NewerAddon/Libs/FxUI", 2)
  local lib = LibStub("FxUI-1.0")
  eq(lib.MINOR, 2, "both addons get the newer copy")
  ok(b.FxUI == lib and libA == lib, "one library table")
  root = lib.mount(host, lib.Text { text = "upgraded" })
  eq(root.node.region:GetText(), "upgraded", "the upgraded copy renders")
  root:unmount()

  LibStub, SlashCmdList.FXUI_COMMANDS = realLibStub, realSlash
end)

test("library: an upgrade keeps mounted trees, scale followers, pools and settings", function()
  local realLibStub, realSlash = LibStub, SlashCmdList.FXUI_COMMANDS
  LibStub = nil
  loadCopy("SomeAddon", "SomeAddon/Libs/FxUI", 1)
  local old = LibStub("FxUI-1.0")
  local oldI = old._internal
  old.registerTheme("t-upgrade", "default", { colors = { gold = "#00FF00" } })
  local host = CreateFrame("Frame")
  host:SetSize(100, 100)
  local root = old.mount(host, old.Text { text = "a", color = "gold" })
  local win = old.mount(UIParent, old.Window { title = "w", width = 300, height = 200 })
  local wf = find(win, "Window")[1].region
  oldI.db = { theme = "default" }
  local oldTable = oldI.resolve({ name = "inline-old", fonts = { body = { file = "Inter-Regular.ttf", size = 20 } } })
  old.toast("from the older copy")
  local released = old.mount(host, old.VStack { bg = "panel" })
  released:unmount()
  local pooled = old.stats().VStack.pooled
  ok(pooled > 0, "a pooled region")

  loadCopy("NewerAddon", "NewerAddon/Libs/FxUI", 2)
  local lib = LibStub("FxUI-1.0")
  local I2 = lib._internal
  eq(lib.MINOR, 2, "the newer copy is registered")
  eq(I2.db and I2.db.theme, "default", "settings state survives")
  eq(lib.stats().VStack.pooled, pooled, "pooled regions survive")

  lib.setTheme("t-upgrade")
  eq(find(root, "Text")[1].region._color[2], 1, "setTheme from the newer copy restyles a tree the older copy mounted")
  eq(I2.db.theme, "t-upgrade", "the choice is saved")
  lib.setScale(1.5)
  eq(wf:GetScale(), 1.5, "setScale reaches a window the older copy mounted")

  local newTable = I2.resolve({ name = "inline-new", fonts = { body = { file = "Inter-Regular.ttf", size = 30 } } })
  ok(newTable.fonts.body ~= oldTable.fonts.body, "theme tables resolved after the upgrade get their own fonts")
  eq(select(2, oldTable.fonts.body:GetFont()), 20, "a table resolved before the upgrade keeps its fonts")

  lib.toast("from the newer copy")
  eq(#I2.toast.root.node.ctx.state.items, 2, "both copies' toasts share one stack")

  local calls = 0
  local function listener() calls = calls + 1 end
  I2.combatListeners[listener] = true
  W.fireEvent("PLAYER_REGEN_DISABLED")
  eq(calls, 1, "one dispatch per event after the upgrade")
  ok(lib.inCombat(), "combat state follows")
  W.fireEvent("PLAYER_REGEN_ENABLED")
  I2.combatListeners[listener] = nil

  lib.setScale(1)
  lib.setTheme("default")
  root:unmount()
  win:unmount()
  W.advance(10)
  LibStub, SlashCmdList.FXUI_COMMANDS = realLibStub, realSlash
end)

test("library: nodes an older copy mounted reconcile as the same types under the newer copy", function()
  local realLibStub, realSlash = LibStub, SlashCmdList.FXUI_COMMANDS
  LibStub = nil
  loadCopy("SomeAddon", "SomeAddon/Libs/FxUI", 1)
  local old = LibStub("FxUI-1.0")
  local items = {}
  for i = 1, 100 do items[i] = { id = i, name = "Item " .. i, price = i * 10 } end
  local function tree(L)
    return L.VStack {
      align = "stretch",
      L.List { height = 100, items = items, key = "id", rowHeight = 20, render = function(it) return L.Text { text = it.name } end },
      L.Table { height = 120, items = items, key = "name", rowHeight = 20,
        columns = { { key = "name", title = "Name", flex = 1 }, { key = "price", title = "Price", width = 80 } } },
      L.TabBar { tabs = { { id = "a", text = "Alpha" }, { id = "b", text = "Beta" } }, selected = "a" },
      L.Legend { items = { { label = "Bid", value = 1, color = "gold" } } },
    }
  end
  local host = CreateFrame("Frame")
  host:SetSize(400, 400)
  local root = old.mount(host, tree(old))
  local function nodes()
    local out = { list = find(root, "List")[1], hosts = {} }
    walk(root.node, function(n)
      if n.def then out[n.def.name] = n end
      if n.host then out.hosts[#out.hosts + 1] = n end
    end)
    return out
  end
  find(root, "List")[1].region:_fire("OnMouseWheel", -1)
  local before = nodes()
  for _, name in ipairs({ "Table", "TabBar", "Legend" }) do ok(before[name], name .. " mounted") end
  local offset = before.list.offset
  ok(offset > 0, "the older copy's list scrolled")

  loadCopy("NewerAddon", "NewerAddon/Libs/FxUI", 2)
  local lib = LibStub("FxUI-1.0")
  eq(lib.MINOR, 2, "the newer copy is registered")
  root:update(tree(lib))
  local after = nodes()
  ok(after.list == before.list, "the list node is kept")
  eq(after.list.offset, offset, "the list keeps its scroll offset")
  for _, name in ipairs({ "Table", "TabBar", "Legend" }) do
    ok(after[name] == before[name], name .. " node is kept")
  end
  eq(#after.hosts, #before.hosts, "as many host nodes")
  for i, n in ipairs(before.hosts) do
    ok(after.hosts[i] == n, "host node " .. i .. " (" .. n.host.name .. ") is kept")
  end
  lib.scrollListTo(after.list.region, 10)
  eq(after.list.offset, 9 * 20, "scrollListTo works on a list the older copy mounted")
  ok(lib.component("Table", function() return lib.Text {} end) ~= lib.Table, "a consumer component never takes over a built-in one")

  root:unmount()
  LibStub, SlashCmdList.FXUI_COMMANDS = realLibStub, realSlash
end)

test("library: an embedded copy upgrading the standalone addon keeps its saved settings working", function()
  local realLibStub, realSlash = LibStub, SlashCmdList.FXUI_COMMANDS
  LibStub = nil
  loadCopy("FxUI", "FxUI", 1)
  local I1 = LibStub("FxUI-1.0")._internal
  I1.db = { theme = "t-saved" } -- what ADDON_LOADED sets up from FxUIDB
  loadCopy("NewerAddon", "NewerAddon/Libs/FxUI", 2)
  local lib = LibStub("FxUI-1.0")
  local I2 = lib._internal
  ok(I2.eventHandlers.ADDON_LOADED and next(I2.eventHandlers.ADDON_LOADED), "the standalone addon's settings handler is kept")
  lib.registerTheme("t-saved", "default", {})
  I2.events:_fire("OnEvent", "PLAYER_LOGIN")
  eq(lib.themeName, "t-saved", "the saved theme is applied at login")
  lib.setTheme("default")
  LibStub, SlashCmdList.FXUI_COMMANDS = realLibStub, realSlash
end)

test("render: a root update with another key creates a new node", function()
  local host = CreateFrame("Frame")
  host:SetSize(100, 100)
  local root = UI.mount(host, UI.Text { key = "a", text = "a" })
  local first = root.node
  root:update(UI.Text { key = "b", text = "b" })
  ok(root.node ~= first, "another key: a new node")
  ok(not first.alive, "the old node is released")
  local second = root.node
  root:update(UI.Text { key = "b", text = "c" })
  ok(root.node == second, "the same key updates in place")
  eq(second.region:GetText(), "c")
  root:unmount()
end)

test("layout: wrapped lines honour every justify value", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 600)
  -- Five 80 px children with gap 10: lines of three (260 px) and two (170 px).
  local expect = {
    start = { 0, 90, 180, 0, 90 },
    center = { 20, 110, 200, 65, 155 },
    ["end"] = { 40, 130, 220, 130, 220 },
    between = { 0, 110, 220, 0, 220 },
  }
  for justify, xs in pairs(expect) do
    local kids = {}
    for i = 1, 5 do kids[i] = UI.HStack { width = 80, height = 20 } end
    local root = UI.mount(host, UI.VStack { align = "stretch", UI.HStack { wrap = true, gap = 10, justify = justify, kids } })
    local row = find(root, "HStack", function(n) return n.el.props.wrap end)[1]
    for i, c in ipairs(row.children) do
      eq(c.x, xs[i], justify .. ": child " .. i .. " x")
    end
    root:unmount()
  end
end)

test("scroll: scrollbars go away with scroll = false and on a reused region", function()
  local function rows()
    local out = {}
    for i = 1, 10 do out[i] = UI.HStack { height = 40 } end
    return out
  end
  local root = UI.mount(UIParent, UI.Window { title = "Tall", width = 300, height = 248, rows() })
  local win = find(root, "Window")[1]
  local sc = win.region.body.fxScroller
  ok(win.scroll and sc.thumbY:IsShown() and sc.thumbY.track:IsShown(), "scrolls")
  root:update(UI.Window { title = "Tall", width = 300, height = 248, scroll = false, rows() })
  ok(not sc.thumbY:IsShown() and not sc.thumbY.track:IsShown(), "vertical scrollbar hidden")
  ok(not sc.thumbX:IsShown() and not sc.thumbX.track:IsShown(), "horizontal scrollbar hidden")
  ok(not win.scroll, "the node no longer scrolls")
  eq(sc.maxY, 0, "no scroll range")
  root:update(UI.Window { title = "Tall", width = 300, height = 248, rows() })
  ok(win.scroll and sc.thumbY:IsShown(), "scrolls again")
  sc.thumbY:_fire("OnEnter")
  sc.thumbY:_fire("OnMouseDown")
  root:unmount()

  root = UI.mount(UIParent, UI.Window { title = "Short", width = 300, height = 248, scroll = false, UI.HStack { height = 40 } })
  win = find(root, "Window")[1]
  ok(win.region.body.fxScroller == sc, "the pooled window is reused")
  ok(not sc.thumbY:IsShown() and not sc.thumbY.track:IsShown(), "no scrollbar on the reused window")
  ok(not sc.thumbY.fxHover and not sc.thumbY.fxDrag, "no hover or drag carried over")
  root:unmount()

  local host = CreateFrame("Frame")
  host:SetSize(200, 100)
  local kids = {}
  for i = 1, 6 do kids[i] = UI.HStack { height = 30 } end
  root = UI.mount(host, UI.ScrollView { kids })
  local view = find(root, "ScrollView")[1]
  local vsc = view.region.fxScroller
  ok(vsc.thumbY:IsShown(), "ScrollView scrolls")
  vsc.thumbY:_fire("OnEnter")
  vsc.thumbY:_fire("OnMouseDown")
  root:unmount()
  ok(not vsc.thumbY:IsShown() and not vsc.thumbY.track:IsShown(), "a released ScrollView keeps no scrollbar")
  ok(not vsc.thumbY.fxHover and not vsc.thumbY.fxDrag, "nor hover or drag")
  eq(vsc.maxY, 0, "nor a scroll range")
end)

test("theme: radius tokens and late item styling use the element's theme", function()
  UI.registerTheme("t-square", "default", { colors = { muted = "#00FF00" }, radius = { r4 = 0, r8 = 0, pill = 0 } })
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(400, 40)
  local root = UI.mount(host, UI.HStack { bg = "panel", radius = "r8", UI.ItemCell { item = 4250, qty = 2 } }, { theme = "t-square" })
  local stack = find(root, "HStack")[1]
  eq(stack.region.fxBg.fxShape, nil, "r8 is square in a theme whose r8 is 0")
  local f = find(root, "ItemCell")[1].region
  W.loadItems()
  W.nextFrame()
  eq(f.extra:GetText(), "\195\1512")
  eq(f.extra._color[2], 1, "extra text styled in the tree's theme after the item loads")
  eq(f.extra._color[1], 0)
  root:unmount()
  W.items[4250] = nil
end)

test("theme: re-registering a theme reaches roots and elements that use it", function()
  UI.registerTheme("t-re", "default", { colors = { gold = "#FF0000" } })
  UI.registerTheme("t-re-base", "default", { colors = { gold = "#FF0000" } })
  UI.registerTheme("t-re-kid", "t-re-base", { colors = { info = "#123456" } })
  local hosts = {}
  for i = 1, 3 do
    hosts[i] = CreateFrame("Frame")
    hosts[i]:SetSize(100, 100)
  end
  local direct = UI.mount(hosts[1], UI.Text { text = "a", color = "gold" }, { theme = "t-re" })
  local inherited = UI.mount(hosts[2], UI.Text { text = "b", color = "gold" }, { theme = "t-re-kid" })
  local inline = { name = "inline-kid", base = "t-re-base" }
  local function elements()
    return UI.VStack {
      UI.Text { text = "c", color = "gold", theme = "t-re-kid" },
      UI.Text { text = "d", color = "gold", theme = inline },
    }
  end
  local perElement = UI.mount(hosts[3], elements())
  UI.registerTheme("t-re", "default", { colors = { gold = "#00FF00" } })
  UI.registerTheme("t-re-base", "default", { colors = { gold = "#00FF00" } })
  direct:update()
  inherited:update()
  perElement:update(elements())
  eq(find(direct, "Text")[1].region._color[2], 1, "a mount theme re-registered")
  eq(find(inherited, "Text")[1].region._color[2], 1, "a mount theme whose base was re-registered")
  local texts = find(perElement, "Text")
  eq(texts[1].region._color[2], 1, "an element theme name whose base was re-registered")
  eq(texts[2].region._color[2], 1, "an element theme table whose base was re-registered")
  direct:unmount(); inherited:unmount(); perElement:unmount()
end)

test("chart: onHover(nil) on every path that ends a hover", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(300, 150)
  local values = {}
  for i = 1, 11 do values[i] = 1000 + i * 100 end
  local calls = {}
  local function onHover(i) calls[#calls + 1] = i == nil and "nil" or i end
  local function chart() return UI.Chart { values = values, onHover = onHover } end
  local root = UI.mount(host, chart())
  local node = find(root, "Chart")[1]
  local f = node.region
  local l, b = f:GetRect()
  local function hover(i)
    W.cursorX, W.cursorY = l + node.geo.xs[i], b + 60
    W.nextFrame()
  end
  hover(6)
  eq(calls[#calls], 6, "hovered index")
  W.cursorX = l + 1
  W.nextFrame()
  eq(calls[#calls], "nil", "leaving the plot into the margin")
  ok(not f.cross:IsShown(), "crosshair hidden in the margin")
  local n = #calls
  W.cursorX, W.cursorY = -100, -100
  W.nextFrame()
  eq(#calls, n, "leaving the frame afterwards sends nothing more")

  hover(4)
  n = #calls
  root:update(chart())
  W.nextFrame()
  for i = n + 1, #calls do ok(calls[i] ~= "nil", "a re-layout does not end the hover") end
  eq(calls[#calls], 4, "still hovering after a re-layout")
  root:update(UI.Chart { values = {}, onHover = onHover })
  W.nextFrame()
  eq(calls[#calls], "nil", "the data going away ends the hover")

  root:update(chart())
  hover(3)
  f:Hide()
  eq(calls[#calls], "nil", "hiding the chart ends the hover")
  f:Show()
  hover(2)
  root:unmount()
  eq(calls[#calls], "nil", "unmounting ends the hover")
  W.cursorX, W.cursorY = -100, -100
end)

test("chart: hover ends in every margin of the plot", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(300, 150)
  local values = {}
  for i = 1, 11 do values[i] = 1000 + i * 100 end
  local calls = {}
  local root = UI.mount(host, UI.Chart { values = values, onHover = function(i) calls[#calls + 1] = i == nil and "nil" or i end })
  local node = find(root, "Chart")[1]
  local f, g = node.region, node.geo
  local l, b = f:GetRect()
  local x = l + g.xs[6]
  local margins = {
    { "left", l + g.left - 2, b + 60 },
    { "right", l + g.right + 2, b + 60 },
    { "top", x, b + g.top + 2 },
    { "bottom", x, b + g.bottom - 2 },
  }
  for _, m in ipairs(margins) do
    W.cursorX, W.cursorY = x, b + 60
    W.nextFrame()
    ok(f.cross:IsShown(), "hovering before the " .. m[1] .. " margin")
    eq(calls[#calls], 6, "hovered index before the " .. m[1] .. " margin")
    W.cursorX, W.cursorY = m[2], m[3]
    W.nextFrame()
    ok(not f.cross:IsShown(), "crosshair hidden in the " .. m[1] .. " margin")
    eq(calls[#calls], "nil", "onHover(nil) in the " .. m[1] .. " margin")
  end
  root:unmount()
  W.cursorX, W.cursorY = -100, -100
end)

test("chart: onHover fires once per hovered point, even when it re-renders the consumer", function()
  local host = CreateFrame("Frame")
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(300, 200)
  local values = {}
  for i = 1, 11 do values[i] = 1000 + i * 100 end
  local notes, renders = {}, 0
  local Probe = UI.component("HoverProbe", function(_, ctx)
    renders = renders + 1
    return UI.VStack {
      align = "stretch",
      UI.Text { text = "hovered " .. tostring(ctx.state.i) },
      UI.Chart { flex = 1, values = values, onHover = function(i)
        notes[#notes + 1] = i == nil and "nil" or i
        ctx:setState({ i = i })
      end },
    }
  end)
  local root = UI.mount(host, Probe {})
  local node = find(root, "Chart")[1]
  local f = node.region
  local l, b = f:GetRect()
  W.cursorX, W.cursorY = l + node.geo.xs[6], b + 60
  local before = renders
  for _ = 1, 30 do W.nextFrame() end
  eq(#notes, 1, "one notification for a stationary cursor")
  eq(notes[1], 6, "the hovered index")
  ok(renders - before <= 2, "a bounded number of renders: " .. (renders - before))
  ok(f.cross:IsShown(), "the crosshair is redrawn after the re-layout")

  -- Moving within the same point redraws the price line but does not notify.
  W.cursorY = b + 40
  for _ = 1, 5 do W.nextFrame() end
  eq(#notes, 1, "no notification when only the height changes")
  W.cursorX = l + node.geo.xs[7]
  for _ = 1, 5 do W.nextFrame() end
  eq(#notes, 2, "a new point notifies once")
  eq(notes[2], 7, "with its index")
  W.cursorX, W.cursorY = -100, -100
  for _ = 1, 5 do W.nextFrame() end
  eq(#notes, 3, "ending the hover notifies once")
  eq(notes[3], "nil", "with nil")
  root:unmount()
end)

test("theme: every theme gets its own font objects, whatever its name", function()
  local function body(size) return { fonts = { body = { file = "Inter-Regular.ttf", size = size } } } end
  UI.registerTheme("t-font-a-b", "default", body(12))
  UI.registerTheme("t-font-a_b", "default", body(24))
  local dash, under = I.resolve("t-font-a-b"), I.resolve("t-font-a_b")
  ok(dash.fonts.body ~= under.fonts.body, "names that differ only in punctuation get distinct fonts")
  eq(select(2, dash.fonts.body:GetFont()), 12, "resolving the second keeps the first's size")
  eq(select(2, under.fonts.body:GetFont()), 24)

  -- An unregistered table never shares fonts with a registered theme,
  -- whatever that theme is called.
  local nextName = "custom" .. (I.nextThemeId + 1)
  UI.registerTheme(nextName, "default", body(14))
  local named = I.resolve(nextName)
  local anon = I.resolve(body(30))
  ok(anon.fonts.body ~= named.fonts.body, "a table's fonts are its own")
  eq(select(2, named.fonts.body:GetFont()), 14, "the registered theme keeps its size")
  eq(select(2, anon.fonts.body:GetFont()), 30)

  -- Re-registering a name keeps that theme's font objects.
  local before = dash.fonts.body
  UI.registerTheme("t-font-a-b", "default", body(16))
  local again = I.resolve("t-font-a-b")
  ok(again.fonts.body == before, "the same font object after re-registration")
  eq(select(2, before:GetFont()), 16)
  eq(select(2, I.resolve("t-font-a_b").fonts.body:GetFont()), 24, "the other theme is untouched")
end)

test("table: changing the sorted column's sortValue sorts again", function()
  local host = CreateFrame("Frame")
  host:SetSize(400, 300)
  local items = { { id = 1, a = 1, b = 3 }, { id = 2, a = 2, b = 2 }, { id = 3, a = 3, b = 1 } }
  local function tree(field)
    return UI.Table {
      key = "id", items = items, defaultSort = { key = "v" },
      columns = { { key = "v", title = "V", flex = 1, sortValue = function(it) return it[field] end } },
    }
  end
  local root = UI.mount(host, tree("a"))
  local function order()
    local out = {}
    for _, c in ipairs(find(root, "List")[1].children) do out[#out + 1] = c.el.key end
    return table.concat(out, ",")
  end
  eq(order(), "1,2,3", "sorted by the first sortValue")
  root:update(tree("b"))
  eq(order(), "3,2,1", "sorted again by the new sortValue")

  -- The same sortValue with the same items does not sort again.
  local calls = 0
  local sv = function(it) calls = calls + 1; return it.a end
  local function cell(it) return UI.Text { text = tostring(it.id) } end
  local function same() return UI.Table { key = "id", items = items, defaultSort = { key = "v" }, columns = { { key = "v", flex = 1, sortValue = sv, render = cell } } } end
  root:update(same())
  local after = calls
  ok(after > 0, "sorted with the new function")
  root:update(same())
  eq(calls, after, "no re-sort when nothing the order depends on changed")
  root:unmount()
end)

test("layout: a flexible child is measured at the width it is placed at", function()
  local host = CreateFrame("Frame")
  host:SetSize(200, 400)
  local function chips()
    local out = {}
    for i = 1, 7 do out[i] = UI.HStack { width = 50, height = 20 } end
    return out
  end
  local function isWrap(n) return n.el.props.wrap end
  local function isRow(n) return n.el.props.width == 200 end

  -- A flexible wrapping child with a minimum gets the whole 200 px and
  -- needs two lines of four; the row must be measured that tall.
  local root = UI.mount(host, UI.VStack { align = "start",
    UI.HStack { width = 200, align = "start", UI.HStack { wrap = true, flex = 1, minWidth = 100, chips() } },
  })
  local wrap, row = find(root, "HStack", isWrap)[1], find(root, "HStack", isRow)[1]
  eq(wrap.w, 200, "placed at the full share")
  eq(row.h, 40, "measured at that share: two lines of four")
  root:unmount()

  -- A fixed child after a flexible one is measured, and placed, within what
  -- the flexible child's minimum leaves.
  root = UI.mount(host, UI.VStack { align = "start",
    UI.HStack { width = 200, align = "start", UI.HStack { flex = 1, minWidth = 100 }, UI.HStack { wrap = true, chips() } },
  })
  wrap, row = find(root, "HStack", isWrap)[1], find(root, "HStack", isRow)[1]
  ok(wrap.x + wrap.w <= 200, "the fixed child stays inside the row: " .. tostring(wrap.x + wrap.w))
  eq(wrap.h, 80, "four lines of two")
  eq(row.h, wrap.h, "the row is measured as tall as the child it places")
  root:unmount()
end)

test("layout: a stack child is measured within the space the gaps before it leave", function()
  local host = CreateFrame("Frame")
  host:SetSize(200, 400)
  local function chips()
    local out = {}
    for i = 1, 4 do out[i] = UI.HStack { width = 50, height = 20 } end
    return out
  end
  local function isWrap(n) return n.el.props.wrap end
  local function isRow(n) return n.el.props.width == 200 end

  -- 200 px, gap 10, a 100 px child: the wrapping row gets 90 px, so one
  -- chip per line, and ends inside the row.
  local root = UI.mount(host, UI.VStack { align = "start",
    UI.HStack { width = 200, gap = 10, align = "start", UI.HStack { width = 100, height = 20 }, UI.HStack { wrap = true, chips() } },
  })
  local wrap, row = find(root, "HStack", isWrap)[1], find(root, "HStack", isRow)[1]
  eq(wrap.x, 110)
  ok(wrap.x + wrap.w <= 200, "the row ends inside the stack: " .. tostring(wrap.x + wrap.w))
  eq(wrap.h, 80, "four lines of one")
  eq(row.h, 80, "the row is measured as tall as the child it places")
  root:unmount()

  -- The same along a column: a child that takes the height it is offered
  -- (up to 150) gets 200 - 100 - 10 = 90.
  local seen = {}
  I.defineHost("TestFillHeight", {
    update = I.noop,
    measure = function(node, _, maxH)
      seen[#seen + 1] = maxH
      return 10, math.min(maxH, 150)
    end,
  })
  root = UI.mount(host, UI.HStack { align = "start",
    UI.VStack { height = 200, gap = 10, align = "start", UI.HStack { width = 10, height = 100 }, UI.TestFillHeight {} },
  })
  local fill = find(root, "TestFillHeight")[1]
  eq(fill.y, 110)
  eq(fill.h, 90, "measured within what the gap leaves")
  ok(fill.y + fill.h <= 200, "the child ends inside the column: " .. tostring(fill.y + fill.h))
  root:unmount()
end)

test("layout: stacks are measured as they are placed and keep children inside", function()
  local host = CreateFrame("Frame")
  host:SetSize(200, 200)
  local function chips(n)
    local out = {}
    for i = 1, n do out[i] = UI.HStack { width = 50, height = 20 } end
    return out
  end
  local function inside(s, label)
    for _, c in ipairs(s.children) do
      ok(c.x >= -0.001 and c.y >= -0.001, label .. ": child starts inside")
      ok(c.x + c.w <= s.w + 0.001, label .. ": child ends inside horizontally: " .. tostring(c.x + c.w) .. " > " .. tostring(s.w))
      ok(c.y + c.h <= s.h + 0.001, label .. ": child ends inside vertically: " .. tostring(c.y + c.h) .. " > " .. tostring(s.h))
    end
  end
  -- Extent the children reach, plus the far padding.
  local function extent(s, horizontal, padEnd)
    local m = 0
    for _, c in ipairs(s.children) do
      local e = horizontal and (c.x + c.w) or (c.y + c.h)
      if e > m then m = e end
    end
    return m + padEnd
  end

  local cases = {
    { label = "padded row with a wrapping child", horizontal = true, flex = false, padEnd = 6, crossEnd = 4,
      el = UI.HStack { tag = "s", padding = { 4, 6 }, gap = 10, align = "start", UI.HStack { width = 60, height = 20 }, UI.HStack { wrap = true, chips(4) }, UI.HStack { width = 8, height = 10 } } },
    { label = "row with flexible minima", horizontal = true, flex = true, padEnd = 6, crossEnd = 4,
      el = UI.HStack { tag = "s", padding = { 4, 6 }, gap = 8, align = "start", UI.HStack { flex = 1, minWidth = 100, height = 10 }, UI.HStack { flex = 1, height = 10 }, UI.HStack { width = 50, height = 30 } } },
    { label = "row with uneven flexible minima", horizontal = true, flex = true, padEnd = 0, crossEnd = 0,
      el = UI.HStack { tag = "s", gap = 10, align = "start", UI.HStack { flex = 2, minWidth = 30, height = 10 }, UI.HStack { flex = 1, minWidth = 130, height = 10 }, UI.HStack { width = 10, height = 10 } } },
    { label = "column with flexible minima", horizontal = false, flex = true, padEnd = 5, crossEnd = 5,
      el = UI.VStack { tag = "s", padding = 5, gap = 10, align = "start", UI.HStack { flex = 1, minHeight = 120, width = 20 }, UI.HStack { flex = 1, width = 30 }, UI.HStack { width = 40, height = 20 } } },
  }
  for _, case in ipairs(cases) do
    local outer = case.horizontal and UI.VStack { case.el } or UI.HStack { align = "stretch", case.el }
    local root = UI.mount(host, outer)
    local s = find(root, case.horizontal and "HStack" or "VStack", function(n) return n.el.props.tag == "s" end)[1]
    inside(s, case.label)
    local mw, mh
    if case.horizontal then mw, mh = I.measure(s, 200, nil) else mw, mh = I.measure(s, nil, 200) end
    local cross = extent(s, not case.horizontal, case.crossEnd)
    eq(case.horizontal and mh or mw, cross, case.label .. ": measured cross size equals the placed extent")
    local main = extent(s, case.horizontal, case.padEnd)
    if case.flex then
      eq(main, 200, case.label .. ": flexible children fill the stack exactly")
    else
      eq(case.horizontal and mw or mh, main, case.label .. ": measured main size equals the placed extent")
    end
    root:unmount()
  end
end)

test("layout: a flexible child's minimum applies only along the stack's main axis", function()
  local host = CreateFrame("Frame")
  host:SetSize(100, 100)
  -- A row ignores minHeight when sharing widths, and a column ignores minWidth.
  local root = UI.mount(host, UI.HStack { gap = 0, align = "start",
    UI.HStack { tag = "a", flex = 1, minHeight = 80 }, UI.HStack { tag = "b", flex = 1 } })
  local function tagged(name, tag)
    return find(root, name, function(n) return n.el.props.tag == tag end)[1]
  end
  eq(tagged("HStack", "a").w, 50, "row: minHeight is not a width minimum")
  eq(tagged("HStack", "b").w, 50, "row: the other child gets an equal share")
  eq(tagged("HStack", "a").h, 80, "row: minHeight still holds across the row")
  local mw = I.measure(find(root, "HStack")[1], nil, nil)
  eq(mw, 0, "row: measured main size counts no cross-axis minimum")
  root:unmount()

  root = UI.mount(host, UI.VStack { gap = 0, align = "start",
    UI.VStack { tag = "a", flex = 1, minWidth = 80 }, UI.VStack { tag = "b", flex = 1 } })
  eq(tagged("VStack", "a").h, 50, "column: minWidth is not a height minimum")
  eq(tagged("VStack", "b").h, 50, "column: the other child gets an equal share")
  eq(tagged("VStack", "a").w, 80, "column: minWidth still holds across the column")
  local _, mh = I.measure(find(root, "VStack")[1], nil, nil)
  eq(mh, 0, "column: measured main size counts no cross-axis minimum")
  root:unmount()
end)

test("scroll: content keeps its natural size along every scrolling axis", function()
  local host = CreateFrame("Frame")
  host:SetSize(100, 100)
  local long = string.rep("word ", 40)

  -- Horizontal: a wrapping text is not squeezed to the view width.
  local root = UI.mount(host, UI.ScrollView { direction = "horizontal", gap = 0, UI.Text { text = long, wrap = true } })
  local view = find(root, "ScrollView")[1]
  local text = find(root, "Text")[1]
  ok(text.w > 700, "horizontal: the text keeps its natural width, got " .. tostring(text.w))
  eq(view.region.fxScroller.maxX, text.w - 100, "horizontal: the range covers the whole text")
  root:unmount()

  -- Content that takes whatever it is offered (up to 500) along each axis.
  I.defineHost("TestTakeOffered", {
    update = I.noop,
    measure = function(_, maxW, maxH)
      return math.min(maxW, 500), math.min(maxH, 500)
    end,
  })
  local cases = {
    { direction = "vertical", maxX = 0, maxY = 400 },
    { direction = "horizontal", maxX = 400, maxY = 0 },
  }
  for _, case in ipairs(cases) do
    root = UI.mount(host, UI.ScrollView { direction = case.direction, gap = 0, UI.TestTakeOffered {} })
    local sc = find(root, "ScrollView")[1].region.fxScroller
    eq(sc.maxX, case.maxX, case.direction .. ": horizontal range")
    eq(sc.maxY, case.maxY, case.direction .. ": vertical range")
    root:unmount()
  end
  root = UI.mount(host, UI.ScrollView { direction = "both", gap = 0, UI.TestTakeOffered {} })
  local sc = find(root, "ScrollView")[1].region.fxScroller
  ok(sc.contentW >= 500 and sc.contentH >= 500, "both: content is unbounded on both axes, got "
    .. tostring(sc.contentW) .. " x " .. tostring(sc.contentH))
  root:unmount()
end)

test("layout: text that stops wrapping is measured at one line, also from a pooled region", function()
  local long = string.rep("word ", 8)
  local function tree()
    return UI.VStack { align = "start", UI.Text { text = long, wrap = true }, UI.Button { text = "Go" } }
  end
  -- Reference: the tree laid out at 800 from fresh.
  local host = CreateFrame("Frame")
  host:SetSize(800, 400)
  local root = UI.mount(host, tree())
  local wantH, wantY = find(root, "Text")[1].h, find(root, "Button")[1].y
  root:unmount()
  ok(wantH < 20, "one line at 800, got " .. tostring(wantH))

  -- Wrapped at 100, then widened to 800: one layout gets it right.
  host:SetSize(100, 400)
  root = UI.mount(host, tree())
  ok(find(root, "Text")[1].h > wantH, "wraps at 100")
  host:SetSize(800, 400)
  UI.flush()
  eq(find(root, "Text")[1].h, wantH, "widened: the text is one line high")
  eq(find(root, "Button")[1].y, wantY, "widened: the button follows the text")
  root:unmount()

  -- A pooled region that last held wrapped text at 100 measures the same.
  host:SetSize(100, 400)
  root = UI.mount(host, UI.Text { text = long, wrap = true })
  root:unmount()
  host:SetSize(800, 400)
  root = UI.mount(host, tree())
  eq(find(root, "Text")[1].h, wantH, "pooled: the text is one line high")
  eq(find(root, "Button")[1].y, wantY, "pooled: the button follows the text")
  root:unmount()
end)

test("layout: width props bound content before it is measured", function()
  local host = CreateFrame("Frame")
  host:SetSize(500, 400)
  -- A component's width wins over the width of the row it renders: three
  -- 90 px chips in 100 px take three lines, and the next sibling follows.
  local Narrow = UI.component("TestNarrowRow", function()
    local chips = {}
    for i = 1, 3 do chips[i] = UI.HStack { width = 90, height = 20 } end
    return UI.HStack { width = 300, wrap = true, chips }
  end)
  local root = UI.mount(host, UI.VStack { align = "start", Narrow { width = 100 }, UI.HStack { tag = "next", width = 10, height = 10 } })
  local row = find(root, "HStack", function(n) return n.el.props.wrap end)[1]
  local nextNode = find(root, "HStack", function(n) return n.el.props.tag == "next" end)[1]
  eq(row.w, 100, "the component's width wins")
  eq(row.h, 60, "measured at that width: three lines")
  ok(nextNode.y >= row.y + row.h, "the next sibling starts below the row: " .. tostring(nextNode.y))
  root:unmount()

  -- A wrapping text with maxWidth in a wide start-aligned column wraps
  -- within maxWidth and gets the height its lines need.
  root = UI.mount(host, UI.VStack { align = "start", UI.Text { text = string.rep("word ", 8), wrap = true, maxWidth = 100 } })
  local text = find(root, "Text")[1]
  eq(text.w, 100, "clamped to maxWidth")
  ok(not text.region:IsTruncated(), "every line fits: " .. tostring(text.h))
  local _, h = I.measure(text, 100, nil)
  eq(text.h, h, "as tall as its lines at 100")
  root:unmount()
end)

-- Layout invariants over representative trees at several sizes, under the
-- given theme (nil: the global one). Themes change metrics, fonts and window
-- chrome, so each shipped theme runs them.
local function layoutInvariants(theme)
  local opts = theme and { theme = theme } or nil
  local EPS = 0.001
  local long = string.rep("word ", 12)
  local function chips(n, w, h)
    local out = {}
    for i = 1, n do out[i] = UI.HStack { width = w or (40 + (i % 3) * 15), height = h or (16 + (i % 2) * 8) } end
    return out
  end
  local Card = UI.component("TestInvariantCard", function(props)
    return UI.VStack { width = 300, gap = 4, padding = 4, UI.Text { text = props.text, wrap = true }, UI.HStack { wrap = true, gap = 4, chips(3, 90, 20) } }
  end)
  local Row = UI.component("TestInvariantRow", function()
    return UI.HStack { width = 300, wrap = true, gap = 0, chips(3, 90, 20) }
  end)
  local Label = UI.component("TestInvariantLabel", function(props)
    return UI.Text { text = props.text, wrap = true, maxWidth = 400 }
  end)

  -- Each tree fills a host frame (or, for a window, is the window).
  local cases = {
    { name = "column, align start, padding and gaps", el = function() return UI.VStack { align = "start", padding = { 6, 8 }, gap = 4,
      UI.Text { text = "Title", style = "title" }, UI.Text { text = long, wrap = true }, UI.Button { text = "Go" },
      UI.HStack { width = 40, height = 10 }, UI.Spacer { size = 6 }, UI.Divider {} } end },
    { name = "column, align center, flex and minima", el = function() return UI.VStack { align = "center", gap = 6,
      UI.HStack { height = 20, UI.Text { text = "Head" } }, UI.HStack { flex = 1, minHeight = 30 }, UI.Text { text = long, wrap = true },
      UI.VStack { flex = 2, minHeight = 10, UI.Text { text = "in a flexible column" } }, UI.Button { text = "Done" } } end },
    { name = "column, align end, justify center", el = function() return UI.VStack { align = "end", justify = "center", gap = 3,
      UI.Text { text = long, wrap = true }, UI.Badge { text = "new" }, UI.Dot { size = 10 } } end },
    { name = "column, align stretch, justify between", el = function() return UI.VStack { justify = "between", padding = 5,
      UI.Text { text = long, wrap = true }, UI.HStack { height = 12 }, UI.Button { text = "Wide" } } end },
    { name = "row, justify between, padding", el = function() return UI.HStack { justify = "between", padding = { 4, 6 }, gap = 8,
      UI.Button { text = "One" }, UI.Text { text = "Two" }, UI.Dot {} } end },
    { name = "row, justify end, align end", el = function() return UI.HStack { justify = "end", align = "end", gap = 8,
      UI.Text { text = "Label" }, UI.HStack { width = 30, height = 30 }, UI.Button { text = "Act" } } end },
    { name = "row, flex minima beside fixed children", el = function() return UI.HStack { gap = 6, align = "start",
      UI.HStack { flex = 2, minWidth = 40, height = 12 }, UI.VStack { flex = 1, minWidth = 30, UI.Text { text = long, wrap = true } },
      UI.Button { text = "Fixed" } } end },
    { name = "row, align stretch with a spacer", el = function() return UI.HStack { align = "stretch", gap = 4,
      UI.Text { text = "Left" }, UI.Spacer {}, UI.Button { text = "Right" } } end },
    { name = "wrapping row, justify center, align end", el = function() return UI.VStack { align = "start",
      UI.HStack { wrap = true, gap = 6, rowGap = 4, justify = "center", align = "end", padding = 3, chips(7), UI.Text { text = "tail" } } } end },
    { name = "wrapping row, align stretch, justify between", el = function() return UI.VStack {
      UI.HStack { wrap = true, gap = 5, align = "stretch", justify = "between", chips(9) } } end },
    { name = "wrapping text with width, maxWidth and minWidth", el = function() return UI.VStack { align = "start", gap = 2,
      UI.Text { text = long, wrap = true, width = 120 }, UI.Text { text = long, wrap = true, maxWidth = 150 },
      UI.Text { text = "short", wrap = true, minWidth = 90 }, UI.Text { text = long, wrap = true, maxWidth = 90, minWidth = 60 } } end },
    { name = "wrapping text with maxWidth, centred", el = function() return UI.VStack { align = "center",
      UI.Text { text = long, wrap = true, maxWidth = 150 }, UI.HStack { height = 10, width = 10 } } end },
    { name = "components with width props over containers", el = function() return UI.VStack { align = "start", gap = 4,
      Row { width = 100 }, Card { text = long, width = 160 }, Card { text = "short" }, Label { text = long, maxWidth = 120 } } end },
    -- In a stretching column, so the row is placed at the width it is
    -- measured at (a start-aligned column places a row with a flexible child
    -- at its minimum width, by design). The flexible card's share wins over
    -- the width its render gives.
    { name = "component flexing beside a fixed component", el = function() return UI.VStack {
      UI.HStack { gap = 4, align = "start", Row { width = 100 }, Card { text = long, flex = 1 } } } end },
    { name = "scroll view, vertical", el = function() return UI.ScrollView { gap = 4, padding = 4,
      UI.Text { text = long, wrap = true }, UI.HStack { height = 120 }, UI.HStack { wrap = true, gap = 4, chips(6) }, UI.HStack { flex = 1, minHeight = 20 } } end },
    { name = "scroll view, horizontal", el = function() return UI.ScrollView { direction = "horizontal", gap = 10,
      chips(8, 50, 20), UI.Text { text = long, wrap = true } } end },
    { name = "scroll view, both", el = function() return UI.ScrollView { direction = "both",
      UI.VStack { gap = 2, UI.HStack { width = 360, height = 90 }, UI.HStack { width = 200, height = 90 } }, UI.Text { text = long, wrap = true } } end },
    { name = "window body", window = true, el = function(w, h) return UI.Window { title = "Invariants", width = w, height = h, gap = 6, padding = 8,
      UI.Text { text = long, wrap = true }, UI.HStack { gap = 4, UI.Button { text = "A" }, UI.Spacer {}, UI.Button { text = "B" } },
      UI.HStack { wrap = true, gap = 4, chips(6) }, UI.VStack { flex = 1, minHeight = 20 } } end },
    { name = "window body without scrolling", window = true, el = function(w, h) return UI.Window { title = "Fixed", width = w, height = h, scroll = false, gap = 4,
      Card { text = long, width = 200 }, UI.Text { text = long, wrap = true, maxWidth = 180 }, UI.VStack { flex = 1 } } end },
  }
  local sizes = { { 100, 900 }, { 240, 500 }, { 380, 260 }, { 520, 640 }, { 800, 120 } }

  local origMeasure = I.measure
  local function hostOf(node)
    while node and node.def do node = node.child end
    return node
  end
  local function hosts(root)
    local out = {}
    walk(root.node, function(n) if n.host then out[#out + 1] = n end end)
    return out
  end
  local function r(v) return v and string.format("%.3f", v) or "-" end
  local function snapshot(root)
    local out = {}
    for _, n in ipairs(hosts(root)) do
      local s = n.host.name .. " " .. r(n.x) .. "," .. r(n.y) .. " " .. r(n.w) .. "x" .. r(n.h)
      if n.region and n.region.GetSize then
        local rw, rh = n.region:GetSize()
        s = s .. " region " .. r(rw) .. "x" .. r(rh)
      end
      local sc = n.region and (n.region.fxScroller or (n.region.body and n.region.body.fxScroller))
      if sc then
        s = s .. " scroll " .. table.concat({ r(sc.offsetX), r(sc.offsetY), r(sc.maxX), r(sc.maxY), r(sc.contentW), r(sc.contentH), r(sc.viewW), r(sc.viewH) }, ",")
      end
      out[#out + 1] = s
    end
    return out
  end
  local violations = {}
  local function report(case, size, what)
    violations[#violations + 1] = case.name .. " @" .. size[1] .. "x" .. size[2] .. ": " .. what
  end
  local function same(case, size, label, a, b)
    if #a ~= #b then return report(case, size, label .. ": " .. #a .. " nodes vs " .. #b) end
    for i = 1, #a do
      if a[i] ~= b[i] then return report(case, size, label .. ": node " .. i .. ": " .. a[i] .. " vs " .. b[i]) end
    end
  end

  local function mount(case, size, frame)
    if case.window then return UI.mount(frame, case.el(size[1], size[2]), opts) end
    frame:SetSize(size[1], size[2])
    return UI.mount(frame, case.el(), opts)
  end
  local function resize(case, root, frame, size)
    if case.window then
      root.node.region:SetSize(size[1], size[2])
    else
      frame:SetSize(size[1], size[2])
    end
    UI.flush()
  end
  -- Lay out with no pooled regions, so nothing a region kept can matter.
  local function fresh(case, size)
    local saved = I.pools
    I.pools = {}
    local frame = CreateFrame("Frame")
    local root = mount(case, size, frame)
    local snap = snapshot(root)
    root:unmount()
    I.pools = saved
    return snap
  end

  -- How a stack-like parent lays out a child: main axis, whether the child
  -- flexes or stretches, and the box children must stay in.
  local function arrangement(parent, top)
    local p, name = parent.el.props, parent.host.name
    if name == "HStack" then
      return { horizontal = true, wrap = p.wrap, align = p.align or "center", boxW = parent.w, boxH = parent.h }
    elseif name == "VStack" then
      return { horizontal = false, align = p.align or "stretch", boxW = parent.w, boxH = parent.h }
    elseif name == "ScrollView" then
      local dir = p.direction or "vertical"
      local sc = parent.region.fxScroller
      return { horizontal = dir == "horizontal", align = p.align or (dir == "vertical" and "stretch" or "start"), boxW = sc.contentW, boxH = sc.contentH }
    elseif name == "Window" then
      for _, c in ipairs(parent.children or {}) do
        if c == top then
          local sc = parent.region.body.fxScroller
          return { horizontal = false, align = "stretch", boxW = sc.contentW, boxH = sc.contentH }
        end
      end
    end
  end

  local function checkPlacement(case, size, root)
    for _, n in ipairs(hosts(root)) do
      local top, parent = n, n.parent
      while parent and parent.def do top, parent = parent, parent.parent end
      local how = parent and arrangement(parent, top)
      if how and n.host.name ~= "Spacer" then
        local label = n.host.name .. (n.el.props.text and (" '" .. n.el.props.text:sub(1, 12) .. "'") or "")
        -- Inside the parent's box (a scrolling parent's box is its content).
        if n.x < -EPS or n.y < -EPS or n.x + n.w > how.boxW + EPS or n.y + n.h > how.boxH + EPS then
          report(case, size, label .. " at " .. r(n.x) .. "," .. r(n.y) .. " " .. r(n.w) .. "x" .. r(n.h)
            .. " outside its parent's " .. r(how.boxW) .. "x" .. r(how.boxH))
        end
        -- A leaf's content fits the box it got: measured at that box, it
        -- needs no more.
        if not n.host.container then
          local mw, mh = origMeasure(n, n.w, n.h)
          if mw > n.w + EPS or mh > n.h + EPS then
            report(case, size, label .. " needs " .. r(mw) .. "x" .. r(mh) .. " in its " .. r(n.w) .. "x" .. r(n.h) .. " box")
          end
        end
        local seen = n.fxSeen
        if not seen then
          report(case, size, label .. " was placed without being measured")
        else
          local flex = (not how.wrap) and (I.layoutProp(top, "flex") or 0) > 0
          local stretch = (I.layoutProp(top, "alignSelf") or how.align) == "stretch"
          local mainPlaced, crossPlaced = n.w, n.h
          local mainSeen, crossSeen = seen.w, seen.h
          if not how.horizontal then
            mainPlaced, crossPlaced, mainSeen, crossSeen = n.h, n.w, seen.h, seen.w
          end
          -- A flexible child is placed at its share, not its measured main
          -- size (stacks report it at its minimum by design); a stretched
          -- child fills the cross axis whatever it measured.
          if not flex and math.abs(mainPlaced - mainSeen) > EPS then
            report(case, size, label .. " measured " .. r(mainSeen) .. " but placed at " .. r(mainPlaced) .. " along the main axis")
          end
          if not stretch and math.abs(crossPlaced - crossSeen) > EPS then
            report(case, size, label .. " measured " .. r(crossSeen) .. " but placed at " .. r(crossPlaced) .. " across")
          end
        end
      end
    end
  end

  I.measure = function(node, maxW, maxH, exact)
    local w, h = origMeasure(node, maxW, maxH, exact)
    local n = hostOf(node)
    if n then n.fxSeen = { w = w, h = h } end
    return w, h
  end
  local passed, err = pcall(function()
    for _, case in ipairs(cases) do
      local checked = 0
      for i, size in ipairs(sizes) do
        local want = fresh(case, size)
        local frame = CreateFrame("Frame")
        local root = mount(case, size, frame)
        same(case, size, "fresh mount vs mount without pooled regions", snapshot(root), want)

        -- Idempotence: a second layout moves and resizes nothing.
        local before = snapshot(root)
        local fits = true
        if not case.window then
          local mw, mh = origMeasure(root.node, size[1], size[2])
          fits = mw <= size[1] + EPS and mh <= size[2] + EPS
        else
          -- A window body scrolls vertically at most, so its content must fit
          -- across (and, without scrolling, down too).
          local p, sc = root.node.el.props, root.node.region.body.fxScroller
          local mw, mh = I.stackMeasure(root.node.children, { gap = p.gap, padding = p.padding }, false, sc.contentW, nil)
          fits = mw <= sc.contentW + EPS and (p.scroll ~= false or mh <= sc.contentH + EPS)
        end
        root:layout()
        same(case, size, "second layout", snapshot(root), before)
        -- Measure = place, and children inside their parents, wherever the
        -- tree fits its frame (content too big for a box that does not
        -- scroll overflows by design).
        if fits then
          checked = checked + 1
          checkPlacement(case, size, root)
        end

        -- Resize independence: from every other size to this one.
        for j, from in ipairs(sizes) do
          if j ~= i then
            resize(case, root, frame, from)
            resize(case, root, frame, size)
            same(case, size, "resized from " .. from[1] .. "x" .. from[2], snapshot(root), want)
          end
        end
        root:unmount()

        -- A pooled region reused at this size: lay out at another size,
        -- release, and mount again here.
        local other = sizes[i % #sizes + 1]
        local f2 = CreateFrame("Frame")
        local r2 = mount(case, other, f2)
        r2:unmount()
        r2 = mount(case, size, f2)
        same(case, size, "pooled from " .. other[1] .. "x" .. other[2], snapshot(r2), want)
        r2:unmount()
      end
      if checked == 0 then violations[#violations + 1] = case.name .. ": fits no size, so placement went unchecked" end
    end
  end)
  I.measure = origMeasure
  if not passed then error(err, 0) end
  if #violations > 0 then error(#violations .. " violations:\n  " .. table.concat(violations, "\n  "), 0) end
end

test("layout: invariants hold over representative trees at several sizes", function()
  layoutInvariants(nil)
end)

test("table: mixed-type columns sort the same way from every starting order", function()
  local values = { 2, 10, "11", "b", "A" }
  local function permutations(list)
    local out = {}
    local function go(prefix, rest)
      if #rest == 0 then out[#out + 1] = prefix return end
      for i = 1, #rest do
        local p, r = { unpack(prefix) }, { unpack(rest) }
        p[#p + 1] = table.remove(r, i)
        go(p, r)
      end
    end
    go({}, list)
    return out
  end
  local col = { key = "v" }
  local function order(items)
    local s = {}
    for i, it in ipairs(items) do s[i] = tostring(it.v) end
    return table.concat(s, ",")
  end
  local asc, desc
  for _, perm in ipairs(permutations(values)) do
    local items = {}
    for i, v in ipairs(perm) do items[i] = { v = v } end
    items[#items + 1] = { v = nil }
    local a, d = order(UI.sortItems(items, col, false)), order(UI.sortItems(items, col, true))
    asc, desc = asc or a, desc or d
    eq(a, asc, "ascending order does not depend on the input order")
    eq(d, desc, "descending order does not depend on the input order")
  end
  -- A mixed column compares every value as a string.
  eq(asc, "10,11,2,A,b,nil")
  eq(desc, "b,A,2,11,10,nil")
  -- A column of one type keeps that type's order.
  for _, d in ipairs({ false, true }) do
    local sorted = UI.sortItems({ { v = 10 }, { v = 2 }, { v = 0 / 0 }, { v = 11 } }, col, d)
    eq(order({ sorted[1], sorted[2], sorted[3] }), d and "11,10,2" or "2,10,11", "a column of numbers sorts numerically")
    ok(sorted[4].v ~= sorted[4].v, "NaN has no value and goes last")
  end
  eq(order(UI.sortItems({ { v = true }, { v = false } }, col, false)), "false,true", "values that have no order compare as strings")
end)

---------------------------------------------------------------------------
-- Theme addons: Teal and Classic
---------------------------------------------------------------------------

-- The color a texture was filled with: vertex color over a shape, or a
-- color texture.
local function fillOf(tex)
  local c = tex._vertex or tex._color
  return c[1], c[2], c[3]
end

local function near(a, b, msg)
  ok(math.abs(a - b) < 0.002, (msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

test("teal: registers the default theme with a teal accent and nothing else", function()
  local def = UI.themes.teal
  ok(def, "teal registered")
  eq(def.title, "FxUI Teal")
  eq(def.base, "default")
  local keys = {}
  for k in pairs(def) do keys[#keys + 1] = k end
  table.sort(keys)
  eq(table.concat(keys, ","), "base,colors,name,title", "overrides colors only")
  local colors = {}
  for k in pairs(def.colors) do colors[#colors + 1] = k end
  table.sort(colors)
  eq(table.concat(colors, ","), "gold,onGold", "overrides gold and onGold only")

  local teal, base = I.resolve("teal"), I.resolve("default")
  eq(teal.title, "FxUI Teal")
  eq(teal.gold.hex, "#3FC1B0")
  eq(teal.onGold.hex, "#06201C")
  local checked = 0
  for k, v in pairs(base) do
    if type(v) == "table" and v.hex and k ~= "gold" and k ~= "onGold" then
      eq(teal[k].hex, v.hex, "color " .. k .. " is the default theme's")
      checked = checked + 1
    end
  end
  ok(checked > 10, "compared every other color")
  for token, spec in pairs(base.fontSpecs) do
    eq(teal.fontSpecs[token].path, spec.path, "font " .. token)
    eq(teal.fontSpecs[token].size, spec.size, "font size " .. token)
  end
  ok(teal.fonts.body ~= base.fonts.body, "its own font objects")
  eq(teal.money, base.money)
  for component, m in pairs(base.metrics) do
    for k, v in pairs(m) do
      if type(v) ~= "table" then eq(teal.metrics[component][k], v, "metric " .. component .. "." .. k) end
    end
  end
  eq(next(teal.skins), nil, "no skins")

  -- Teal as the global theme: a primary button is filled with the accent.
  UI.setTheme("teal")
  local host = CreateFrame("Frame")
  host:SetSize(200, 50)
  local root = UI.mount(host, UI.Button { text = "Go", variant = "primary" })
  local b = find(root, "Button")[1].region
  local r, g, bl = fillOf(b.fxBg)
  near(r, teal.gold.r, "red"); near(g, teal.gold.g, "green"); near(bl, teal.gold.b, "blue")
  eq(b.label._color[1], teal.onGold.r, "label in onGold")
  root:unmount()
  UI.setTheme("default")
end)

test("classic: client fonts with shadows, coin icons and the client's colors", function()
  local def = UI.themes.classic
  ok(def, "classic registered")
  eq(def.title, "Classic")
  eq(def.base, "default")
  local c = I.resolve("classic")
  local FRIZ, MORPHEUS, ARIAL = "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.TTF", "Fonts\\ARIALN.TTF"
  local want = { display = MORPHEUS, title = FRIZ, body = FRIZ, strong = FRIZ, label = FRIZ, small = FRIZ, mono = ARIAL, monoSmall = ARIAL }
  for token, path in pairs(want) do
    eq(c.fontSpecs[token].path, path, "font " .. token)
    ok(c.fontSpecs[token].shadow, "font " .. token .. " has a shadow")
    eq((c.fonts[token]:GetFont()), path, "font object " .. token)
    ok(c.fonts[token] ~= I.resolve("default").fonts[token], "own font object " .. token)
  end
  eq(c.money, "icons")
  local colors = {
    ground = "#000000", panel = "#0B0B0B", raised = "#1E1E1E", line = "#5A4A2A", text = "#FFFFFF",
    muted = "#FFD100", gold = "#FFD100", onGold = "#000000", info = "#69CCF0", up = "#1EFF00",
    down = "#FF3030", warn = "#FF8000", poor = "#9D9D9D", common = "#FFFFFF", uncommon = "#1EFF00",
    rare = "#0070DD", epic = "#A335EE", legendary = "#FF8000",
  }
  for token, hex in pairs(colors) do eq(c[token].hex, hex, "color " .. token) end
  -- The client's Rare and Epic stay below the default theme's 4.5:1 on purpose.
  local rare, epic = UI.contrast(c.rare, c.panel), UI.contrast(c.epic, c.panel)
  ok(rare > 4 and rare < 4.5, "rare about 4.1:1, got " .. rare)
  ok(epic > 3.9 and epic < 4.5, "epic about 4.0:1, got " .. epic)

  -- Metrics from the spec.
  local m = c.metrics
  eq(m.Button.sizes.sm.height, 20); eq(m.Button.sizes.md.height, 22); eq(m.Button.sizes.lg.pad, 18)
  eq(m.Toggle.width, 24); eq(m.Toggle.gap, 4)
  eq(m.Tab.height, 30); eq(m.Tab.gap, -10); eq(m.Tab.rail, 5); eq(m.Tab.railColor, "#666666")
  ok(m.Tab.openSelected and m.Tab.railAbove and not m.Tab.railHighlight, "tab rail flags")
  eq(m.Badge.height, 18); eq(m.Meter.barHeight, 16); ok(m.Meter.inlineValue)
  eq(m.HeaderCell.height, 19); eq(m.Scroll.width, 18); eq(m.Scroll.thumb, 16)
  eq(m.Window.status, "footer"); eq(m.Window.actions, "footer")
  eq(m.Window.md.header, 34); eq(m.Window.sm.header, 30); ok(m.Window.md.banner and m.Window.sm.banner)

  -- Coin icons inside a Classic tree only, then everywhere once Classic is global.
  local host = CreateFrame("Frame")
  host:SetSize(200, 50)
  local root = UI.mount(host, UI.Money { value = 123456 }, { theme = "classic" })
  ok(find(root, "Money")[1].region:GetText():find("UI-GoldIcon", 1, true), "coin icons inside the tree")
  root:unmount()
  eq(UI.formatMoney(123456), "12g 34s 56c", "letters outside it")
  UI.setTheme("classic")
  ok(UI.formatMoney(123456):find("UI-GoldIcon", 1, true), "coin icons with Classic global")
  UI.setTheme("default")
end)

test("classic: skins draw with client art and clean up when switching back", function()
  local host = CreateFrame("Frame")
  host:SetSize(300, 100)
  local root = UI.mount(host, UI.HStack { UI.Button { text = "Go" }, UI.Toggle { label = "On", checked = true } }, { theme = "classic" })
  local b = find(root, "Button")[1].region
  ok(b.fxSkinTex and b.fxSkinTex.bgL:IsShown(), "panel button slices")
  eq(b.fxSkinTex.bgM._texture, "Interface\\Buttons\\UI-Panel-Button-Up")
  ok(not (b.fxBg and b.fxBg:IsShown()), "no flat background")
  local t = find(root, "Toggle")[1].region
  ok(t.fxSkinTex.check:IsShown() and not t.track:IsShown(), "checkbox instead of the pill")
  root:update(UI.HStack { UI.Button { text = "Go" }, UI.Toggle { label = "On", checked = true } })
  root:unmount()
  root = UI.mount(host, UI.HStack { UI.Button { text = "Go" }, UI.Toggle { label = "On", checked = true } })
  b = find(root, "Button")[1].region
  ok(not b.fxSkinTex.bgL:IsShown(), "pooled button: classic slices hidden under the default theme")
  ok(b.fxBg and b.fxBg:IsShown(), "default background back")
  t = find(root, "Toggle")[1].region
  ok(t.track:IsShown() and not t.fxSkinTex.check:IsShown(), "pill back")
  root:unmount()

  -- Tabs, title banner, rows and header cells, then back to the default.
  local items = { { id = 1, v = "a" }, { id = 2, v = "b" } }
  local function view(theme)
    return UI.Window { title = "Classic", width = 400, height = 300, theme = theme,
      UI.TabBar { tabs = { { id = "x", text = "One" }, { id = "y", text = "Two" } }, selected = "x" },
      UI.Table { flex = 1, items = items, key = "id", selected = 2, onSelect = function() end,
        columns = { { key = "v", title = "Value", flex = 1 } } },
    }
  end
  root = UI.mount(UIParent, view("classic"))
  local tabs = find(root, "Tab")
  local sel = tabs[1].region
  eq(sel.fxSkinTex.onM._texture, "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab", "selected tab uses the top tab art")
  local other = tabs[2].region.fxSkinTex
  eq(other.onM._texture, "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab", "other tabs the same full-height art")
  ok(other.onM._vertex[1] < 1, "darkened")
  eq(other.onL._points[1][5], -6.25, "inactive tabs hang like the selected one")
  eq(sel.fxSkinTex.onL._points[1][5], -6.25, "so their feet land on the rail")
  local railNode = find(root, "TabRail")[1]
  ok(railNode.region:GetFrameLevel() > tabs[2].region:GetFrameLevel(), "the rail crosses over the tabs")
  local win = find(root, "Window")[1].region
  ok(win.header.fxSkinTex.bannerM:IsShown(), "title banner")
  local header = find(root, "HeaderCell")[1].region
  eq(header.fxSkinTex.colM._texture, "Interface\\FriendsFrame\\WhoFrame-ColumnTabs", "column header art")
  -- The rail under the tabs opens under the selected tab, measured from the
  -- selected tab's art on screen.
  local rail = find(root, "TabRail")[1]
  local railLeft = rail.region:GetLeft()
  local artL, artR = sel.fxSkinTex.onL:GetLeft(), sel.fxSkinTex.onR:GetRight()
  ok(math.abs(rail.region.left._w - (artL + 9.5 - railLeft)) < 0.01, "rail runs in under the tab's left flare: " .. rail.region.left._w)
  ok(math.abs(rail.region.right._points[1][4] - (artR - 9.5 - railLeft)) < 0.01, "and resumes under the right flare")
  ok(rail.region.left.fxInner and rail.region.left.fxInner._backdrop, "rail drawn with border art")
  eq(sel.label._points[1][5], -3.75, "selected tab text")
  eq(tabs[2].region.label._points[1][5], -3.75, "same text offset in every tab")
  -- With nothing in the header, the classic header is a thin strip.
  eq(win.header._h, 14, "compact header under the banner")
  local list = find(root, "List")[1]
  ok(list.children[2].region.fxSkinTex.rowHL:IsShown(), "selected row highlighted")
  ok(not list.children[1].region.fxSkinTex.rowHL:IsShown(), "other row plain")
  root:update(view(nil))
  sel = find(root, "Tab")[1].region
  ok(not sel.fxSkinTex.onM:IsShown(), "classic tab art hidden under the default theme")
  ok(not sel.underline:IsShown(), "default tabs carry no underline of their own")
  rail = find(root, "TabRail")[1]
  ok(not rail.region.right:IsShown() or rail.region.left._w >= rail.w - 0.5, "default rail is continuous")
  ok(rail.region.mark:IsShown(), "the selected tab is marked on the line")
  local selNode = find(root, "Tab")[1]
  ok(math.abs(rail.region.mark._points[1][4] - (selNode.region:GetLeft() - rail.region:GetLeft())) < 0.01, "mark under the selected tab")
  eq(rail.region.mark._w, selNode.w, "mark as wide as the tab")
  ok(not win.header.fxSkinTex.bannerM:IsShown(), "banner hidden")
  ok(not find(root, "List")[1].children[2].region.fxSkinTex.rowHL:IsShown(), "row highlight hidden")
  root:unmount()
end)

test("classic: window status and actions move to a footer status bar", function()
  local clicked
  local function view(theme)
    return UI.Window { title = "Acts", width = 400, height = 300, theme = theme,
      actions = { { text = "Do", onClick = function() clicked = true end } },
      status = "status",
      UI.Text { text = "body" },
    }
  end
  local function textsIn(list)
    local out = {}
    for _, n in ipairs(list or {}) do if n.el.props.text then out[#out + 1] = n.el.props.text end end
    return table.concat(out, ",")
  end
  local root = UI.mount(UIParent, view(nil))
  eq(textsIn(find(root, "Window")[1].headerChildren), "status,Do", "default theme: in the header")
  root:update(view("classic"))
  local win = find(root, "Window")[1]
  eq(textsIn(win.headerChildren), "", "classic: header keeps only the title and close")
  eq(textsIn(win.footerChildren), "status,Do", "classic: actions in the footer after the status")
  ok(win.region.footer:IsShown(), "footer shown")
  ok(win.region.footer.fxHasBackdrop, "classic footer drawn as a status bar")
  eq(win.region.footer._backdrop.edgeFile, "Interface\\Tooltips\\UI-Tooltip-Border", "framed like a tooltip")
  local _, _, fw = win.region.footer:GetRect()
  local _, _, ww = win.region:GetRect()
  eq(fw, ww - 2 * 10, "footer spans the full width inside the border")
  local action = find(root, "Button", function(n) return n.el.props.text == "Do" end)[1]
  eq(action.el.props.variant, "secondary", "actions as secondary buttons")
  ok(action.region.fxSkinTex.bgM:IsShown(), "drawn as panel buttons")
  action.region:_click()
  ok(clicked, "action runs")
  ok(win.region.close.fxSkinTex.up:IsShown(), "red close button")
  eq(win.region.close.fxSkinTex.up._texture, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  root:unmount()
end)

test("classic: every component draws with client art in every state; pooled regions are clean afterwards", function()
  W.items[17] = true
  local items = {}
  for i = 1, 30 do items[i] = { id = i, v = "r" .. i } end
  local function view(theme, size)
    return UI.Window { title = "Classic", width = 560, height = 760, size = size, theme = theme, status = "s",
      UI.HStack { gap = 4,
        UI.Button { text = "Go" },
        UI.Button { text = "Ghost", variant = "ghost" },
        UI.Button { text = "Off", disabled = true },
        UI.Badge { text = "B", tone = "info" },
        UI.Badge { text = "S", tone = "gold", solid = true },
        UI.Toggle { label = "On", checked = true },
        UI.Toggle { label = "Off", checked = true, disabled = true },
      },
      UI.TabBar { tabs = { { id = "x", text = "One", count = 3 }, { id = "y", text = "Two" } }, selected = "x" },
      UI.ItemCell { item = 17 },
      UI.Meter { value = 5, max = 10, label = "Fill", valueText = "5/10", tone = "info" },
      UI.VStack { surface = "card", UI.Text { text = "card" } },
      UI.VStack { surface = "inset", UI.Text { text = "inset" } },
      UI.Chart { width = 200, height = 100, values = { 1, 2, 3 } },
      UI.Table { height = 120, items = items, key = "id", selected = 2, onSelect = function() end,
        columns = { { key = "v", title = "Value", flex = 1 } } },
      UI.ScrollView { direction = "both", width = 100, height = 60, UI.HStack { width = 300, height = 200 } },
    }
  end
  local root = UI.mount(UIParent, view("classic"))
  local C = I.resolve("classic")

  -- Buttons: panel art, gold text, white on hover, pressed art and offset,
  -- disabled art and gray text; ghost buttons are text only.
  local buttons = find(root, "Button", function(n) return n.parent and n.parent.host and n.parent.host.name == "HStack" end)
  local go, ghost, off = buttons[1].region, buttons[2].region, buttons[3].region
  eq(go.label._color[2], 0xD1 / 255, "gold text")
  go:_fire("OnEnter")
  eq(go.label._color[2], 1, "white on hover")
  ok(go.fxSkinTex.hl:IsShown(), "highlight art")
  go:_fire("OnMouseDown")
  eq(go.fxSkinTex.bgM._texture, "Interface\\Buttons\\UI-Panel-Button-Down", "pressed art")
  eq(go.label._points[1][4], 1, "text moves 1 px right when pressed")
  eq(go.label._points[1][5], -1, "and 1 px down")
  go:_fire("OnMouseUp")
  go:_fire("OnLeave")
  eq(go.fxSkinTex.bgM._texture, "Interface\\Buttons\\UI-Panel-Button-Up", "up art again")
  eq(off.fxSkinTex.bgM._texture, "Interface\\Buttons\\UI-Panel-Button-Disabled", "disabled art")
  eq(off.label._color[1], 0x80 / 255, "gray text when disabled")
  ok(not (ghost.fxSkinTex and ghost.fxSkinTex.bgM and ghost.fxSkinTex.bgM:IsShown()), "ghost: no panel art")
  ghost:_fire("OnEnter")
  eq(ghost.label._color[3], 1, "ghost text white on hover")
  ghost:_fire("OnLeave")
  eq(ghost.label._color[3], 0, "ghost text gold")

  -- Badges: thin tooltip frames in the tone.
  local badges = find(root, "Badge")
  local tinted, solid = badges[1].region, badges[2].region
  eq(tinted._backdrop.edgeFile, "Interface\\Tooltips\\UI-Tooltip-Border", "thin tooltip frame")
  near(tinted.label._color[1], C.info.r, "tone text")
  near(tinted._backdropBorder[3], C.info.b * 0.8, "border in the tone")
  eq(solid.label._color[1], 1, "solid badge: white text")
  near(solid._backdropBorder[1], C.gold.r, "solid badge: border in the tone")

  -- Toggles: the checkbox.
  local toggles = find(root, "Toggle")
  local on, disabled = toggles[1].region, toggles[2].region
  eq(on.fxSkinTex.box._texture, "Interface\\Buttons\\UI-CheckBox-Up", "checkbox")
  eq(on.fxSkinTex.check._texture, "Interface\\Buttons\\UI-CheckBox-Check", "check")
  eq(disabled.fxSkinTex.check._texture, "Interface\\Buttons\\UI-CheckBox-Check-Disabled", "disabled check")
  ok(not (disabled.fxSkinTex.hl and disabled.fxSkinTex.hl:IsShown()), "no highlight when disabled")
  eq(disabled.label._color[1], 0x80 / 255, "gray label when disabled")

  -- Tabs: the count is centred with the label; hover lightens an inactive tab.
  local tabs = find(root, "Tab")
  local first, second = tabs[1].region, tabs[2].region
  ok(first.count:IsShown(), "count shown")
  ok(first.label._points[1][4] < 0, "label shifted left to centre it with the count")
  eq(second.label._points[1][4], 0, "a tab without a count is centred")
  near(second.fxSkinTex.onM._vertex[1], 0.65, "inactive tab darkened")
  ok(second.fxSkinTex.hl:IsShown() and not first.fxSkinTex.hl:IsShown(), "highlight on inactive tabs only")
  second:_fire("OnEnter")
  near(second.fxSkinTex.onM._vertex[1], 0.85, "lighter on hover")
  eq(second.label._color[3], 1, "white text on hover")
  second:_fire("OnLeave")
  eq(second.label._color[3], 0, "gold text otherwise")

  -- Item cell: a square icon in the quality-tinted frame.
  local cell = find(root, "ItemCell")[1].region
  eq(cell.fxSkinTex.iconFrame._texture, "Interface\\Common\\WhiteIconFrame", "icon frame")
  ok(cell.fxSkinTex.iconFrame:IsShown(), "shown")
  eq(cell.icon._w, cell.icon._h, "square icon")

  -- Meter: a status bar in a thin tooltip frame.
  local meter = find(root, "Meter")[1].region
  eq(meter.fill._texture, "Interface\\TargetingFrame\\UI-StatusBar", "status bar fill")
  near(meter.fill._vertex[1], C.info.r, "in the tone")
  eq(meter.track._backdrop.edgeFile, "Interface\\Tooltips\\UI-Tooltip-Border", "thin frame")

  -- Cards and insets: tooltip-style backdrops.
  local card = find(root, "VStack", function(n) return n.el.props.surface == "card" end)[1].region
  eq(card._backdrop.bgFile, "Interface\\Tooltips\\UI-Tooltip-Background", "card backdrop")
  local inset = find(root, "VStack", function(n) return n.el.props.surface == "inset" end)[1].region
  eq(inset._backdrop.edgeSize, 10, "inset: thin frame")

  -- Chart tags: tooltip frames; the last-price tag in its tone on black.
  local chart = find(root, "Chart")[1].region
  ok(chart.lastTag._backdrop, "last-price tag framed")
  near(chart.lastTag.text._color[1], chart.lastTag._backdropBorder[1] / 0.8, "last tag lettered in its tone")
  local l, b, w, h = chart:GetRect()
  W.cursorX, W.cursorY = l + w / 2, b + h / 2
  W.nextFrame()
  ok(chart.readout:IsShown() and chart.readout._backdrop, "readout in a tooltip frame")
  near(chart.readout._backdropBorder[1], 0x90 / 255, "gray border")
  W.cursorX, W.cursorY = -100, -100
  W.nextFrame()

  -- Table: column-tab header art, gold title once sorted; rows highlighted
  -- on hover, gold when selected or pressed.
  local headerNode = find(root, "HeaderCell")[1]
  local header = headerNode.region
  eq(header.fxSkinTex.colM._texture, "Interface\\FriendsFrame\\WhoFrame-ColumnTabs", "column tab art")
  ok(header.fxSkinTex.hl, "sortable header highlight")
  eq(header.label._color[3], 1, "white title when not sorted")
  local list = find(root, "List")[1]
  local row2 = list.children[2].region.fxSkinTex.rowHL
  eq(row2._texture, "Interface\\QuestFrame\\UI-QuestTitleHighlight", "quest-log highlight")
  near(row2._vertex[4], 0.7, "selected row in gold")
  local ll, lb, lw, lh = list.region:GetRect()
  W.cursorX, W.cursorY = ll + 20, lb + lh - 10 -- first row
  W.nextFrame()
  eq(list.hover, 1, "first row hovered")
  local hovered = list.children[1].region.fxSkinTex.rowHL
  ok(hovered:IsShown(), "hovered row highlighted")
  near(hovered._vertex[4], 0.55, "hover highlight")
  list.region:_fire("OnMouseDown", "LeftButton")
  near(list.children[list.pressed].region.fxSkinTex.rowHL._vertex[4], 1, "pressed row in full gold")
  list.region:_fire("OnMouseUp", "LeftButton")
  W.cursorX, W.cursorY = -100, -100
  W.nextFrame()
  header:_click()
  UI.flush()
  header = find(root, "HeaderCell")[1].region
  eq(header.label._color[3], 0, "gold title on the sorted column")

  -- Scrollbars: the fixed knob, never stretched, either way.
  local knobs = {}
  for _, n in ipairs(find(root, "List")) do
    local thumb = n.region.thumb
    if thumb and thumb.fxSkinTex and thumb.fxSkinTex.knob then knobs[#knobs + 1] = thumb.fxSkinTex.knob end
  end
  local sv = find(root, "ScrollView")[1].region.fxScroller
  for _, thumb in ipairs({ sv.thumbX, sv.thumbY }) do
    if thumb and thumb.fxSkinTex and thumb.fxSkinTex.knob then knobs[#knobs + 1] = thumb.fxSkinTex.knob end
  end
  local sizes = {}
  for _, k in ipairs(knobs) do
    eq(k._texture, "Interface\\Buttons\\UI-ScrollBar-Knob", "knob art")
    sizes[#sizes + 1] = k._w .. "x" .. k._h
  end
  table.sort(sizes)
  eq(table.concat(sizes, ","), "16x24,16x24,24x16", "list and vertical knobs 16x24, horizontal 24x16")

  -- Window: dialog backdrop, banner, gold grip, footer status bar.
  local winNode = find(root, "Window")[1]
  local win = winNode.region
  eq(win._backdrop.bgFile, "Interface\\DialogFrame\\UI-DialogBox-Background", "dialog backdrop")
  ok(win.header.fxSkinTex.bannerM:IsShown(), "banner")
  eq(win.grip.lines[1]._color[2], 0xD1 / 255, "gold grip")
  ok(win.footer.fxHasBackdrop, "footer status bar")
  win.close:_fire("OnEnter")
  win.close:_fire("OnLeave")
  root:update(view("classic", "sm"))
  eq(winNode.region.header._h, 14, "small window: compact header too")
  ok(winNode.region.header.fxSkinTex.bannerM:IsShown(), "small window: banner")
  root:unmount()

  -- The same tree under the default theme reuses the pooled regions.
  root = UI.mount(UIParent, view(nil))
  local function hidden(tex, what) ok(not (tex and tex:IsShown()), what) end
  buttons = find(root, "Button", function(n) return n.parent and n.parent.host and n.parent.host.name == "HStack" end)
  hidden(buttons[1].region.fxSkinTex.bgM, "button art hidden")
  ok(buttons[1].region.fxBg:IsShown(), "default button background")
  badges = find(root, "Badge")
  ok(not badges[1].region.fxHasBackdrop and badges[1].region.fxBg:IsShown(), "default badge")
  toggles = find(root, "Toggle")
  hidden(toggles[1].region.fxSkinTex.box, "checkbox hidden")
  ok(toggles[1].region.track:IsShown(), "default toggle track")
  hidden(find(root, "Tab")[2].region.fxSkinTex.onM, "tab art hidden")
  hidden(find(root, "ItemCell")[1].region.fxSkinTex.iconFrame, "icon frame hidden")
  meter = find(root, "Meter")[1].region
  ok(not meter.track.fxHasBackdrop, "meter frame gone")
  ok(meter.fill._texture ~= "Interface\\TargetingFrame\\UI-StatusBar", "default meter fill")
  card = find(root, "VStack", function(n) return n.el.props.surface == "card" end)[1].region
  ok(not card.fxHasBackdrop and card.fxBg:IsShown(), "default card")
  chart = find(root, "Chart")[1].region
  ok(not chart.lastTag.fxHasBackdrop and chart.lastTag.bg:IsShown(), "default chart tag")
  header = find(root, "HeaderCell")[1].region
  hidden(header.fxSkinTex.colM, "column tab art hidden")
  list = find(root, "List")[1]
  hidden(list.children[2].region.fxSkinTex.rowHL, "row highlight hidden")
  hidden(list.region.thumb.fxSkinTex.knob, "list knob hidden")
  ok(list.region.thumb.tex:IsShown(), "default list thumb")
  sv = find(root, "ScrollView")[1].region.fxScroller
  hidden(sv.thumbY.fxSkinTex.knob, "scroll knob hidden")
  ok(sv.thumbY.tex:IsShown(), "default scroll thumb")
  win = find(root, "Window")[1].region
  ok(not win.fxHasBackdrop and win.headerLine:IsShown(), "default window chrome")
  hidden(win.header.fxSkinTex.bannerM, "banner hidden")
  root:unmount()
  W.items[17] = nil
end)

test("classic: missing client art falls back to flat drawing and is reported once", function()
  -- Every client file Classic draws with.
  local paths = {
    "Interface\\DialogFrame\\UI-DialogBox-Background", "Interface\\DialogFrame\\UI-DialogBox-Border",
    "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border",
    "Interface\\Buttons\\UI-Panel-Button-Up", "Interface\\Buttons\\UI-Panel-Button-Down",
    "Interface\\Buttons\\UI-Panel-Button-Disabled", "Interface\\Buttons\\UI-CheckBox-Up",
    "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab", "Interface\\DialogFrame\\UI-DialogBox-Header",
    "Interface\\FriendsFrame\\WhoFrame-ColumnTabs", "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    "Interface\\Common\\WhiteIconFrame", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    "Interface\\TargetingFrame\\UI-StatusBar", "Interface\\Buttons\\UI-ScrollBar-Knob",
  }
  W.missingFiles = {}
  for _, p in ipairs(paths) do W.missingFiles[p] = true end
  I.wipe(I.textureCache)
  W.items[17] = true
  local items = {}
  for i = 1, 30 do items[i] = { id = i, v = "r" .. i } end
  local function view()
    return UI.Window { title = "Flat", width = 560, height = 700, status = "s", theme = "classic",
      UI.HStack { gap = 4, UI.Button { text = "Go" }, UI.Badge { text = "B" }, UI.Badge { text = "S", solid = true },
        UI.Toggle { label = "On", checked = true } },
      UI.TabBar { tabs = { { id = "x", text = "One" }, { id = "y", text = "Two" } }, selected = "x" },
      UI.ItemCell { item = 17 },
      UI.Meter { value = 5, max = 10 },
      UI.Chart { width = 200, height = 100, values = { 1, 2, 3 } },
      UI.Table { height = 120, items = items, key = "id", selected = 2, onSelect = function() end,
        columns = { { key = "v", title = "Value", flex = 1 } } },
    }
  end
  local root = UI.mount(UIParent, view())
  local b = find(root, "Button")[1].region
  ok(b.fxBg and b.fxBg:IsShown(), "flat button background")
  ok(not (b.fxSkinTex.bgM and b.fxSkinTex.bgM:IsShown()), "no panel art")
  local win = find(root, "Window")[1].region
  ok(not win.fxHasBackdrop and win.fxBg:IsShown(), "flat window")
  ok(not (win.header.fxSkinTex and win.header.fxSkinTex.bannerM and win.header.fxSkinTex.bannerM:IsShown()), "no banner")
  ok(win.footer.fxBg:IsShown(), "flat footer")
  ok(win.close.fxSkinTex.up._color, "flat close button")
  local t = find(root, "Toggle")[1].region
  ok(t.fxSkinTex.box._color and t.fxSkinTex.check._color, "flat checkbox")
  local tab = find(root, "Tab")[1].region
  ok(tab.fxBg:IsShown(), "flat tab")
  local rail = find(root, "TabRail")[1].region
  ok(rail.left.fill:IsShown(), "flat rail")
  ok(not find(root, "ItemCell")[1].region.fxSkinTex.iconFrame:IsShown(), "no icon frame")
  local meter = find(root, "Meter")[1].region
  ok(meter.fill._color and meter.track.fxBg:IsShown(), "flat meter")
  ok(find(root, "Badge")[1].region.fxBg:IsShown(), "flat badge")
  ok(find(root, "Badge")[2].region.fxBg:IsShown(), "flat solid badge")
  ok(find(root, "Chart")[1].region.lastTag.fxBg:IsShown(), "flat chart tag")
  local list = find(root, "List")[1]
  ok(list.children[2].region.fxSkinTex.rowHL._color, "flat row highlight")
  ok(list.region.thumb.tex:IsShown(), "default knob drawing")
  local reported = {}
  for _, e in ipairs(W.errors) do
    local path = e:match("^FxUI Classic: the client has no (.-); using FxUI's own drawing for it$")
    ok(path, "reported as a missing file: " .. e)
    ok(not reported[path], "reported once: " .. path)
    reported[path] = true
  end
  ok(reported["Interface\\Buttons\\UI-Panel-Button-Up"], "missing button art reported")
  W.errors = {}
  root:update(view())
  eq(#W.errors, 0, "nothing reported again")
  root:unmount()
  W.items[17] = nil

  -- Loaded without the tooltip art, cards keep FxUI's own surface.
  local bg, edge = "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border"
  W.missingFiles = { [bg] = true, [edge] = true }
  I.wipe(I.textureCache)
  W.loadAddon("FxUI_Theme_Classic", "FxUI_Theme_Classic")
  eq(#W.errors, 2, "both files reported when the theme loads")
  W.errors = {}
  local host = CreateFrame("Frame")
  host:SetSize(200, 100)
  root = UI.mount(host, UI.VStack { surface = "card", UI.Text { text = "card" } }, { theme = "classic" })
  local card = find(root, "VStack")[1].region
  ok(not card.fxHasBackdrop and card.fxBg:IsShown(), "FxUI's own card")
  root:unmount()
  W.missingFiles = nil
  I.wipe(I.textureCache)
  W.loadAddon("FxUI_Theme_Classic", "FxUI_Theme_Classic")
  root = UI.mount(host, UI.VStack { surface = "card", UI.Text { text = "card" } }, { theme = "classic" })
  ok(find(root, "VStack")[1].region.fxHasBackdrop, "tooltip card again once the art is there")
  root:unmount()
end)

test("classic: missing secondary art while the primary art ships falls back per file and is reported once", function()
  -- The primary files ship; only the secondary ones (check marks and
  -- highlights) are missing.
  local secondary = {
    "Interface\\Buttons\\UI-CheckBox-Check", "Interface\\Buttons\\UI-CheckBox-Check-Disabled",
    "Interface\\Buttons\\UI-CheckBox-Highlight", "Interface\\Buttons\\UI-Panel-Button-Highlight",
    "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
  }
  W.missingFiles = {}
  for _, p in ipairs(secondary) do W.missingFiles[p] = true end
  I.wipe(I.textureCache)
  local items = { { id = 1, v = "a" }, { id = 2, v = "b" } }
  local function view()
    return UI.Window { title = "Secondary", width = 400, height = 300, theme = "classic",
      UI.HStack { gap = 4, UI.Button { text = "Go" },
        UI.Toggle { label = "On", checked = true },
        UI.Toggle { label = "Off", checked = true, disabled = true } },
      UI.TabBar { tabs = { { id = "x", text = "One" }, { id = "y", text = "Two" } }, selected = "x" },
      UI.Table { flex = 1, items = items, key = "id", columns = { { key = "v", title = "Value", flex = 1 } } },
    }
  end
  local root = UI.mount(UIParent, view())
  -- Toggle: the box art stays, the check is drawn flat inside it.
  local toggles = find(root, "Toggle")
  local on, off = toggles[1].region.fxSkinTex, toggles[2].region.fxSkinTex
  eq(on.box._texture, "Interface\\Buttons\\UI-CheckBox-Up", "box art kept")
  ok(on.check:IsShown(), "a checked toggle still shows its check")
  ok(on.check._color and on.check._texture == nil, "check drawn flat")
  near(on.check._color[2], 0xD1 / 255, "in gold")
  ok(on.check._w and on.check._w < on.box._w, "inside the box, not covering it")
  ok(off.check:IsShown() and off.check._color and off.check._texture == nil, "disabled check drawn flat")
  near(off.check._color[1], 0x80 / 255, "in gray")
  ok(not (on.hl and on.hl:IsShown()), "checkbox highlight hidden")
  -- Button: panel slices, no highlight.
  local b = find(root, "Button", function(n) return n.el.props.text == "Go" end)[1].region
  ok(b.fxSkinTex.bgM:IsShown(), "button art kept")
  ok(not (b.fxSkinTex.hl and b.fxSkinTex.hl:IsShown()), "button highlight hidden")
  -- Tabs: tab art, no highlight on the inactive tab.
  local tab = find(root, "Tab")[2].region
  ok(tab.fxSkinTex.onM:IsShown(), "tab art kept")
  ok(not (tab.fxSkinTex.hl and tab.fxSkinTex.hl:IsShown()), "tab highlight hidden")
  -- Table header: column art, no highlight.
  local header = find(root, "HeaderCell")[1].region
  ok(header.fxSkinTex.colM:IsShown(), "column art kept")
  ok(not (header.fxSkinTex.hl and header.fxSkinTex.hl:IsShown()), "header highlight hidden")
  -- Close button: art, no highlight.
  local close = find(root, "Window")[1].region.close
  eq(close.fxSkinTex.up._texture, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", "close art kept")
  ok(not (close.fxSkinTex.hl and close.fxSkinTex.hl:IsShown()), "close highlight hidden")
  -- Each missing file reported exactly once.
  local reported = {}
  for _, e in ipairs(W.errors) do
    local path = e:match("^FxUI Classic: the client has no (.-); using FxUI's own drawing for it$")
    ok(path, "reported as a missing file: " .. e)
    ok(not reported[path], "reported once: " .. path)
    reported[path] = true
  end
  for _, p in ipairs(secondary) do ok(reported[p], "reported: " .. p) end
  W.errors = {}
  root:update(view())
  eq(#W.errors, 0, "nothing reported again")
  root:unmount()
  W.missingFiles = nil
  I.wipe(I.textureCache)
end)

test("classic: conditional decorations hide again on update and on pooled reuse", function()
  local function view(title, sortable)
    return UI.Window { title = title, width = 400, height = 300, theme = "classic",
      UI.Table { flex = 1, items = { { id = 1, v = "a" } }, key = "id",
        columns = { { key = "v", title = "Value", flex = 1, sortable = sortable } } },
    }
  end
  local function bannerShown(win)
    local t = win.header.fxSkinTex
    if not t then return false end
    for _, k in ipairs({ "bannerL", "bannerM", "bannerR" }) do
      if t[k] and t[k]:IsShown() then return true end
    end
    return false
  end
  local root = UI.mount(UIParent, view("Titled"))
  local win = find(root, "Window")[1].region
  ok(bannerShown(win), "banner on a titled window")
  root:update(view(""))
  ok(not bannerShown(win), "banner hidden once the title is empty")
  root:update(view("Again"))
  ok(bannerShown(win), "banner back with a title")
  root:update(view(nil))
  ok(not bannerShown(win), "banner hidden once the title is omitted")
  root:update(view("Titled"))
  -- Table headers: the highlight only while the column sorts.
  local header = find(root, "HeaderCell")[1].region
  ok(header.fxSkinTex.hl:IsShown(), "sortable header highlight")
  root:update(view("Titled", false))
  header = find(root, "HeaderCell")[1].region
  ok(not (header.fxSkinTex.hl and header.fxSkinTex.hl:IsShown()), "no highlight once the column cannot sort")
  root:unmount()
  -- A pooled titled window reused for an untitled Classic window.
  root = UI.mount(UIParent, view(nil, false))
  local reused = find(root, "Window")[1].region
  eq(reused, win, "the pooled window is reused")
  ok(not bannerShown(reused), "no banner left over from the titled window")
  header = find(root, "HeaderCell")[1].region
  ok(not (header.fxSkinTex and header.fxSkinTex.hl and header.fxSkinTex.hl:IsShown()), "no header highlight left over")
  root:unmount()
end)

test("classic: the flat tab rail and meter fill set their own geometry and tint", function()
  W.missingFiles = {
    ["Interface\\Tooltips\\UI-Tooltip-Border"] = true,
    ["Interface\\TargetingFrame\\UI-StatusBar"] = true,
  }
  I.wipe(I.textureCache)
  local function view(theme)
    return UI.VStack { theme = theme, width = 300,
      UI.TabBar { tabs = { { id = "x", text = "One" }, { id = "y", text = "Two" } }, selected = "x" },
      UI.Meter { value = 5, max = 10, tone = "info" },
    }
  end
  local function check(root, what)
    local rail = find(root, "TabRail")[1].region
    for _, side in ipairs({ "left", "right" }) do
      local seg, fill = rail[side], rail[side].fill
      ok(fill:IsShown(), what .. ": flat " .. side .. " rail shown")
      local l, b, w, h = fill:GetRect()
      ok(l, what .. ": flat " .. side .. " rail anchored")
      local sl, sb, sw, sh = seg:GetRect()
      near(l, sl, what .. ": " .. side .. " rail starts with its segment")
      near(w, sw, what .. ": " .. side .. " rail spans its segment")
      near(b + h, sb + sh, what .. ": " .. side .. " rail at the top of its segment")
      near(h, 1, what .. ": " .. side .. " rail one pixel tall")
      local r, g, bl, a = fill:GetVertexColor()
      ok(r == 1 and g == 1 and bl == 1 and a == 1, what .. ": " .. side .. " rail untinted")
    end
    local fill = find(root, "Meter")[1].region.fill
    local info = I.resolve("classic").info
    local cr, cg, cb = info.r, info.g, info.b
    ok(fill._color and fill._texture == nil, what .. ": flat meter fill")
    near(fill._color[1], cr, what .. ": meter in its tone")
    near(fill._color[2], cg, what .. ": meter in its tone")
    near(fill._color[3], cb, what .. ": meter in its tone")
    local r, g, b, a = fill:GetVertexColor()
    ok(r == 1 and g == 1 and b == 1 and a == 1, what .. ": meter fill untinted, got " .. r .. "," .. g .. "," .. b .. "," .. a)
    eq(fill.fxFile, nil, what .. ": no file recorded for the flat fill")
  end
  local host = CreateFrame("Frame", nil, UIParent)
  host:SetPoint("TOPLEFT", 10, -10)
  host:SetSize(300, 200)
  -- Fresh regions, never drawn by the default theme.
  local savedPools = I.pools
  I.pools = {}
  local root = UI.mount(host, view("classic"))
  check(root, "fresh")
  root:unmount()
  -- Regions the default theme drew, then switched to Classic, and reused
  -- from the pool.
  root = UI.mount(host, view("default"))
  root:update(view("classic"))
  check(root, "switched")
  root:unmount()
  root = UI.mount(host, view("default"))
  root:unmount()
  root = UI.mount(host, view("classic"))
  check(root, "pooled")
  root:unmount()
  for name, list in pairs(savedPools) do
    I.pools[name] = I.pools[name] or {}
    for _, r in ipairs(list) do table.insert(I.pools[name], r) end
  end
  W.missingFiles = nil
  I.wipe(I.textureCache)
  W.errors = {}
end)

-- Everything a region tree draws, as sorted lines: each visible texture,
-- line and font string with its on-screen rect, content, tint, blend mode,
-- alpha and draw layer (and a file's tex coords and slice margins); each
-- visible backdrop with its colors; each visible frame's alpha.
local function drawnState(region)
  local out = {}
  local function num(v) return v and string.format("%.2f", v) or "-" end
  local function nums(...)
    local s = {}
    for i = 1, select("#", ...) do s[i] = num((select(i, ...))) end
    return table.concat(s, ",")
  end
  local function rect(r)
    local l, b, w, h = r:GetRect()
    if not l then return "unanchored" end
    return nums(l, b, w, h)
  end
  local function drawn(r)
    if not r:IsVisible() or r._type == "MaskTexture" then return end
    local line
    if r._type == "FontString" then
      local path, size = r:GetFont()
      line = "text '" .. tostring(r:GetText()) .. "' " .. tostring(path) .. " " .. num(size) .. " color " .. nums(r:GetTextColor())
    else
      local content = r._texture and ("file " .. tostring(r._texture))
        or (r._color and ("color " .. nums(r._color[1], r._color[2], r._color[3], r._color[4]))) or "empty"
      line = r._type .. " " .. content .. " tint " .. nums(r:GetVertexColor())
      if r._type == "Texture" then
        line = line .. " blend " .. r:GetBlendMode()
        -- Tex coords and slice margins change nothing on a solid color.
        if r._texture then
          line = line .. " uv " .. nums(r:GetTexCoord()) .. " slice " .. nums(r:GetTextureSliceMargins())
        end
      end
    end
    out[#out + 1] = line .. " alpha " .. num(r:GetAlpha()) .. " layer " .. tostring(r:GetDrawLayer()) .. " at " .. rect(r)
  end
  local function visit(f)
    if not f:IsVisible() then return end
    if f:GetAlpha() ~= 1 then out[#out + 1] = "frame alpha " .. num(f:GetAlpha()) .. " at " .. rect(f) end
    if f._backdrop then
      local bg, edge = f._backdropColor or {}, f._backdropBorder or {}
      out[#out + 1] = "backdrop " .. tostring(f._backdrop.bgFile) .. "|" .. tostring(f._backdrop.edgeFile)
        .. " at " .. rect(f) .. " bg " .. nums(bg[1], bg[2], bg[3], bg[4]) .. " edge " .. nums(edge[1], edge[2], edge[3], edge[4])
    end
    for _, r in ipairs(f._regions or {}) do drawn(r) end
    for _, c in ipairs({ f:GetChildren() }) do visit(c) end
  end
  if region.GetChildren then visit(region) else drawn(region) end
  table.sort(out)
  return out
end

-- The lines only one of two drawn states has.
local function stateDiff(a, b)
  local count = {}
  for _, l in ipairs(a) do count[l] = (count[l] or 0) + 1 end
  for _, l in ipairs(b) do count[l] = (count[l] or 0) - 1 end
  local diff = {}
  for l, n in pairs(count) do
    if n > 0 then diff[#diff + 1] = "fresh only:  " .. l end
    if n < 0 then diff[#diff + 1] = "pooled only: " .. l end
  end
  table.sort(diff)
  return diff
end

test("classic: every fallback path draws a pooled region exactly like a fresh one", function()
  local primary = {
    "Interface\\DialogFrame\\UI-DialogBox-Background", "Interface\\DialogFrame\\UI-DialogBox-Border",
    "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border",
    "Interface\\Buttons\\UI-Panel-Button-Up", "Interface\\Buttons\\UI-Panel-Button-Down",
    "Interface\\Buttons\\UI-Panel-Button-Disabled", "Interface\\Buttons\\UI-CheckBox-Up",
    "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab", "Interface\\DialogFrame\\UI-DialogBox-Header",
    "Interface\\FriendsFrame\\WhoFrame-ColumnTabs", "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    "Interface\\Common\\WhiteIconFrame", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    "Interface\\TargetingFrame\\UI-StatusBar", "Interface\\Buttons\\UI-ScrollBar-Knob",
  }
  local secondary = {
    "Interface\\Buttons\\UI-CheckBox-Check", "Interface\\Buttons\\UI-CheckBox-Check-Disabled",
    "Interface\\Buttons\\UI-CheckBox-Highlight", "Interface\\Buttons\\UI-Panel-Button-Highlight",
    "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
  }
  local function set(...)
    local s = {}
    for _, list in ipairs({ ... }) do for _, p in ipairs(list) do s[p] = true end end
    return s
  end
  W.items[17] = true
  local items = {}
  for i = 1, 30 do items[i] = { id = i, v = "r" .. i } end
  local function view(theme)
    return UI.Window { title = "Fallback", width = 560, height = 760, theme = theme, status = "s",
      UI.HStack { gap = 4,
        UI.Button { text = "Go" },
        UI.Button { text = "Ghost", variant = "ghost" },
        UI.Button { text = "Off", disabled = true },
        UI.Badge { text = "B", tone = "info" },
        UI.Badge { text = "S", tone = "gold", solid = true },
        UI.Toggle { label = "On", checked = true },
        UI.Toggle { label = "Off", checked = true, disabled = true },
      },
      UI.TabBar { tabs = { { id = "x", text = "One", count = 3 }, { id = "y", text = "Two" } }, selected = "x" },
      UI.ItemCell { item = 17 },
      UI.Meter { value = 5, max = 10, label = "Fill", valueText = "5/10", tone = "info" },
      UI.Chart { width = 200, height = 100, values = { 1, 2, 3 } },
      UI.Table { height = 120, items = items, key = "id", selected = 2, onSelect = function() end,
        columns = { { key = "v", title = "Value", flex = 1, sortable = true } } },
      UI.ScrollView { direction = "both", width = 100, height = 60, UI.HStack { width = 300, height = 200 } },
    }
  end
  -- Nodes in tree order, deepest first, so a difference is reported at the
  -- smallest component that has it.
  local function nodes(root)
    local out = {}
    walk(root.node, function(n) if n.region then table.insert(out, 1, n) end end)
    return out
  end
  -- The regions a pointer can enter: the node's own, its close button and
  -- its scrollbar thumbs.
  local function hoverables(r)
    local out = {}
    local function add(x) if x and x.GetScript and x:GetScript("OnEnter") then out[#out + 1] = x end end
    add(r)
    add(r.close)
    add(r.thumb)
    for _, sc in ipairs({ r.fxScroller, r.body and r.body.fxScroller }) do
      if sc then add(sc.thumbY); add(sc.thumbX) end
    end
    return out
  end
  -- Differences, each reported once, at the smallest component that has it.
  local problems, seen = {}, {}
  local function same(fresh, pooled, what)
    for _, line in ipairs(stateDiff(drawnState(fresh), drawnState(pooled))) do
      if not seen[line] then
        seen[line] = true
        problems[#problems + 1] = what .. " draws differently when pooled:\n    " .. line
      end
    end
  end
  local function compare(a, b, label)
    local na, nb = nodes(a), nodes(b)
    eq(#na, #nb, label .. ": same tree")
    for i, n in ipairs(na) do
      local m = nb[i]
      eq(n.host.name, m.host.name, label .. ": same tree")
      ok(n.region ~= m.region, label .. ": distinct regions")
      local what = label .. ": " .. n.host.name
      same(n.region, m.region, what)
      local ha, hb = hoverables(n.region), hoverables(m.region)
      eq(#ha, #hb, what .. ": same hoverables")
      for j, x in ipairs(ha) do
        local y = hb[j]
        x:GetScript("OnEnter")(x)
        y:GetScript("OnEnter")(y)
        same(n.region, m.region, what .. " (hovered)")
        if n.host.name == "Button" then
          x:GetScript("OnMouseDown")(x)
          y:GetScript("OnMouseDown")(y)
          same(n.region, m.region, what .. " (pressed)")
          x:GetScript("OnMouseUp")(x)
          y:GetScript("OnMouseUp")(y)
        end
        x:GetScript("OnLeave")(x)
        y:GetScript("OnLeave")(y)
        same(n.region, m.region, what .. " (after hover)")
      end
    end
  end
  -- Hover everything and leave again: the default theme draws (and
  -- creates) its hover state, and the pointer is gone before the swap.
  local function hoverAll(root)
    for _, n in ipairs(nodes(root)) do
      for _, x in ipairs(hoverables(n.region)) do
        x:GetScript("OnEnter")(x)
        x:GetScript("OnLeave")(x)
      end
    end
  end

  local savedPools, savedMixin = I.pools, BackdropTemplateMixin
  local cases = {
    { "every client file missing", set(primary, secondary) },
    { "secondary files missing", set(secondary) },
    { "no backdrops", nil, true },
  }
  for _, case in ipairs(cases) do
    local label, missing, noBackdrops = case[1], case[2], case[3]
    W.missingFiles = missing
    I.wipe(I.textureCache)
    if noBackdrops then BackdropTemplateMixin = nil end
    -- Fresh: empty pools, so Classic draws regions nothing drew before.
    I.pools = {}
    local fresh = UI.mount(UIParent, view("classic"))
    -- Pooled: regions the default theme drew, hover included, then reused
    -- for Classic.
    local default = UI.mount(UIParent, view("default"))
    hoverAll(default)
    local defaultWin = find(default, "Window")[1].region
    default:unmount()
    local pooled = UI.mount(UIParent, view("classic"))
    eq(find(pooled, "Window")[1].region, defaultWin, label .. ": the default theme's window is reused")
    compare(fresh, pooled, label)
    -- The same regions switched from the default theme while mounted.
    pooled:unmount()
    local switched = UI.mount(UIParent, view("default"))
    hoverAll(switched)
    switched:update(view("classic"))
    compare(fresh, switched, label .. " (switched)")
    fresh:unmount()
    switched:unmount()
    BackdropTemplateMixin = savedMixin
  end
  W.missingFiles = nil
  I.wipe(I.textureCache)
  W.items[17] = nil
  W.errors = {}
  -- Hand the earlier tests' pooled regions back.
  for name, list in pairs(savedPools) do
    I.pools[name] = I.pools[name] or {}
    for _, r in ipairs(list) do table.insert(I.pools[name], r) end
  end
  ok(#problems == 0, "\n  " .. table.concat(problems, "\n  "))
end)

test("classic: layout invariants hold over representative trees at several sizes", function()
  layoutInvariants("classic")
end)

test("themes: the theme dropdown lists Classic and Teal", function()
  local setting = W.settings.settings.FXUI_THEME
  local names = {}
  for _, o in ipairs(setting.dropdown()) do names[o.value] = o.label end
  eq(names.default, "FxUI Dark")
  eq(names.classic, "Classic")
  eq(names.teal, "FxUI Teal")
  setting:SetValue("classic")
  eq(UI.themeName, "classic")
  eq(FxUIDB.theme, "classic", "saved")
  setting:SetValue("teal")
  eq(UI.themeName, "teal")
  setting:SetValue("default")
  eq(UI.themeName, "default")
end)

---------------------------------------------------------------------------
-- Dev tools: FxUI_Dev and the snapshot reader
---------------------------------------------------------------------------

-- The interpreter running these tests, for the snapshot reader, which runs
-- as its own process the way it is used. Interpreter options such as
-- -lluacov sit between the interpreter and the script, so it is the lowest
-- negative index of arg.
local LUA = "lua"
if arg then
  local lowest = 0
  while arg[lowest - 1] ~= nil do lowest = lowest - 1 end
  if lowest < 0 then LUA = arg[lowest] end
end

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Under luacov the reader runs under it too, so its lines count.
local READER = shellQuote(LUA)
  .. ((package.loaded.luacov or package.loaded["luacov.runner"]) and " -lluacov" or "")
  .. " tools/inspect.lua"

-- Runs the reader; returns what it printed (stdout and stderr) and its exit
-- status.
local function runReader(path, options)
  local cmd = READER .. (path and (" " .. shellQuote(path)) or "") .. " " .. (options or "") .. " 2>&1; echo \"exit=$?\""
  local pipe = assert(io.popen(cmd))
  local text = pipe:read("*a")
  pipe:close()
  local status = tonumber(text:match("exit=(%d+)%s*$"))
  return (text:gsub("exit=%d+%s*$", "")), status
end

-- Writes the given SavedVariables the way the client does and reads them
-- with the reader.
local function readSaved(options, names)
  local path = os.tmpname()
  W.writeSavedVariables(path, names or { "FxUIDevDB" })
  local text, status = runReader(path, options)
  os.remove(path)
  return text, status
end

-- Reads a hand-built snapshot database stored under `name`.
local function readDB(db, options, name)
  name = name or "FxUIDevDB"
  local saved = _G[name]
  _G[name] = db
  local ok2, text, status = pcall(readSaved, options, { name })
  _G[name] = saved
  if not ok2 then error(text, 2) end
  return text, status
end

-- Everything printed to chat while fn runs.
local function chat(fn)
  local lines, savedPrint = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  local ok2, err = pcall(fn)
  print = savedPrint
  if not ok2 then error(err, 2) end
  return table.concat(lines, "\n")
end

local function rootNamed(name)
  for r in pairs(I.roots) do
    if r.node and r.node.def and r.node.def.name == name then return r end
  end
end

local function clickTab(root, id)
  find(root, "Tab", function(n) return n.el.props.id == id end)[1].region:_click()
  W.nextFrame()
end

-- Takes a snapshot without reloading and reads it. It is the only one
-- stored, so writing and reading it stays quick (also under luacov).
local function snapshotText(options)
  FxUIDevDB.snapshots = {}
  FxUIDevCharDB.snapshotReload = false
  chat(function() fx("dev all") end)
  FxUIDevCharDB.snapshotReload = true
  return readSaved(options)
end

-- The picker frame (shown or not).
local function pickerFrame()
  for _, f in ipairs(W.frames) do
    if f._strata == "TOOLTIP" and f._scripts.OnKeyDown and f._scripts.OnMouseDown then return f end
  end
end

test("demo: opens, every tab renders, items load, closes", function()
  local notice = chat(function()
    W.loadAddon("FxUI_Dev", "FxUI_Dev")
    W.fireEvent("PLAYER_LOGIN")
  end)
  ok(notice:find("/fx demo", 1, true) and notice:find("/fx dev", 1, true), "login notice names the commands: " .. notice)
  fx("demo")
  W.nextFrame()
  local root = rootNamed("DemoApp")
  ok(root, "demo root mounted")

  local window = find(root, "Window")[1]
  ok(window.region:IsShown(), "window shown")
  eq(window.region:GetWidth(), 980, "default width")
  eq(window.region:GetHeight(), 660, "default height")

  for _, id in ipairs({ "items", "charts", "theme", "scroll", "controls", "items" }) do
    local tab = find(root, "Tab", function(n) return n.el.props.id == id end)[1]
    tab.region:_click()
    W.nextFrame()
    W.loadItems()
    W.nextFrame()
    ok(#find(root, "Tab", function(n) return n.el.props.selected and n.el.props.id == id end) == 1, id .. " selected")
    eq(FxUIDevCharDB.tab, id, "selected tab saved")
  end

  local list = find(root, "List")[1]
  ok(list and #list.children > 0, "items list has rows")
  for _ = 1, 50 do list.region:_fire("OnMouseWheel", -1) end
  W.loadItems()
  W.nextFrame()
  ok(#list.children < 30, "rows virtualized")

  -- Sort by a header, select a row.
  local header = find(root, "Button", function(n) return n.el.props.text == "Price" end)[1]
  if header then header.region:_click() end
  W.nextFrame()

  -- Open the inspector from a row; it docks to the demo's right edge.
  local inspect = find(root, "Button", function(n) return n.el.props.text == "Inspect" end)[1]
  inspect.region:_click()
  W.loadItems()
  W.nextFrame()
  local inspector = rootNamed("DemoInspector")
  ok(inspector, "inspector opened")
  local iframe = find(inspector, "Window")[1].region
  eq(iframe:GetLeft(), window.region:GetRight() + 8, "docked to the right edge")
  -- Selecting another row while the inspector is open shows that row.
  local rows = find(root, "TableRow")
  if #rows == 0 then rows = find(root, "Button", function(n) return n.el.props.text == "Inspect" end) end
  rows[#rows].region:_click()
  W.loadItems()
  W.nextFrame()
  ok(rootNamed("DemoInspector"), "inspector follows the selection")

  W.advance(1)
  W.nextFrame()

  -- Theme tab: global theme buttons, then a theme for this window only.
  clickTab(root, "theme")
  local function button(text, nth)
    return find(root, "Button", function(n) return n.el.props.text == text end)[nth or 1]
  end
  button("FxUI Teal").region:_click()
  W.nextFrame()
  eq(UI.themeName, "teal", "global theme from a theme addon")
  button("FxUI Dark").region:_click()
  W.nextFrame()
  eq(UI.themeName, "default")
  button("Classic", 2).region:_click()
  W.nextFrame()
  eq(UI.themeName, "default", "the window choice leaves the global theme alone")
  eq(FxUIDevCharDB.demoTheme, "classic", "window theme saved")
  local win = find(root, "Window")[1]
  eq(win.theme and win.theme.name, "classic", "the window uses its own theme")
  ok(win.region.fxHasBackdrop, "classic draws the window with a dialog backdrop")
  local inspectorWin = find(rootNamed("DemoInspector"), "Window")[1]
  eq(inspectorWin.theme and inspectorWin.theme.name, "classic", "the inspector follows the window theme")
  button("Global").region:_click()
  W.nextFrame()
  win = find(root, "Window")[1]
  eq(win.theme, nil, "back to the global theme")
  ok(not win.region.fxHasBackdrop, "backdrop cleared when the theme changes back")
  eq(FxUIDevCharDB.demoTheme, nil)

  -- Charts tab: every mode and a new random series.
  clickTab(root, "charts")
  for _, text in ipairs({ "Candles", "Bars", "Randomize", "Line" }) do
    button(text).region:_click()
    W.nextFrame()
  end
  ok(#find(root, "Chart") == 7, "seven charts")

  -- Controls tab buttons and toasts; combat redraws the demo.
  clickTab(root, "controls")
  for _, n in ipairs(find(root, "Button")) do
    if n.alive then n.region:_click() end
    W.nextFrame()
  end
  for _, n in ipairs(find(root, "Toggle")) do
    if n.alive then n.region:_click() end
    W.nextFrame()
  end
  W.advance(5)
  W.nextFrame()
  W.combat = true
  W.fireEvent("PLAYER_REGEN_DISABLED")
  W.nextFrame()
  ok(#find(root, "Text", function(n) return n.el.props.text == "In combat" end) == 1, "combat state shown")
  W.combat = false
  W.fireEvent("PLAYER_REGEN_ENABLED")
  W.nextFrame()

  local frame = window.region
  frame.close:_click()
  W.nextFrame()
  ok(not frame:IsShown(), "window hidden after close")
  ok(not root.alive, "demo unmounted after close")
  ok(not rootNamed("DemoInspector"), "inspector closed with the demo")
  fx("demo")
  W.nextFrame()
  ok(frame:IsShown(), "window frame reused from the pool on reopen")
  eq(FxUIDevCharDB.tab, "controls", "reopens on the saved tab")
  fx("demo")
end)

test("demo: the same generated data every time, generic items only", function()
  fx("demo")
  W.nextFrame()
  local root = rootNamed("DemoApp")
  clickTab(root, "items")
  W.loadItems()
  W.nextFrame()
  local function firstItems()
    local out = {}
    for _, n in ipairs(find(rootNamed("DemoApp"), "ItemCell")) do out[#out + 1] = tostring(n.el.props.item) end
    return table.concat(out, ",")
  end
  local before = firstItems()
  ok(#before > 0, "items shown")
  fx("demo")
  fx("demo")
  W.nextFrame()
  W.loadItems()
  W.nextFrame()
  eq(firstItems(), before, "rows are generated once, deterministically")
  clickTab(rootNamed("DemoApp"), "controls")
  fx("demo")
end)

-- A snapshot built by hand, with one node for every flag the reader raises.
local function flaggedSnapshot()
  local function fs(text, rect, extra)
    local r = { type = "FontString", text = text, rect = rect, shown = true, visible = true,
      font = { file = "Inter.ttf", size = 12 }, color = "#FFFFFF", textWidth = 10 }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local function frame(rect, extra)
    local r = { type = "Frame", rect = rect, shown = true, visible = true }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  return {
    time = 0, date = "2026-01-02 03:04:05", fxui = "FxUI-1.0.1", theme = "default",
    uiScale = 0.8, fxScale = 1, uiSize = { 1000, 800 }, screen = { 2000, 1600 },
    client = { version = "12.1.5", build = "1", interface = 120105 },
    stats = { active = 3, pooled = 2, created = 5 },
    errors = { { time = 0, message = "boom\nstack line" } },
    hover = { { type = "Button", name = "HoverMe", node = 5 }, { type = "Frame" } },
    selected = 5,
    frames = {
      { name = "NamedFrame", tree = frame({ 0, 0, 10, 10 }, { parts = { fs("child", { 0, 0, 5, 5 }) } }) },
      { name = "NotThere", missing = true },
    },
    roots = { { parent = "UIParent", tree = {
      id = 1, component = "App", props = { title = "Demo", onClick = "<fn>" }, state = { count = 1 }, renders = 2,
      children = { {
        id = 2, host = "VStack", props = { padding = 10, gap = 4 }, layout = { 0, 0, 200, 100 }, scale = 0.8,
        theme = "classic",
        region = frame({ 0, 600, 200, 100 }, { strata = "MEDIUM", level = 3, clips = true }),
        parts = {
          fs("cut", { 0, 690, 300, 10 }, { field = "label", truncated = true }),
          { field = "fxBg", type = "Texture", texture = "Round8.tga", vertex = "#000000", slice = { 4, 4, 4, 4 },
            uv = { 0, 1, 1, 0, flipped = true }, blend = "ADD", rect = { 0, 600, 200, 100 }, alpha = 0.5, shown = true },
          { field = "edge", type = "Line", vertex = "#FF0000", shown = false },
          frame({ 10, 610, 20, 20 }, { field = "sub", type = "Button", parts = { fs("in", { -50, 610, 10, 10 }, { field = "tag" }) } }),
          frame({ 0, 0, 900, 900 }, { field = "scrollContent" }),
        },
        children = {
          { id = 3, host = "HStack", props = { padding = { 2, 4 } }, layout = { 2, 2, 50, 20 },
            region = frame({ 2, 678, 50, 20 }) },
          { id = 4, host = "Text", props = { text = "Too long", color = "text" }, layout = { 150, 40, 80, 10 },
            region = fs("Too long", { 150, 650, 100, 10 }, { truncated = true, alpha = 0.5 }) },
          { id = 5, host = "Button", props = { text = "Go", variant = "primary" }, layout = { 10, 60, 40, 20 }, scale = 0.8,
            region = frame({ 10, 620, 40, 20 }, { type = "Button", enabled = false }),
            parts = { fs("Go", { 12, 622, 20, 10 }, { field = "label" }) } },
          { id = 6, host = "HStack", props = {}, region = frame({ 10, 610, 0, 10 }) },
          { id = 7, host = "HStack", props = {}, layout = { 0, 0, 5, 5 }, region = { type = "Frame", shown = true, visible = true } },
          { id = 8, host = "List", props = {}, layout = { 0, 0, 100, 50 }, scroll = { 0, 10, 5, 100 },
            region = frame({ 0, 600, 100, 50 }),
            children = { { id = 9, host = "HStack", props = {}, region = frame({ 0, 0, 100, 20 }) } } },
          { id = 10, host = "HStack", props = {}, region = frame({ 0, 600, 10, 10 }, { visible = false }) },
        },
      } },
    } }, { parent = "<anonymous>", tree = {
      id = 11, host = "Frame", props = {}, layout = { 10, 20, 30, 40 },
      region = frame({ 10, 740, 30, 40 }, { strata = "DIALOG", level = 7 }),
    } } },
  }
end

test("reader: header, errors, hover, selection, trees and every flag", function()
  local text, status = readDB({ snapshots = { flaggedSnapshot() } })
  eq(status, 0, "exit status")
  for _, want in ipairs({
    "Snapshot 1/1  2026-01-02 03:04:05  client 12.1.5 (1, interface 120105)  FxUI-1.0.1",
    "UI 1000x800 at scale 0.80 (FxUI x1.00) on a 2000x1600 screen  theme default  regions active 3 / pooled 2 / created 5",
    "Errors (1):", "boom\n    stack line",
    "Under the mouse:", "Button HoverMe -> node #5", "Frame <anonymous>",
    "Selected #5 (picked in game)", "screen pixels: ",
    "Root 1 in UIParent", "#1 <App> \"Demo\" state{count=1}",
    "[clips, theme classic]",
    "Root 2 in <anonymous>", "#11 Frame   @10,20 30x40  [DIALOG/7]",
    "#3 HStack", "PADDING 8",
    "#4 Text \"Too long\" color=\"text\"", "TRUNCATED", "SIZE 100x10!=layout 80x10", "OVERFLOW 50",
    "[alpha 0.5, Inter.ttf 12 #FFFFFF]",
    "[disabled]", "<== HOVER", "<== SELECTED",
    "#6 HStack", "ZERO", "#7 HStack", "NO-RECT", "layout 5x5",
    "OVERFLOW(label) 100", "TRUNCATED(label)", "OVERFLOW(tag) 50",
    "[invisible]", "scrolls y 5/100 x 0/10",
    "Issues (",
  }) do
    ok(text:find(want, 1, true), "missing " .. want .. ":\n" .. text)
  end
  ok(not text:find("#9 HStack %S+ .*OVERFLOW"), "rows of a List are not flagged")
  ok(not text:find("OVERFLOW(scrollContent)", 1, true), "scroll content is larger by design")
  ok(not text:find("Frame NamedFrame", 1, true), "named frames only with --frames")
  local issues = text:match("Issues %(%d+%):\n(.*)$")
  ok(issues and issues:find("#4 App > VStack > Text: OVERFLOW 50", 1, true), "issues name the path:\n" .. tostring(issues))
  local _, selectedCount = text:gsub("#5 Button", "")
  eq(selectedCount, 2, "the selection is printed once more, with its parts")
  local _, issueCount = issues:gsub("#5 Button", "")
  eq(issueCount, 0, "the disabled button raises no issue")
end)

test("reader: --parts, --props, --frames, --node, --list and --snapshot", function()
  local first, second = flaggedSnapshot(), flaggedSnapshot()
  second.date = "2026-01-02 04:00:00"
  second.selected, second.errors, second.hover = nil, {}, nil
  local db = { snapshots = { first, second } }

  local text = readDB(db, "--parts")
  ok(text:find("Snapshot 2/2", 1, true), "newest by default:\n" .. text)
  ok(not text:find("Selected #", 1, true), "no selection in the newest")
  ok(text:find(". fxBg:Texture Round8.tga #000000 slice 4,4,4,4 uv 0-1 1-0 flipped ADD 200x100 alpha 0.5", 1, true), "texture part:\n" .. text)
  ok(text:find(". label:FontString \"cut\" Inter.ttf 12 #FFFFFF w=10 TRUNCATED 300x10", 1, true), "font string part")
  ok(text:find(". edge:Line #FF0000 hidden", 1, true), "line part")
  ok(text:find("    . tag:FontString \"in\"", 1, true), "parts of a sub-frame")

  text = readDB(db, "--props")
  ok(text:find("onClick=\"<fn>\"", 1, true) and text:find("gap=4 padding=10", 1, true), "every prop:\n" .. text)

  text = readDB(db, "--frames")
  ok(text:find("Frame NamedFrame\n  ?:Frame 10x10\n    ?:FontString \"child\"", 1, true), "named frame dumped:\n" .. text)
  ok(text:find("Frame NotThere (not found)", 1, true), "missing frame reported")

  text = readDB(db, "--node 4")
  ok(text:find("Node #4 (root 1)", 1, true), "only that node:\n" .. text)
  ok(text:find("screen pixels: 300,280 200x20  (crop 200x20+300+280)", 1, true), "screen pixels at scale 1")
  ok(not text:find("Issues", 1, true) and not text:find("Root 1", 1, true), "no tree, no issue list")
  text = readDB(db, "--node 5")
  ok(text:find("screen pixels: 16,533 66x33  (crop 66x33+16+533)", 1, true), "the node's own scale:\n" .. text)
  text = readDB(db, "--node 1")
  ok(text:find("Node #1 (root 1)\n  screen pixels: ", 1, true), "a component's rect is its child's:\n" .. text)

  text = readDB(db, "--list")
  ok(text:find("1  2026-01-02 03:04:05  2 roots  1 errors\n2  2026-01-02 04:00:00  2 roots  0 errors", 1, true), "list:\n" .. text)

  text = readDB(db, "--snapshot 1")
  ok(text:find("Snapshot 1/2", 1, true) and text:find("Selected #5", 1, true), "first snapshot:\n" .. text)
  text = readDB(db, "--snapshot -1")
  ok(text:find("Snapshot 1/2", 1, true), "-1 is the one before the newest:\n" .. text)

  text = readDB(db, nil, "FxUIInspectDB")
  ok(text:find("Snapshot 2/2", 1, true), "reads the earlier variable name:\n" .. text)
end)

test("reader: usage without a file, status 1 without snapshots", function()
  local text, status = runReader(nil, "")
  eq(status, 2, "usage status")
  ok(text:find("usage: lua tools/inspect.lua", 1, true), "usage printed: " .. text)
  text, status = readDB({ snapshots = {} })
  eq(status, 1, "no snapshots")
  ok(text:find("No snapshots in ", 1, true), text)
  local empty = { snapshots = { { roots = {} } } }
  text, status = readDB(empty)
  eq(status, 0)
  ok(text:find("Snapshot 1/1  ?", 1, true) and text:find("No layout issues flagged.", 1, true), "a bare snapshot reads:\n" .. text)
end)

test("dev: the reader flags non-finite geometry instead of failing", function()
  local text, status = readDB({ snapshots = { {
    time = 0, client = { version = "12.1.5", build = "1", interface = 120105 }, uiSize = { 1920, 1080 }, uiScale = 1,
    screen = { 3840, 2160 },
    roots = { { parent = "UIParent", tree = { id = 1, host = "HStack", props = {}, layout = { 0, 0, 10, 10 },
      region = { type = "Frame", shown = true, visible = true, rect = { 0, 0 / 0, 10, math.huge } } } } },
  } } })
  eq(status, 0, "read without failing:\n" .. text)
  ok(text:find("NONFINITE", 1, true), "flagged:\n" .. text)
end)

-- Rects are in each region's own scale; a scaled window's rects only compare
-- with UIParent's (and each other's) once brought to one scale.
local function scaledSnapshot()
  local function frame(rect, extra)
    local r = { type = "Frame", rect = rect, shown = true, visible = true }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  return {
    time = 0, date = "2026-01-02 03:04:05", uiScale = 0.8, fxScale = 0.5, uiSize = { 1000, 800 }, screen = { 2000, 1600 },
    client = { version = "12.1.5", build = "1", interface = 120105 },
    selected = 3,
    roots = {
      -- At half the UI's scale: x 600-800, y 200-400 of a 1000x800 UI.
      { parent = "UIParent", tree = {
        id = 1, host = "Window", props = {}, layout = { 0, 0, 400, 400 }, scale = 0.4,
        region = frame({ 1200, 400, 400, 400 }),
        parts = {
          -- Sub-frames drawn at their own (double) scale: x 1300-1450 and
          -- 1500-1650 in the window's units.
          frame({ 650, 250, 75, 10 }, { field = "badge", scale = 0.8 }),
          frame({ 750, 250, 75, 10 }, { field = "wide", scale = 0.8 }),
        },
        children = {
          { id = 2, host = "HStack", props = {}, layout = { 1550, 410, 100, 20 }, scale = 0.4,
            region = frame({ 1550, 410, 100, 20 }) },
          { id = 3, host = "HStack", props = {}, layout = { 10, 370, 100, 20 }, scale = 0.4,
            region = frame({ 1210, 410, 100, 20 }) },
          -- No scale recorded: the parent's.
          { id = 4, host = "HStack", props = {}, layout = { 20, 360, 100, 20 },
            region = frame({ 1220, 410, 100, 20 }) },
        },
      } },
      -- At 1.5 times the UI's scale: x 900-1050 sticks 50 UI units (33.3 of
      -- its own) out of the 1000-unit UI.
      { parent = "UIParent", tree = {
        id = 5, host = "Window", props = {}, layout = { 0, 0, 100, 100 }, scale = 1.2,
        region = frame({ 600, 100, 100, 100 }),
      } },
    },
  }
end

test("reader: compares rects at one scale in scaled windows", function()
  local db = { snapshots = { scaledSnapshot() } }
  local text, status = readDB(db)
  eq(status, 0, "exit status:\n" .. text)
  local issues = text:match("Issues %(%d+%):\n(.*)$") or ""
  ok(not issues:find("#1 Window: OVERFLOW %d"), "a half-scale window inside the UI fits:\n" .. text)
  ok(issues:find("#5 Window: OVERFLOW 33.3", 1, true), "a 150% window past the UI's edge overflows:\n" .. text)
  ok(issues:find("#2 Window > HStack: OVERFLOW 50", 1, true), "a child past its window's edge, in its own units:\n" .. text)
  ok(not issues:find("#3 ", 1, true) and not issues:find("#4 ", 1, true), "children inside the window fit:\n" .. text)
  ok(text:find("#1 Window   @1200,800 400x400  [scale x0.50]", 1, true), "the window's position in its own units:\n" .. text)
  ok(text:find("#3 HStack   @10,370 100x20", 1, true), "relative positions at one scale:\n" .. text)
  ok(text:find("#4 HStack   @20,370 100x20", 1, true), "a node without a scale takes its parent's:\n" .. text)
  ok(not issues:find("OVERFLOW(badge)", 1, true), "a part at its own scale inside the node fits:\n" .. text)
  ok(issues:find("#1 Window: OVERFLOW(wide) 50", 1, true), "a part at its own scale past the node's edge:\n" .. text)

  local selected = text:match("Selected #3 %(picked in game%)\n(.-)\n\n")
  ok(selected and selected:find("#3 HStack", 1, true) and not selected:find("!!", 1, true),
    "the selection, against the UI, at one scale:\n" .. text)

  text = readDB(db, "--node 1")
  ok(text:find("#1 Window   @1200,800 400x400", 1, true) and not text:find("OVERFLOW 600", 1, true)
    and not text:find("#1 Window[^\n]*OVERFLOW %d"), "--node at one scale:\n" .. text)
end)

-- Sub-regions nest inside sub-frames (a title inside a header frame).
local function nestedSnapshot()
  local function fs(field, rect, extra)
    local r = { type = "FontString", field = field, text = field, rect = rect, shown = true, visible = true }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local function frame(field, rect, parts, extra)
    local r = { type = "Frame", field = field, rect = rect, shown = true, visible = true, parts = parts }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local inside = { 10, 10, 20, 10 }
  local outside = { 500, 10, 20, 10 }
  return {
    time = 0, uiScale = 1, uiSize = { 1000, 800 },
    roots = { { parent = "UIParent", tree = {
      id = 1, host = "Window", props = {}, layout = { 0, 0, 200, 100 }, scale = 1,
      region = { type = "Frame", rect = { 0, 0, 200, 100 }, shown = true, visible = true },
      parts = {
        frame("header", { 0, 80, 200, 20 }, {
          fs("title", inside, { truncated = true }),
          frame("bar", { 0, 80, 200, 20 }, {
            fs("deepTitle", inside, { truncated = true }),
            fs("farTag", outside),
            fs("nanPart", { 0 / 0, 10, 20, 10 }),
          }),
          frame("clipper", { 0, 80, 200, 20 }, { fs("clippedTag", outside) }, { clips = true }),
        }),
        frame("hiddenHeader", { 0, 80, 200, 20 }, {
          fs("hiddenTitle", inside, { truncated = true }),
          frame("hiddenBar", { 0, 80, 200, 20 }, { fs("hiddenDeep", inside, { truncated = true }), fs("hiddenTag", outside) }),
        }, { shown = false, visible = false }),
        frame("panel", { 0, 0, 200, 80 }, {
          frame("closedBar", { 0, 0, 200, 20 }, { fs("closedTitle", inside, { truncated = true }), fs("closedTag", outside) },
            { shown = false, visible = false }),
        }),
      },
    } } },
  }
end

test("reader: checks sub-regions at every depth, skipping hidden ones", function()
  local db = { snapshots = { nestedSnapshot() } }
  local text, status = readDB(db)
  eq(status, 0, "exit status:\n" .. text)
  local issues = text:match("Issues %(%d+%):\n(.*)$") or ""
  for _, want in ipairs({ "TRUNCATED(title)", "TRUNCATED(deepTitle)", "OVERFLOW(farTag) 320", "NONFINITE(nanPart)" }) do
    ok(issues:find(want, 1, true), "missing " .. want .. ":\n" .. text)
  end
  for _, unwanted in ipairs({ "hiddenTitle", "hiddenDeep", "hiddenTag", "closedTitle", "closedTag", "clippedTag", "OVERFLOW(nanPart)" }) do
    ok(not issues:find(unwanted, 1, true), "flagged under a hidden or clipping ancestor: " .. unwanted .. ":\n" .. text)
  end

  text = readDB(db, "--parts")
  ok(text:find("\n            . deepTitle:FontString \"deepTitle\"", 1, true), "--parts lists every depth:\n" .. text)
end)

test("dev: /fx dev all snapshots the demo and the reader prints it", function()
  FxUIDevDB = nil
  fx("demo")
  W.nextFrame()
  W.loadItems()
  W.nextFrame()
  local root = rootNamed("DemoApp")
  local button = find(root, "Button", function(n) return n.el.props.text == "Primary" end)[1]
  W.mouseFoci = { button.region }
  local reloads = W.reloads or 0
  fx("dev all UIParent NoSuchFrame")
  eq(W.reloads, reloads + 1, "reloaded")
  W.mouseFoci = nil
  local snaps = FxUIDevDB.snapshots
  ok(snaps and #snaps == 1, "one snapshot stored")
  ok(#snaps[1].roots >= 1, "roots captured")
  eq(snaps[1].client.interface, 120105, "client facts")
  eq(snaps[1].frames[2].missing, true, "unknown frame recorded as missing")

  local text = readSaved("--frames")
  local parts = readSaved("--parts")
  ok(not parts:find('?:FontString "BUTTONS"', 1, true), "node regions are not repeated as parts")
  ok(parts:find("headerFoot:Texture", 1, true), "sub-frame regions named from the host's fields:\n" .. parts:sub(1, 3000))
  ok(parts:find("Round8.tga", 1, true), "texture files named, not file IDs")
  ok(text:find("Snapshot 1/1", 1, true), "header printed:\n" .. text)
  ok(text:find("<DemoApp>", 1, true), "the demo's tree printed")
  ok(text:find('Button "Primary"', 1, true), "primary button listed")
  ok(text:find("<== HOVER", 1, true), "hovered node marked")
  ok(text:find("Frame UIParent", 1, true), "named frame dumped")
  ok(text:find("Frame NoSuchFrame (not found)", 1, true), "missing frame reported")
  ok(not text:find("OVERFLOW", 1, true), "no overflow on the controls tab:\n" .. text)

  -- Every tab lays out without flags (item names may end in an ellipsis),
  -- at the default size and at the window's minimum size, in the default
  -- theme and in Classic.
  local function noFlags(out, what)
    ok(out:find("<DemoApp>", 1, true), what .. ": the reader printed the tree:\n" .. out)
    local issues = out:match("Issues %(%d+%):\n(.*)$") or ""
    for line in issues:gmatch("[^\n]+") do
      ok(line:find("ItemCell: TRUNCATED(name)", 1, true), what .. ": " .. line .. "\n" .. out)
    end
  end
  for _, variant in ipairs({ { 980, 660 }, { 760, 520 }, { 980, 660, "classic" }, { 760, 520, "classic" } }) do
    FxUIDevCharDB.demoTheme = variant[3]
    root:update()
    W.nextFrame()
    local frame = find(root, "Window")[1].region
    frame:SetSize(variant[1], variant[2])
    W.nextFrame()
    local where = " at " .. variant[1] .. "x" .. variant[2] .. " in " .. (variant[3] or "default")
    for _, id in ipairs({ "controls", "items", "charts", "theme", "scroll" }) do
      clickTab(root, id)
      W.loadItems()
      W.nextFrame()
      local out = snapshotText()
      noFlags(out, id .. " tab" .. where)
      if id == "theme" then ok(out:find("<DemoTheme>", 1, true), "theme tab captured") end
      if id == "charts" then
        for _, mode in ipairs({ "Candles", "Bars", "Line" }) do
          find(root, "Button", function(n) return n.el.props.text == mode end)[1].region:_click()
          W.nextFrame()
          noFlags(snapshotText(), "charts " .. mode .. where)
        end
      end
      if id == "scroll" then
        ok(out:find("scrolls y %d+/%d+ x %d+/%d+"), "the both-directions view scrolls on both axes")
        ok(out:find("scrolls x", 1, true), "the horizontal view scrolls")
      end
    end
  end
  FxUIDevCharDB.demoTheme = nil
  root:update()
  find(root, "Window")[1].region:SetSize(980, 660)
  W.nextFrame()
  clickTab(root, "controls")
  fx("demo")
end)

test("dev: snapshots keep the newest five, skip the reload with -n, refuse in combat, report failures", function()
  local reloads = W.reloads or 0
  local said = chat(function()
    for _ = 1, 7 do fx("dev all -n") end
  end)
  eq(W.reloads or 0, reloads, "-n does not reload")
  ok(said:find("snapshot stored; it reaches disk on the next reload or logout", 1, true), "says when it reaches disk: " .. said)
  eq(#FxUIDevDB.snapshots, 5, "the five most recent kept")
  local newest = FxUIDevDB.snapshots[5]
  chat(function() fx("dev all -n") end)
  eq(#FxUIDevDB.snapshots, 5)
  eq(FxUIDevDB.snapshots[4], newest, "the oldest dropped")

  W.combat = true
  local count = #FxUIDevDB.snapshots
  local last = FxUIDevDB.snapshots[count]
  said = chat(function()
    fx("dev all")
    FxUIDev_Snapshot()
    fx("dev pick")
  end)
  W.combat = false
  eq(FxUIDevDB.snapshots[count], last, "no snapshot in combat")
  eq(W.reloads or 0, reloads, "no reload in combat")
  local _, refusals = said:gsub("not in combat", "")
  eq(refusals, 3, "each refusal says so: " .. said)
  ok(not (pickerFrame() and pickerFrame():IsShown()), "no picking in combat")

  local savedBuild = GetBuildInfo
  GetBuildInfo = function() error("no build") end
  said = chat(function() fx("dev all") end)
  GetBuildInfo = savedBuild
  ok(said:find("snapshot failed: ", 1, true) and said:find("no build", 1, true), "failure reported: " .. said)
  eq(FxUIDevDB.snapshots[#FxUIDevDB.snapshots], last, "nothing stored")
  eq(W.reloads or 0, reloads, "no reload after a failure")

  -- The key binding snapshots and reloads.
  FxUIDev_Snapshot()
  eq(W.reloads, reloads + 1, "key binding reloads")
  eq(BINDING_NAME_FXUI_DEV_SNAPSHOT, "Snapshot all FxUI and reload")
  eq(BINDING_NAME_FXUI_DEV_PICK, "Pick an FxUI element to export")
  eq(BINDING_HEADER_FXUI_DEV, "FxUI Dev")

  said = chat(function() fx("dev help") end)
  ok(said:find("/fx dev pick", 1, true) and said:find("/fx dev all", 1, true), "usage for anything else: " .. said)
end)

test("dev: snapshots record props, state, themes, scroll offsets and errors", function()
  local Probe = UI.component("SnapProbe", {
    init = function(ctx) ctx.state.n = 1 end,
    render = function()
      return UI.VStack { theme = "classic", padding = 4,
        UI.Text { text = "Probe", meta = { a = 1, b = "x" }, big = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }, nested = { { 1 } },
          node = UI.Text { text = "el" }, frame = UIParent, fn = function() end, co = coroutine.create(function() end) },
        UI.ScrollView { height = 40, UI.VStack { height = 400 } },
      }
    end,
  })
  local root = UI.mount(UIParent, Probe {})
  W.nextFrame()
  I.errors = I.errors or {}
  I.errors[#I.errors + 1] = { time = 0, message = "probe error" }
  chat(function() fx("dev all -n") end)
  table.remove(I.errors)
  local snap = FxUIDevDB.snapshots[#FxUIDevDB.snapshots]
  local tree
  for _, r in ipairs(snap.roots) do
    if r.tree.component == "SnapProbe" then tree = r.tree end
  end
  ok(tree, "probe captured")
  eq(tree.state.n, 1, "component state")
  eq(tree.renders, 1, "render count")
  local stack = tree.children[1]
  eq(stack.theme, "classic", "theme where it differs from the parent's")
  local text = stack.children[1]
  eq(text.props.meta.b, "x", "small flat tables inline")
  eq(text.props.big, "<table 9>", "large tables summarised")
  eq(text.props.nested, "<table 1>", "nested tables summarised")
  eq(text.props.node, "<element Text>", "elements summarised")
  eq(text.props.frame, "<Frame>", "regions summarised")
  eq(text.props.fn, "<fn>", "functions summarised")
  eq(text.props.co, "<thread>", "anything else by type")
  eq(text.region.type, "FontString")
  eq(text.region.text, "Probe")
  ok(text.region.font and text.region.font.size, "font recorded")
  local scroll = stack.children[2]
  ok(scroll.scroll and scroll.scroll[4] > 0, "scroll range recorded")
  local found
  for _, e in ipairs(snap.errors) do
    if e.message == "probe error" then found = true end
  end
  ok(found, "FxUI's errors recorded")
  local out = readSaved()
  ok(out:find("<SnapProbe>", 1, true) and out:find("probe error", 1, true), "reader prints it:\n" .. out)
  root:unmount()
end)

test("dev: snapshots record a sub-frame's scale where it differs from its frame's", function()
  local root = UI.mount(UIParent, UI.VStack { width = 100, height = 50 })
  W.nextFrame()
  local region = find(root, "VStack")[1].region
  local scaled = CreateFrame("Frame", nil, region)
  scaled:SetScale(0.5)
  region.scaledBadge = scaled
  local plain = CreateFrame("Frame", nil, region)
  region.plainBadge = plain
  chat(function() fx("dev all -n") end)
  local snap = FxUIDevDB.snapshots[#FxUIDevDB.snapshots]
  region.scaledBadge, region.plainBadge = nil, nil
  root:unmount()
  local byField = {}
  for _, r in ipairs(snap.roots) do
    for _, p in ipairs(r.tree.parts or {}) do
      if p.field == "scaledBadge" or p.field == "plainBadge" then byField[p.field] = p end
    end
  end
  ok(byField.scaledBadge and byField.plainBadge, "both sub-frames captured")
  eq(byField.scaledBadge and byField.scaledBadge.scale, math.floor(region:GetEffectiveScale() * 0.5 * 1000 + 0.5) / 1000, "the scaled sub-frame's scale")
  eq(byField.plainBadge and byField.plainBadge.scale, nil, "no scale where it is the frame's")
end)

test("dev: /fx dev picker highlights, walks up with the wheel, exports the selection", function()
  fx("demo")
  W.nextFrame()
  local root = rootNamed("DemoApp")
  local button = find(root, "Button", function(n) return n.el.props.text == "Primary" end)[1]
  local l, b, w, h = button.region:GetRect()
  W.cursorX, W.cursorY = l + w / 2, b + h / 2

  FxUIDev_Pick()
  W.nextFrame()
  local picker = pickerFrame()
  ok(picker and picker:IsShown(), "picker shown")
  eq(picker.selected, button, "innermost element under the cursor")
  ok(picker.label:GetText():find('Button "Primary"', 1, true), "label names the element")
  ok(picker.label:GetText():find("DemoApp > ", 1, true), "label gives the path from the root")
  ok(picker.box:IsShown(), "box follows the element")

  picker:_fire("OnMouseWheel", 1)
  W.nextFrame()
  eq(picker.selected, button.parent, "wheel up selects the parent")
  picker:_fire("OnMouseWheel", -1)
  W.nextFrame()
  eq(picker.selected, button, "wheel down returns to the child")
  picker:_fire("OnMouseWheel", -1)
  W.nextFrame()
  eq(picker.selected, button, "never below the innermost element")

  -- Scenario: wheel up once and click; the parent is stored as selected.
  picker:_fire("OnMouseWheel", 1)
  W.nextFrame()
  local parent = picker.selected
  eq(parent, button.parent)
  local reloads = W.reloads or 0
  picker:_fire("OnMouseDown", "LeftButton")
  ok(not picker:IsShown(), "picker closes on click")
  eq(W.reloads, reloads + 1, "reloads as for any snapshot")
  local snap = FxUIDevDB.snapshots[#FxUIDevDB.snapshots]
  ok(snap.selected, "selection stored in a new snapshot")
  local text = readSaved()
  ok(text:find("Selected #" .. snap.selected, 1, true), "reader shows the selection:\n" .. text)
  ok(text:find("Selected #" .. snap.selected .. " (picked in game)\n  screen pixels: ", 1, true), "with its screen rect")
  ok(text:find("<== SELECTED", 1, true), "marked in the tree")

  -- Picking the button itself prints it with its parts.
  fx("dev pick")
  W.nextFrame()
  picker:_fire("OnMouseDown", "LeftButton")
  text = readSaved()
  ok(text:find("label:FontString \"Primary\"", 1, true), "selection printed with parts:\n" .. text)

  -- Right click, Esc and combat stop without a snapshot.
  local count = #FxUIDevDB.snapshots
  local last = FxUIDevDB.snapshots[count]
  fx("dev pick")
  W.nextFrame()
  picker:_fire("OnMouseDown", "RightButton")
  ok(not picker:IsShown(), "right click stops")
  fx("dev pick")
  W.combat = true
  W.fireEvent("PLAYER_REGEN_DISABLED")
  ok(not picker:IsShown(), "entering combat stops")
  W.combat = false
  W.fireEvent("PLAYER_REGEN_ENABLED")
  fx("dev pick")
  fx("dev pick")
  ok(not picker:IsShown(), "the command again stops")
  eq(FxUIDevDB.snapshots[#FxUIDevDB.snapshots], last, "no snapshot taken")

  -- Nothing under the cursor.
  W.cursorX, W.cursorY = 1, 1
  fx("dev pick")
  W.nextFrame()
  eq(picker.selected, nil, "nothing selected")
  ok(not picker.box:IsShown(), "no box")
  eq(picker.label:GetText(), "No FxUI element here")
  picker:_fire("OnMouseDown", "LeftButton")
  eq(FxUIDevDB.snapshots[#FxUIDevDB.snapshots], last, "a click on nothing takes no snapshot")

  -- Hit testing follows the FxUI scale.
  UI.setScale(0.8)
  W.nextFrame()
  button = find(root, "Button", function(n) return n.el.props.text == "Primary" end)[1]
  local k = button.region:GetEffectiveScale() / UIParent:GetEffectiveScale()
  l, b, w, h = button.region:GetRect()
  W.cursorX, W.cursorY = (l + w / 2) * k, (b + h / 2) * k
  fx("dev pick")
  W.nextFrame()
  eq(picker.selected, button, "picked where it is drawn in a scaled window")
  picker:_fire("OnKeyDown", "ESCAPE")
  UI.setScale(1)
  W.nextFrame()
  fx("demo")
end)

test("dev: the picker takes the innermost element when mounted trees overlap", function()
  -- Empty full-screen trees (an empty toast stack, an overlay) over a window
  -- must not hide the window's elements, whichever tree is visited first.
  local overlays = {}
  for i = 1, 8 do
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetAllPoints(UIParent)
    overlays[i] = UI.mount(host, UI.VStack {})
  end
  local root = UI.mount(UIParent, UI.Window { title = "Under", width = 300, height = 200,
    UI.HStack { padding = 10, UI.Button { text = "Target" } } })
  W.nextFrame()
  local button = find(root, "Button", function(n) return n.el.props.text == "Target" end)[1]
  local l, b, w, h = button.region:GetRect()
  W.cursorX, W.cursorY = l + w / 2, b + h / 2
  fx("dev pick")
  W.nextFrame()
  local picker = pickerFrame()
  eq(picker.selected, button, "innermost element: " .. picker.label:GetText())
  picker:_fire("OnMouseWheel", 1)
  W.nextFrame()
  eq(picker.selected, button.parent, "the wheel walks up the window's own chain")
  picker:_fire("OnKeyDown", "ESCAPE")
  root:unmount()
  for _, o in ipairs(overlays) do o:unmount() end
end)

test("dev: /fx dev opens the dev window with capture and demo controls", function()
  fx("dev")
  W.nextFrame()
  local root = rootNamed("FxDevWindow")
  ok(root, "dev window mounted")
  -- It refreshes every second, the first time right after mounting.
  W.advance(0.2)
  W.nextFrame()
  ok(FxUIDevCharDB.devOpen == true, "open state saved")
  local function button(text)
    return find(root, "Button", function(n) return n.el.props.text == text end)[1]
  end
  local function texts()
    local out = {}
    for _, n in ipairs(find(root, "Text")) do out[#out + 1] = tostring(n.el.props.text) end
    return table.concat(out, "\n")
  end
  ok(button("Pick element") and button("Snapshot all") and button("Settings"), "inspect buttons present")
  local facts = texts()
  ok(facts:find("12.1.5 (70529)", 1, true) and facts:find("120105", 1, true), "client facts:\n" .. facts)
  ok(facts:find("stored", 1, true), "last snapshot shown")
  ok(facts:find("/fx demo", 1, true) and facts:find("/fx dev", 1, true), "commands listed")
  ok(facts:find("FxDevWindow", 1, true), "mounted trees listed")
  ok(facts:find("active", 1, true) and facts:find("pooled", 1, true), "region statistics")

  button("Demo").region:_click()
  W.nextFrame()
  ok(rootNamed("DemoApp"), "demo opened from the dev window")
  ok(button("Close demo"), "demo button reflects the open demo")
  ok(FxUIDevCharDB.demoOpen == true, "demo state saved")
  button("Settings").region:_click()
  ok(W.settings.opened, "settings opened")
  local reloads = W.reloads or 0
  button("Reload").region:_click()
  eq(W.reloads, reloads + 1, "reload button reloads")
  local count = #FxUIDevDB.snapshots
  button("Snapshot all").region:_click()
  eq(#FxUIDevDB.snapshots, math.min(count + 1, 5), "snapshot all")
  eq(W.reloads, reloads + 2, "and reloads")

  -- Theme buttons for every registered theme.
  button("FxUI Teal").region:_click()
  W.nextFrame()
  eq(UI.themeName, "teal")
  button("FxUI Dark").region:_click()
  W.nextFrame()
  eq(UI.themeName, "default")

  -- FxUI scale in 5 % steps, reset to 100 %, link to the FxUI options.
  button("+").region:_click()
  W.nextFrame()
  ok(math.abs(UI.scale - 1.05) < 1e-9, "larger")
  ok(button("105%"), "shows the percentage")
  button("\226\136\146").region:_click()
  button("\226\136\146").region:_click()
  W.nextFrame()
  ok(math.abs(UI.scale - 0.95) < 1e-9, "smaller")
  button("95%").region:_click()
  W.nextFrame()
  eq(UI.scale, 1, "back to 100%")
  button("Options").region:_click()
  eq(W.settings.opened, I.settingsCategory:GetID(), "FxUI options")

  -- Errors: count, the newest three, Clear.
  I.errors = I.errors or {}
  for i = 1, 4 do I.errors[#I.errors + 1] = { time = 0, message = "dev error " .. i .. "\nstack" } end
  W.advance(1.1)
  W.nextFrame()
  facts = texts()
  ok(facts:find("dev error 4", 1, true) and facts:find("dev error 2", 1, true) and not facts:find("dev error 1", 1, true), "newest three:\n" .. facts)
  button("Clear").region:_click()
  W.nextFrame()
  eq(#I.errors, 0, "cleared")
  ok(not button("Clear"), "nothing to clear")

  -- Pick element toggles the picker; Esc and the button itself stop it.
  button("Pick element").region:_click()
  W.nextFrame()
  ok(pickerFrame():IsShown(), "picking")
  local toggle = button("Picking\226\128\166 (Esc)")
  ok(toggle, "button shows picking state")
  local l, b, w, h = toggle.region:GetRect()
  W.cursorX, W.cursorY = l + w / 2, b + h / 2
  W.nextFrame()
  eq(pickerFrame().selected, nil, "the toggle button itself is never selected")
  eq(pickerFrame().label:GetText(), "Click to stop picking")
  local snaps = #FxUIDevDB.snapshots
  local last = FxUIDevDB.snapshots[snaps]
  pickerFrame():_fire("OnMouseDown", "LeftButton")
  ok(not pickerFrame():IsShown(), "clicking the toggle stops picking")
  eq(FxUIDevDB.snapshots[snaps], last, "no snapshot taken")
  W.nextFrame()
  button("Pick element").region:_click()
  W.nextFrame()
  button("Picking\226\128\166 (Esc)").region:_click()
  ok(not pickerFrame():IsShown(), "the button stops picking")
  W.nextFrame()
  button("Pick element").region:_click()
  pickerFrame():_fire("OnKeyDown", "A")
  ok(pickerFrame():IsShown() and pickerFrame()._propagate == true, "other keys pass through")
  pickerFrame():_fire("OnKeyDown", "ESCAPE")
  ok(not pickerFrame():IsShown() and pickerFrame()._propagate == false, "Esc stops picking and is consumed")
  W.nextFrame()
  ok(button("Pick element"), "button back to idle")

  -- In combat the reload action is disabled.
  W.combat = true
  W.fireEvent("PLAYER_REGEN_DISABLED")
  W.advance(1.1)
  W.nextFrame()
  ok(button("Reload").el.props.disabled, "reload disabled in combat")
  W.combat = false
  W.fireEvent("PLAYER_REGEN_ENABLED")
  W.advance(1.1)
  W.nextFrame()
  ok(not button("Reload").el.props.disabled, "enabled again after combat")

  -- Position and size are remembered per character.
  local frame = find(root, "Window")[1].region
  frame:SetSize(400, 360)
  frame:_fireSize()
  W.nextFrame()
  ok(FxUIDevCharDB.devWindow.width == 400 or FxUIDevCharDB.devWindow.w == 400 or next(FxUIDevCharDB.devWindow), "geometry saved")

  button("Close demo").region:_click()
  W.nextFrame()
  find(root, "Window")[1].region.close:_click()
  W.nextFrame()
  ok(not rootNamed("FxDevWindow") and not rootNamed("DemoApp"), "both closed")
  eq(FxUIDevCharDB.devOpen, false)
end)

test("dev: reopens the dev window and demo after a reload when enabled", function()
  FxUIDevCharDB.devOpen, FxUIDevCharDB.demoOpen = true, true
  chat(function() W.fireEvent("PLAYER_LOGIN") end)
  W.nextFrame()
  ok(rootNamed("FxDevWindow"), "dev window restored")
  ok(rootNamed("DemoApp"), "demo restored")
  fx("dev")
  fx("demo")
  W.nextFrame()
  FxUIDevCharDB.devOpen, FxUIDevCharDB.demoOpen = true, true
  FxUIDevCharDB.restore = false
  chat(function() W.fireEvent("PLAYER_LOGIN") end)
  W.nextFrame()
  ok(not rootNamed("FxDevWindow") and not rootNamed("DemoApp"), "not restored when the setting is off")
  FxUIDevCharDB.restore, FxUIDevCharDB.devOpen, FxUIDevCharDB.demoOpen = true, false, false
end)

test("dev: settings registered in the options panel and honoured", function()
  local category
  for _, c in ipairs(W.settings.categories) do
    if c.name == "FxUI Dev" then category = c end
  end
  ok(category and category.registered, "category registered")
  local restore = W.settings.settings.FXUI_DEV_RESTORE
  local reload = W.settings.settings.FXUI_DEV_SNAPSHOTRELOAD
  ok(restore and restore.checkbox and reload and reload.checkbox, "checkboxes created")
  eq(restore:GetValue(), true, "reopen after reload defaults on")
  eq(reload:GetValue(), true, "reload after a snapshot defaults on")
  local buttons = {}
  for _, init in ipairs(W.settings.initializers) do buttons[init.name] = init end
  ok(buttons["Dev window"] and buttons["Component demo"], "open buttons added")
  buttons["Dev window"].onClick()
  W.nextFrame()
  ok(rootNamed("FxDevWindow"), "the settings button opens the dev window")
  buttons["Dev window"].onClick()
  ok(rootNamed("FxDevWindow"), "and leaves it open")
  buttons["Component demo"].onClick()
  W.nextFrame()
  ok(rootNamed("DemoApp"), "the settings button toggles the demo")
  buttons["Component demo"].onClick()
  W.nextFrame()
  ok(not rootNamed("DemoApp"))

  reload:SetValue(false)
  W.nextFrame()
  local said
  local before = W.reloads or 0
  said = chat(function() fx("dev all") end)
  eq(W.reloads or 0, before, "no reload when the setting is off")
  ok(said:find("next reload or logout", 1, true), "says when it reaches disk: " .. said)
  reload:SetValue(true)
  fx("dev all")
  eq(W.reloads, before + 1, "reloads when on")
  fx("dev")
  W.nextFrame()
end)

test("dev: the FxUI scale resizes the demo, keeps its spot and saves it with its geometry", function()
  fx("demo")
  W.nextFrame()
  local root = rootNamed("DemoApp")
  local f = find(root, "Window")[1].region
  eq(f:GetScale(), 1, "starts at 100%")
  local left, top = f:GetLeft(), f:GetTop()
  UI.setScale(0.8)
  eq(f:GetScale(), 0.8, "window scaled")
  local p = f._points[1]
  ok(math.abs(p[4] - left / 0.8) < 0.01 and math.abs(p[5] - top / 0.8) < 0.01, "top-left kept on screen")
  eq(FxUIDevCharDB.window.scale, 0.8, "demo geometry saved with its scale")
  UI.setScale(1)
  fx("demo")
  W.nextFrame()
  fx("demo")
  W.nextFrame()
  local f2 = find(rootNamed("DemoApp"), "Window")[1].region
  eq(f2:GetScale(), 1, "reopened at the current scale")
  fx("demo")
end)

---------------------------------------------------------------------------

for _, t in ipairs(tests) do
  W.errors = {}
  local passed, err = pcall(t.fn)
  if passed and #W.errors > 0 then
    passed, err = false, "reported errors:\n" .. table.concat(W.errors, "\n")
  end
  if passed then
    print("ok   " .. t.name)
  else
    failures = failures + 1
    print("FAIL " .. t.name .. "\n     " .. tostring(err))
  end
end

print(string.format("\n%d tests, %d failed", #tests, failures))
os.exit(failures == 0 and 0 or 1)
