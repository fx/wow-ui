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
  for _, name in ipairs({ "Button", "Badge", "Toggle", "Tab", "TabRail", "ItemCell", "Meter", "Chart", "List", "HeaderCell", "Scroll", "Window", "WindowClose", "WindowFooter" }) do
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
  card = find(root, "VStack", function(n) return n.el.props.surface == "card" end)[1].region
  ok(not card.fxHasBackdrop and card.fxBg:IsShown(), "default card surface back")
  local win = find(root, "Window")[1].region
  ok(not win.fxSkinTex.Window:IsShown() and win.headerLine:IsShown(), "default window chrome back")
  root:unmount()
  W.items[17] = nil
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
  ok(GameTooltip:IsOwned(buttons[1].region), "tooltip on hover")
  buttons[1].region:_fire("OnLeave")
  ok(not GameTooltip:IsOwned(buttons[1].region), "tooltip hidden")
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
