-- Snapshot every mounted FxUI tree (and optionally any named frame) into
-- SavedVariables, then reload so the client writes it to disk. Read the
-- result with tools/inspect.lua.

local ADDON, ns = ...
local UI = LibStub("FxUI-1.0")
local I = UI._internal

local MAX_SNAPSHOTS = 5
local pickedNode -- set by the picker for the next snapshot
local MAX_DEPTH = 40

local function round(v)
  if type(v) ~= "number" then return v end
  return math.floor(v * 100 + 0.5) / 100
end

local function hex(r, g, b, a)
  if type(r) ~= "number" then return nil end
  local s = string.format("#%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
  if a and a < 0.999 then s = s .. string.format("@%.2f", a) end
  return s
end

local function passOk(ok, ...)
  if ok then return ... end
end

local function try(fn, ...)
  return passOk(pcall(fn, ...))
end

-- Effective scale of a region (font strings and textures use their frame's).
local function effectiveScale(region)
  if region.GetEffectiveScale then return region:GetEffectiveScale() end
  local parent = region:GetParent()
  return parent and parent:GetEffectiveScale() or 1
end
ns.effectiveScale = effectiveScale

-- Props and state: scalars as is, small flat tables inline, everything else
-- summarized so the snapshot stays small.
local function serializeValue(v, depth)
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" then return v end
  if t == "function" then return "<fn>" end
  if t == "table" then
    if UI.isElement(v) then return "<element " .. tostring(v.type.name) .. ">" end
    if v.GetObjectType then return "<" .. (try(v.GetObjectType, v) or "region") .. ">" end
    local n, flat = 0, true
    for _, x in pairs(v) do
      n = n + 1
      local xt = type(x)
      if xt ~= "string" and xt ~= "number" and xt ~= "boolean" then flat = false end
    end
    if depth < 2 and n <= 8 and flat then
      local out = {}
      for k, x in pairs(v) do out[k] = x end
      return out
    end
    return "<table " .. n .. ">"
  end
  return "<" .. t .. ">"
end

local SKIP_PROPS = { key = true }

local function serializeProps(props)
  local out = {}
  for k, v in pairs(props or {}) do
    if not SKIP_PROPS[k] then out[k] = serializeValue(v, 0) end
  end
  return out
end

-- What the client reports about one region.
local function regionInfo(r)
  local info = { type = try(r.GetObjectType, r) }
  local left, bottom, w, h = try(r.GetRect, r)
  if left then
    info.rect = { round(left), round(bottom), round(w), round(h) }
  end
  info.shown = try(r.IsShown, r)
  info.visible = try(r.IsVisible, r)
  local alpha = try(r.GetAlpha, r)
  if alpha and alpha < 0.999 then info.alpha = round(alpha) end

  local kind = info.type
  if kind == "FontString" then
    info.text = try(r.GetText, r)
    local file, size, flags = try(r.GetFont, r)
    info.font = file and { file = tostring(file):match("([^\\/]+)$") or file, size = round(size), flags = flags ~= "" and flags or nil }
    info.color = hex(try(r.GetTextColor, r))
    info.textWidth = round(try(r.GetStringWidth, r))
    if r.GetUnboundedStringWidth then info.unbounded = round(try(r.GetUnboundedStringWidth, r)) end
    if r.IsTruncated then info.truncated = try(r.IsTruncated, r) or nil end
    info.justify = try(r.GetJustifyH, r)
    info.wrap = try(r.CanWordWrap, r)
  elseif kind == "Texture" or kind == "MaskTexture" then
    -- Addon files only get a temporary file ID (negative, or the same as
    -- unsigned), so prefer the file FxUI recorded when it set the texture.
    local tex = r.fxFile
    if not tex then
      tex = r.GetTextureFilePath and try(r.GetTextureFilePath, r) or try(r.GetTexture, r)
      if type(tex) == "string" then tex = tex:match("([^\\/]+)$") or tex end
    end
    -- SetColorTexture leaves no file; the client has no getter for its color.
    info.texture = tex or "solid color"
    info.atlas = r.GetAtlas and try(r.GetAtlas, r) or nil
    info.vertex = hex(try(r.GetVertexColor, r))
    if r.GetTextureSliceMargins then
      local a, b, c, d = try(r.GetTextureSliceMargins, r)
      if a and (a > 0 or b > 0 or c > 0 or d > 0) then info.slice = { round(a), round(b), round(c), round(d) } end
    end
    info.layer = try(r.GetDrawLayer, r)
    if r.GetTexCoord then
      local ulx, uly, llx, lly, urx, ury, lrx, lry = try(r.GetTexCoord, r)
      if ulx and not (ulx == 0 and uly == 0 and lrx == 1 and lry == 1) then
        info.uv = { round(ulx), round(urx), round(uly), round(lly), flipped = (uly or 0) > (lly or 0) or nil }
      end
    end
    if r.GetBlendMode then
      local blend = try(r.GetBlendMode, r)
      if blend and blend ~= "BLEND" then info.blend = blend end
    end
  elseif kind == "Line" then
    info.thickness = round(try(r.GetThickness, r))
    info.vertex = hex(try(r.GetVertexColor, r))
  else
    info.name = try(r.GetName, r)
    info.strata = try(r.GetFrameStrata, r)
    info.level = try(r.GetFrameLevel, r)
    info.mouse = try(r.IsMouseEnabled, r) or nil
    if r.DoesClipChildren then info.clips = try(r.DoesClipChildren, r) or nil end
    if r.IsEnabled then info.enabled = try(r.IsEnabled, r) end
  end
  return info
end

-- Field names a frame holds its sub-regions under (label, fxBg, ...),
-- added to `names` (a host keeps fields for regions of its sub-frames too).
local function fieldNames(frame, names)
  names = names or {}
  for key, tex in pairs(frame.fxSkinTex or {}) do names[tex] = "skin:" .. key end
  local sc = frame.fxScroller
  if sc then
    names[sc.content] = "scrollContent"
    names[sc.thumbY] = "scrollThumbY"
    names[sc.thumbX] = "scrollThumbX"
  end
  for k, v in pairs(frame) do
    if type(k) == "string" and type(v) == "table" and v.GetObjectType then
      names[v] = names[v] or k
    end
  end
  return names
end

-- A frame's own regions and the child frames that are not FxUI nodes.
local function frameParts(frame, depth, names)
  local parts = {}
  names = fieldNames(frame, names)
  local regions = { try(frame.GetRegions, frame) }
  for _, r in ipairs(regions) do
    -- Regions that are FxUI nodes themselves (Text, Money, ...) are dumped as nodes.
    if not r.fxNode then
      local info = regionInfo(r)
      info.field = names[r]
      parts[#parts + 1] = info
    end
  end
  if depth < MAX_DEPTH then
    local children = { try(frame.GetChildren, frame) }
    for _, c in ipairs(children) do
      if not c.fxNode then
        local info = regionInfo(c)
        info.field = names[c]
        info.parts = frameParts(c, depth + 1, names)
        parts[#parts + 1] = info
      end
    end
  end
  return parts
end

local nextId

local function dumpNode(node, depth, ids)
  nextId = nextId + 1
  local out = { id = nextId, key = node.key }
  ids[node] = nextId
  if node.def then
    out.component = node.def.name
    out.props = serializeProps(node.el.props)
    out.state = serializeProps(node.ctx and node.ctx.state)
    out.renders = node.renders
    if node.child then out.children = { dumpNode(node.child, depth + 1, ids) } end
    return out
  end

  out.host = node.host.name
  out.props = serializeProps(node.el.props)
  if node.theme ~= (node.parent and node.parent.theme or node.root.theme) or (not node.parent and node.theme) then
    out.theme = node.theme and node.theme.name or "global"
  end
  if node.region then out.scale = round(effectiveScale(node.region) * 1000) / 1000 end
  local r = node.region
  local sc = r and (r.fxScroller or (r.body and r.body.fxScroller))
  if sc and ((sc.maxX or 0) > 0 or (sc.maxY or 0) > 0) then
    out.scroll = { round(sc.offsetX), round(sc.maxX), round(sc.offsetY), round(sc.maxY) }
  end
  if node.x then out.layout = { round(node.x), round(node.y), round(node.w), round(node.h) } end
  if node.region then
    out.region = regionInfo(node.region)
    if node.region.GetRegions then out.parts = frameParts(node.region, depth) end
  end
  local kids = {}
  for _, list in ipairs({ node.headerChildren or {}, node.children or {}, node.footerChildren or {} }) do
    for _, c in ipairs(list) do
      if depth < MAX_DEPTH then kids[#kids + 1] = dumpNode(c, depth + 1, ids) end
    end
  end
  if node.headerChildren then out.headerCount = #node.headerChildren end
  if #kids > 0 then out.children = kids end
  return out
end

-- Any frame by reference: its regions and child frames, recursively.
local function dumpFrame(frame, depth)
  local info = regionInfo(frame)
  if frame.GetRegions and depth < MAX_DEPTH then
    info.parts = frameParts(frame, depth)
  end
  return info
end

local function hoveredFrames()
  local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
  return foci or {}
end

local function snapshot(extraFrames)
  nextId = 0
  local ids = {}
  local snap = {
    time = time(),
    date = date("%Y-%m-%d %H:%M:%S"),
    fxui = UI.MAJOR .. "." .. UI.MINOR,
    theme = UI.themeName,
    uiScale = round(UIParent:GetEffectiveScale() * 1000) / 1000,
    fxScale = UI.scale,
    uiSize = { round(UIParent:GetWidth()), round(UIParent:GetHeight()) },
    roots = {},
    frames = {},
    errors = {},
  }
  local version, build, _, iface = GetBuildInfo()
  snap.client = { version = version, build = build, interface = iface }
  local sw, sh = GetPhysicalScreenSize()
  snap.screen = { sw, sh }

  local _, total = UI.stats()
  snap.stats = total

  for root in pairs(I.roots) do
    if root.node then
      snap.roots[#snap.roots + 1] = {
        parent = try(root.frame.GetName, root.frame) or (root.frame == UIParent and "UIParent") or "<anonymous>",
        tree = dumpNode(root.node, 0, ids),
      }
    end
  end

  -- What the mouse is over: FxUI node ids where the frame belongs to a node.
  snap.hover = {}
  for _, f in ipairs(hoveredFrames()) do
    local probe, nodeId = f, nil
    while probe and not nodeId do
      if probe.fxNode then nodeId = ids[probe.fxNode] end
      probe = try(probe.GetParent, probe)
    end
    snap.hover[#snap.hover + 1] = { name = try(f.GetName, f), type = try(f.GetObjectType, f), node = nodeId }
  end

  for _, name in ipairs(extraFrames or {}) do
    local f = _G[name]
    if type(f) == "table" and f.GetObjectType then
      snap.frames[#snap.frames + 1] = { name = name, tree = dumpFrame(f, 0) }
    else
      snap.frames[#snap.frames + 1] = { name = name, missing = true }
    end
  end

  if pickedNode then
    snap.selected = ids[pickedNode]
    pickedNode = nil
  end

  for _, e in ipairs(I.errors or {}) do snap.errors[#snap.errors + 1] = e end
  return snap
end

local function store(snap)
  FxUIDevDB = FxUIDevDB or {}
  local list = FxUIDevDB.snapshots or {}
  FxUIDevDB.snapshots = list
  list[#list + 1] = snap
  while #list > MAX_SNAPSHOTS do table.remove(list, 1) end
end

local function dump(extraFrames, reload)
  if InCombatLockdown() then
    print("|cffE2B04AFxUI Dev|r: not in combat.")
    return
  end
  local ok, snap = pcall(snapshot, extraFrames)
  if not ok then
    print("|cffE2B04AFxUI Dev|r: snapshot failed: " .. tostring(snap))
    return
  end
  store(snap)
  -- nil follows the "Reload after a snapshot" setting.
  if reload == nil then reload = not (FxUIDevCharDB and FxUIDevCharDB.snapshotReload == false) end
  if reload == false then
    print("|cffE2B04AFxUI Dev|r: snapshot stored; it reaches disk on the next reload or logout.")
    return
  end
  ReloadUI()
end

---------------------------------------------------------------------------
-- Picker: highlight the FxUI element under the cursor, click to export it
---------------------------------------------------------------------------

local picker
local GOLD = { 0.886, 0.69, 0.29 }

-- Host nodes under the cursor, outermost first, from every mounted tree.
-- A region's rect in UIParent units. Regions report rects in their own
-- scale, which differs from UIParent's inside FxUI-scaled windows.
local function uiRect(region)
  local l, b, w, h = region:GetRect()
  if not l then return nil end
  local k = effectiveScale(region) / UIParent:GetEffectiveScale()
  return l * k, b * k, w * k, h * k
end

local function nodesAt(x, y)
  local hits = {}
  local function visit(node)
    if not node.alive then return end
    if node.host and node.region and node.region:IsVisible() then
      local l, b, w, h = uiRect(node.region)
      if l and x >= l and x <= l + w and y >= b and y <= b + h then
        hits[#hits + 1] = node
      end
    end
    if node.child then visit(node.child) end
    for _, list in ipairs({ node.headerChildren or {}, node.children or {}, node.footerChildren or {} }) do
      for _, c in ipairs(list) do visit(c) end
    end
  end
  for root in pairs(I.roots) do
    if root.node and root.frame ~= picker then visit(root.node) end
  end
  -- Keep only one chain: each hit must sit inside the previous one.
  local chain = {}
  for _, n in ipairs(hits) do
    local p, inside = n.parent, #chain == 0
    while p and not inside do
      if p == chain[#chain] then inside = true end
      p = p.parent
    end
    if inside then chain[#chain + 1] = n end
  end
  return chain
end

local function nodeLabel(node)
  local p = node.el.props
  local text = p.text or p.title or p.label
  local s = node.host.name .. (text and (' "' .. tostring(text) .. '"') or "")
  local _, _, w, h = node.region:GetRect()
  if w then s = s .. string.format("  %dx%d", math.floor(w + 0.5), math.floor(h + 0.5)) end
  return s
end

local function pathOf(node)
  local parts = {}
  local n = node
  while n do
    parts[#parts + 1] = n.def and n.def.name or n.host.name
    n = n.parent
  end
  local out = {}
  for i = #parts, 1, -1 do out[#out + 1] = parts[i] end
  return table.concat(out, " > ")
end

local function edge(parent)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  return t
end

-- The frame that toggles picking (the dev window's button). Clicks over it
-- stop picking instead of selecting it.
local function overToggle(x, y)
  local t = ns.pickToggle
  if not (t and t:IsVisible()) then return false end
  local l, b, w, h = uiRect(t)
  return l and x >= l and x <= l + w and y >= b and y <= b + h
end

local function createPicker()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetAllPoints(UIParent)
  f:SetFrameStrata("TOOLTIP")
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f:EnableKeyboard(true)
  f:Hide()

  -- Esc stops picking; every other key goes on to the game.
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      self:Hide()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  f:SetScript("OnShow", function() if ns.onPickChanged then ns.onPickChanged(true) end end)
  f:SetScript("OnHide", function() if ns.onPickChanged then ns.onPickChanged(false) end end)
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:SetScript("OnEvent", function(self) self:Hide() end)

  local box = CreateFrame("Frame", nil, f)
  box.fill = box:CreateTexture(nil, "BACKGROUND")
  box.fill:SetAllPoints()
  box.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
  box.top, box.bottom, box.left, box.right = edge(box), edge(box), edge(box), edge(box)
  box.top:SetPoint("TOPLEFT"); box.top:SetPoint("TOPRIGHT"); box.top:SetHeight(1)
  box.bottom:SetPoint("BOTTOMLEFT"); box.bottom:SetPoint("BOTTOMRIGHT"); box.bottom:SetHeight(1)
  box.left:SetPoint("TOPLEFT"); box.left:SetPoint("BOTTOMLEFT"); box.left:SetWidth(1)
  box.right:SetPoint("TOPRIGHT"); box.right:SetPoint("BOTTOMRIGHT"); box.right:SetWidth(1)
  f.box = box

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.label:SetJustifyH("LEFT")
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.hint:SetPoint("TOP", UIParent, "TOP", 0, -60)
  f.hint:SetText("FxUI Dev: click to export \194\183 wheel for parent/child \194\183 right-click or Esc to cancel")

  f.depth = 0 -- how many levels above the innermost hit
  f:SetScript("OnUpdate", function(self)
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    if overToggle(cx, cy) then
      self.chain, self.selected = {}, nil
      self.box:Hide()
      self.label:SetText("Click to stop picking")
      self.label:ClearAllPoints()
      self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 16, cy + 8)
      return
    end
    local chain = nodesAt(cx, cy)
    self.chain = chain
    local index = #chain - self.depth
    if index < 1 then index = 1 end
    local node = chain[index]
    self.selected = node
    if not node then
      self.box:Hide()
      self.label:SetText("No FxUI element here")
      self.label:ClearAllPoints()
      self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 16, cy + 8)
      return
    end
    local l, b, w, h = uiRect(node.region)
    self.box:ClearAllPoints()
    self.box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    self.box:SetSize(math.max(w, 1), math.max(h, 1))
    self.box:Show()
    self.label:SetText(nodeLabel(node) .. "\n|cff9AA0A8" .. pathOf(node) .. "|r")
    self.label:ClearAllPoints()
    self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 16, cy + 8)
  end)
  f:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(#(self.chain or {}) - 1, 0)
    self.depth = math.min(math.max(self.depth + (delta > 0 and 1 or -1), 0), max)
  end)
  f:SetScript("OnMouseDown", function(self, button)
    local node = self.selected
    self:Hide()
    if button ~= "LeftButton" then return end
    if node then
      pickedNode = node
      dump(nil)
    end
  end)
  return f
end

-- Start picking, or stop if already picking.
local function pick()
  if picker and picker:IsShown() then
    picker:Hide()
    return
  end
  if InCombatLockdown() then
    print("|cffE2B04AFxUI Dev|r: not in combat.")
    return
  end
  picker = picker or createPicker()
  picker.depth = 0
  picker:Show()
end

ns.isPicking = function()
  return picker ~= nil and picker:IsShown()
end

-- Keybinding entry points (Bindings.xml).
function FxUIDev_Pick()
  pick()
end

function FxUIDev_Snapshot()
  dump(nil)
end

BINDING_HEADER_FXUI_DEV = "FxUI Dev"
BINDING_NAME_FXUI_DEV_PICK = "Pick an FxUI element to export"
BINDING_NAME_FXUI_DEV_SNAPSHOT = "Snapshot all FxUI and reload"

---------------------------------------------------------------------------
-- Dev window
---------------------------------------------------------------------------

local devRoot, devOpen = nil, false
local renderDev

local function charDB()
  FxUIDevCharDB = FxUIDevCharDB or {}
  local db = FxUIDevCharDB
  if db.restore == nil then db.restore = true end
  if db.snapshotReload == nil then db.snapshotReload = true end
  db.devWindow = db.devWindow or {}
  return db
end

-- Compact building blocks; these become proper compact components later.
local function Heading(text)
  return UI.Text { text = text, style = "label", color = "muted" }
end

local function Fact(label, value, opts)
  opts = opts or {}
  return UI.HStack {
    gap = 6,
    align = "start",
    UI.Text { text = label, color = "muted", width = 80 },
    UI.Text { text = tostring(value), style = opts.mono and "mono" or "body", color = opts.color or "text", wrap = opts.wrap ~= false, flex = 1 },
  }
end

local function rootNames()
  local names = {}
  for root in pairs(I.roots) do
    local node = root.node
    if node then
      local name = node.def and node.def.name or (node.host and node.host.name) or "?"
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

local function commandNames()
  local names = {}
  for name in pairs(UI.commands or {}) do names[#names + 1] = "/fx " .. name end
  table.sort(names)
  return names
end

local function themeNames()
  local names = {}
  for name in pairs(UI.themes) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local DevWindow = UI.component("FxDevWindow", {
  init = function(ctx)
    local function tick()
      ctx:forceUpdate()
      ctx:after(1, tick)
    end
    -- First refresh right after mounting, once this window counts as mounted.
    ctx:after(0.1, tick)
  end,
  render = function(props)
    local db = charDB()
    local version, build, _, iface = GetBuildInfo()
    local _, stats = UI.stats()
    local snaps = FxUIDevDB and FxUIDevDB.snapshots or {}
    local last = snaps[#snaps]
    local errors = I.errors or {}
    local demoOpen = ns.demo and ns.demo.isOpen()
    local picking = ns.isPicking()

    local themeButtons = {}
    for _, t in ipairs(UI.listThemes()) do
      themeButtons[#themeButtons + 1] = UI.Button {
        text = t.title,
        size = "sm",
        variant = t.name == UI.themeName and "primary" or "ghost",
        onClick = function() UI.setTheme(t.name) end,
      }
    end

    local errorRows = {}
    for i = #errors, math.max(#errors - 2, 1), -1 do
      local e = errors[i]
      local first = (e.message or ""):match("^[^\n]*") or ""
      errorRows[#errorRows + 1] = UI.HStack {
        gap = 6,
        align = "start",
        UI.Text { text = date("%H:%M:%S", e.time or 0), style = "mono", color = "muted", width = 64 },
        UI.Text { text = first, color = "down", wrap = true, maxLines = 2, flex = 1 },
      }
    end

    return UI.Window {
      title = "FxUI Dev",
      size = "sm",
      width = 360,
      height = 320,
      minWidth = 300,
      minHeight = 200,
      saved = db.devWindow,
      onClose = props.onClose,
      actions = {
        {
          text = "Reload",
          disabled = UI.inCombat(),
          tooltip = "Reload the UI (/reload).",
          onClick = function() ReloadUI() end,
        },
        {
          text = "Settings",
          tooltip = "Options > AddOns > FxUI Dev",
          onClick = function() if ns.openSettings then ns.openSettings() end end,
        },
      },
      status = UI.MAJOR:match("%d+%.%d+$") .. "." .. UI.MINOR,
      UI.VStack {
        gap = 6,
        padding = 10,
        UI.HStack {
          gap = 6,
          UI.Button {
            text = picking and "Picking\226\128\166 (Esc)" or "Pick element",
            size = "sm",
            variant = picking and "primary" or "secondary",
            tooltip = "Hover an element, wheel for parent or child, click to export it. Click again or press Esc to stop.",
            ref = function(f) ns.pickToggle = f end,
            onClick = function() ns.pick() end,
          },
          UI.Button {
            text = "Snapshot all",
            size = "sm",
            tooltip = "Export every mounted FxUI tree.",
            onClick = function() ns.dump(nil) end,
          },
          UI.Spacer {},
          UI.Button {
            text = demoOpen and "Close demo" or "Demo",
            size = "sm",
            variant = demoOpen and "primary" or "secondary",
            onClick = function() if ns.demo then ns.demo.toggle() end end,
          },
        },
        Fact("Snapshot", last and (last.date:sub(12) .. "  \194\183  " .. #snaps .. " stored" .. (db.snapshotReload == false and "  \194\183  no reload" or "")) or "none yet", { mono = true }),
        UI.Divider {},
        UI.HStack { gap = 4, rowGap = 4, wrap = true, align = "center", Heading("Theme"), UI.Spacer { size = 6 }, themeButtons },
        UI.Divider {},
        Fact("Client", string.format("%s (%s)  \194\183  %s", tostring(version), tostring(build), tostring(iface)), { mono = true }),
        Fact("UI", string.format("%.0fx%.0f  scale %.2f", UIParent:GetWidth(), UIParent:GetHeight(), UIParent:GetEffectiveScale()), { mono = true }),
        UI.HStack {
          gap = 6,
          align = "center",
          UI.Text { text = "FxUI scale", color = "muted", width = 80 },
          UI.Button { text = "\226\136\146", size = "sm", width = 28, tooltip = "Smaller (5%)", onClick = function() UI.setScale((UI.scale or 1) - 0.05) end },
          UI.Button {
            text = string.format("%d%%", math.floor((UI.scale or 1) * 100 + 0.5)),
            size = "sm",
            variant = "ghost",
            width = 52,
            tooltip = "Click for 100%",
            onClick = function() UI.setScale(1) end,
          },
          UI.Button { text = "+", size = "sm", width = 28, tooltip = "Larger (5%)", onClick = function() UI.setScale((UI.scale or 1) + 0.05) end },
          UI.Spacer {},
          UI.Button { text = "Options", size = "sm", variant = "ghost", tooltip = "Options > AddOns > FxUI", onClick = function() UI.openSettings() end },
        },
        Fact("Regions", string.format("%d active  %d pooled  %d made", stats.active, stats.pooled, stats.created), { mono = true }),
        Fact("Mounted", table.concat(rootNames(), ", "), { wrap = true }),
        Fact("Commands", table.concat(commandNames(), "  "), { wrap = true }),
        UI.Divider {},
        UI.HStack {
          gap = 6,
          align = "center",
          Heading("Errors"),
          UI.Text { text = tostring(#errors), style = "mono", color = #errors > 0 and "down" or "muted" },
          UI.Spacer {},
          #errors > 0 and UI.Button {
            text = "Clear",
            size = "sm",
            variant = "ghost",
            onClick = function()
              I.wipe(errors)
              renderDev()
            end,
          } or nil,
        },
        errorRows,
      },
    }
  end,
})

renderDev = function()
  local db = charDB()
  db.devOpen = devOpen
  if not devOpen then
    if devRoot then
      devRoot:unmount()
      devRoot = nil
    end
    return
  end
  local el = DevWindow {
    onClose = function()
      devOpen = false
      renderDev()
    end,
  }
  if devRoot then devRoot:update(el) else devRoot = UI.mount(UIParent, el) end
end

local function toggleDev()
  devOpen = not devOpen
  renderDev()
end

ns.pick, ns.dump = pick, dump
ns.onPickChanged = function()
  if devRoot then renderDev() end
end

ns.onDemoChanged = function(open)
  charDB().demoOpen = open
  if devRoot then renderDev() end
end

---------------------------------------------------------------------------
-- Addon settings: Options > AddOns > FxUI Dev
---------------------------------------------------------------------------

local settingsCategory

local function registerSettings()
  if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local db = charDB()
  local category, layout = Settings.RegisterVerticalLayoutCategory("FxUI Dev")

  local function checkbox(key, name, tooltip, default)
    local setting = Settings.RegisterAddOnSetting(category, "FXUI_DEV_" .. key:upper(), key, db, type(default), name, default)
    Settings.CreateCheckbox(category, setting, tooltip)
    if setting.SetValueChangedCallback then
      setting:SetValueChangedCallback(function()
        if devRoot then renderDev() end
      end)
    end
  end

  checkbox("restore", "Reopen after reload",
    "Reopen the dev window and the demo after a reload if they were open.", true)
  checkbox("snapshotReload", "Reload after a snapshot",
    "Reload right after taking a snapshot so the client writes it to disk. Off: the snapshot waits in memory until the next reload or logout.", true)

  if CreateSettingsButtonInitializer and layout and layout.AddInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer("Dev window", "Open", function()
      if not devOpen then
        devOpen = true
        renderDev()
      end
    end, "Open the FxUI dev window (/fx dev).", true))
    layout:AddInitializer(CreateSettingsButtonInitializer("Component demo", "Toggle", function()
      if ns.demo then ns.demo.toggle() end
    end, "Open or close the component demo (/fx demo).", true))
  end

  Settings.RegisterAddOnCategory(category)
  settingsCategory = category
end

ns.openSettings = function()
  if settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(settingsCategory:GetID())
  end
end

-- Reopen what was open before the reload.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == ADDON then I.safecall(registerSettings) end
    return
  end
  local db = charDB()
  if not db.restore then return end
  if db.devOpen then
    devOpen = true
    renderDev()
  end
  if db.demoOpen and ns.demo and not ns.demo.isOpen() then ns.demo.toggle() end
end)

-- /fx dev                 open or close the dev window
-- /fx dev pick            pick an element with the mouse, click to snapshot and reload
-- /fx dev all [names]     snapshot all FxUI trees (and named frames) and reload
-- /fx dev all -n [names]  snapshot without reloading
UI.registerCommand("dev", function(args)
  local words = {}
  for word in args:gmatch("%S+") do words[#words + 1] = word end
  local sub = (words[1] or ""):lower()
  if sub == "" then
    toggleDev()
  elseif sub == "pick" then
    pick()
  elseif sub == "all" then
    local names, reload = {}, nil
    for i = 2, #words do
      if words[i] == "-n" then reload = false else names[#names + 1] = words[i] end
    end
    dump(names, reload)
  else
    print("|cffE2B04A/fx dev|r          open the dev window")
    print("|cffE2B04A/fx dev pick|r     pick an element and export it")
    print("|cffE2B04A/fx dev all|r      export every FxUI tree; add frame names to include them, -n to skip the reload")
  end
end, "dev window; 'pick' to export an element, 'all' to export everything")
