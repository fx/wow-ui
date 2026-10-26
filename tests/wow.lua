-- A strict, minimal stand-in for the client API, enough to load and drive
-- FxUI under plain Lua 5.1. Methods the stub does not define
-- raise an error, so a misspelt API call fails here rather than in game.

local W = { frames = {}, created = {}, errors = {}, timers = {}, now = 0, items = {} }

local function count(kind)
  W.created[kind] = (W.created[kind] or 0) + 1
end

-- Escape codes take no room; an inline texture (|T...|t) is about two glyphs.
local function stripCodes(s)
  return (s:gsub("|T.-|t", "WW"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

local function utf8len(s)
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end

---------------------------------------------------------------------------
-- Classes
---------------------------------------------------------------------------

local Region, Frame, Button, Texture, Line, Mask, FontString, Font = {}, {}, {}, {}, {}, {}, {}, {}
local ALL = { Region, Frame, Button, Texture, Line, Mask, FontString, Font }
local universe = {}

local function inherit(child, parent)
  for k, v in pairs(parent) do
    if child[k] == nil then child[k] = v end
  end
end

local function noop() end

local function setters(class, names)
  for name in names:gmatch("%S+") do class[name] = noop end
end

-- Region
function Region:SetPoint(point, rel, relPoint, x, y)
  -- Shorthands: SetPoint(point), SetPoint(point, x, y), SetPoint(point, rel, x, y)
  if type(rel) == "number" then
    rel, relPoint, x, y = nil, point, rel, relPoint
  elseif type(relPoint) == "number" then
    relPoint, x, y = point, relPoint, x
  end
  self._points = self._points or {}
  self._points[#self._points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
end
function Region:ClearAllPoints() self._points = {} end
function Region:SetAllPoints(rel) self._points = { { "ALL", rel } } end
function Region:SetSize(w, h)
  local changed = w ~= self._w or h ~= self._h
  self._w, self._h = w, h
  if changed and self._fireSize then self:_fireSize() end
end
function Region:SetWidth(w) self:SetSize(w, self._h or 0) end
function Region:SetHeight(h) self:SetSize(self._w or 0, h) end
function Region:GetWidth() return self._w or 0 end
function Region:GetHeight() return self._h or 0 end
function Region:GetSize() return self._w or 0, self._h or 0 end
-- Frames get OnShow / OnHide when their own shown flag changes.
local function setShown(self, v)
  local was = self._shown ~= false
  self._shown = v
  if was ~= v and self._fire then self:_fire(v and "OnShow" or "OnHide") end
end
function Region:Show() setShown(self, true) end
function Region:Hide() setShown(self, false) end
function Region:SetShown(v) setShown(self, v and true or false) end
function Region:IsShown() return self._shown ~= false end
function Region:SetAlpha(a) self._alpha = a end
function Region:SetParent(p)
  local old = self._parent
  if old and old._regions and self._type ~= "Frame" and self._type ~= "Button" then
    for i, r in ipairs(old._regions) do
      if r == self then table.remove(old._regions, i) break end
    end
    p._regions = p._regions or {}
    table.insert(p._regions, self)
  end
  self._parent = p
end
function Region:GetParent() return self._parent end
-- Where an anchor point lands, in screen coordinates.
local function anchorPos(self, p)
  local rel = p[2] or self._parent
  if not rel or not rel.GetRect then return nil end
  local rl, rb, rw, rh = rel:GetRect()
  if not rl then return nil end
  local rp = p[3]
  local ax = rp:find("LEFT") and rl or (rp:find("RIGHT") and rl + rw or rl + rw / 2)
  local ay = rp:find("TOP") and rb + rh or (rp:find("BOTTOM") and rb or rb + rh / 2)
  return ax + p[4], ay + p[5]
end

-- Resolves any set of anchors: each point fixes the edges it names (LEFT,
-- RIGHT, TOP, BOTTOM) or the centre; missing edges come from the size.
function Region:GetRect()
  if self == UIParent then return 0, 0, self._w, self._h end
  local points = self._points
  if not points or #points == 0 then return nil end
  local first = points[1]
  if first[1] == "ALL" then
    local rel = first[2] or self._parent
    if rel and rel.GetRect then return rel:GetRect() end
    return nil
  end
  local w, h = self._w or 0, self._h or 0
  local left, right, top, bottom, cx, cy
  for _, p in ipairs(points) do
    local x, y = anchorPos(self, p)
    if not x then return nil end
    local pt = p[1]
    if pt:find("LEFT") then left = x elseif pt:find("RIGHT") then right = x else cx = x end
    if pt:find("TOP") then top = y elseif pt:find("BOTTOM") then bottom = y else cy = y end
  end
  if left and right then w = right - left
  elseif left then right = left + w
  elseif right then left = right - w
  else left = (cx or 0) - w / 2 end
  if top and bottom then h = top - bottom
  elseif top then bottom = top - h
  elseif bottom then top = bottom + h
  else bottom = (cy or 0) - h / 2 end
  return left, bottom, w, h
end
function Region:GetLeft() return (self:GetRect()) or 100 end
function Region:GetRight()
  local l, _, w = self:GetRect()
  return l and (l + w) or nil
end
function Region:GetBottom()
  local _, b = self:GetRect()
  return b
end
function Region:GetTop()
  local l, b, _, h = self:GetRect()
  return l and (b + h) or 700
end
function Region:GetObjectType() return self._type end
function Region:IsVisible()
  if self._shown == false then return false end
  if self._parent and self._parent.IsVisible then return self._parent:IsVisible() end
  return true
end
function Region:GetAlpha() return self._alpha or 1 end
function Region:GetName() return nil end
function Region:GetDrawLayer() return self._layer end

-- Frame
inherit(Frame, Region)
function Frame:CreateTexture(_, layer)
  count("Texture")
  return self:_own(W.new(Texture, { _parent = self, _layer = layer, _type = "Texture" }))
end
function Frame:CreateLine(_, layer)
  count("Line")
  return self:_own(W.new(Line, { _parent = self, _layer = layer, _type = "Line" }))
end
function Frame:CreateMaskTexture()
  count("MaskTexture")
  return self:_own(W.new(Mask, { _parent = self, _type = "MaskTexture" }))
end
function Frame:CreateFontString(_, layer, template)
  count("FontString")
  local font = template and _G[template]
  if template then assert(font, "stub: unknown font template " .. template) end
  return self:_own(W.new(FontString, { _parent = self, _layer = layer, _text = "", _type = "FontString", _font = font }))
end
function Frame:_own(region)
  self._regions = self._regions or {}
  table.insert(self._regions, region)
  return region
end
function Frame:SetScript(name, fn) self._scripts[name] = fn end
function Frame:GetScript(name) return self._scripts[name] end
function Frame:HookScript(name, fn)
  self._hooks[name] = self._hooks[name] or {}
  table.insert(self._hooks[name], fn)
end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:GetFrameStrata() return self._strata or "MEDIUM" end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel() return self._level or 1 end
function Frame:SetScale(s)
  assert(type(s) == "number" and s > 0, "SetScale needs a positive number")
  self._scale = s
end
function Frame:GetScale() return self._scale or 1 end
function Frame:GetEffectiveScale()
  local parent = self._parent
  local base = parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or (W.uiScale or 1)
  if self == UIParent then base = W.uiScale or 1 end
  return base * (self._scale or 1)
end
function Frame:IsMouseEnabled() return self._mouse or false end
function Frame:EnableMouse(v) self._mouse = v and true or false end
function Frame:IsMouseOver()
  local l, b, w, h = self:GetRect()
  if not l then return false end
  local x, y = W.cursorX or -1, W.cursorY or -1
  return x >= l and x <= l + w and y >= b and y <= b + h
end
function Frame:SetClipsChildren(v) self._clips = v and true or false end
function Frame:DoesClipChildren() return self._clips or false end
function Frame:GetRegions()
  local out = {}
  for _, r in ipairs(self._regions or {}) do out[#out + 1] = r end
  return unpack(out)
end
function Frame:GetChildren()
  local out = {}
  for _, f in ipairs(W.frames) do
    if f._parent == self then out[#out + 1] = f end
  end
  return unpack(out)
end
function Frame:_fire(name, ...)
  local fn = self._scripts[name]
  if fn then fn(self, ...) end
  if self._hooks[name] then
    for _, h in ipairs(self._hooks[name]) do h(self, ...) end
  end
end
function Frame:_fireSize() self:_fire("OnSizeChanged", self._w, self._h) end
setters(Frame, [[EnableMouseWheel SetMovable SetResizable SetClampedToScreen
  SetToplevel RegisterForDrag StartMoving StopMovingOrSizing StartSizing SetResizeBounds
  EnableKeyboard]])
function Frame:SetPropagateKeyboardInput(v)
  assert(not W.combat, "SetPropagateKeyboardInput is protected in combat")
  self._propagate = v
end

-- Button
inherit(Button, Frame)
function Button:Enable() self._enabled = true end
function Button:Disable() self._enabled = false end
function Button:IsEnabled() return self._enabled ~= false end
-- Test helper: a real click, honouring the disabled state like the client.
function Button:_click(mouseButton)
  if self._enabled == false then return end
  self:_fire("OnClick", mouseButton or "LeftButton")
end
setters(Button, "RegisterForClicks SetMotionScriptsWhileDisabled")

-- Textures
inherit(Texture, Region)
function Texture:SetTexture(t) self._texture = t end
function Texture:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Texture:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
function Texture:GetVertexColor()
  local v = self._vertex or { 1, 1, 1, 1 }
  return v[1], v[2], v[3], v[4]
end
function Texture:GetTexture() return self._texture end
function Texture:GetTextureFilePath() return self._texture end
function Texture:GetAtlas() return nil end
function Texture:SetTextureSliceMargins(l, t, r, b) self._slice = { l, t, r, b } end
function Texture:GetTextureSliceMargins()
  local m = self._slice or { 0, 0, 0, 0 }
  return m[1], m[2], m[3], m[4]
end
setters(Texture, "SetTextureSliceMode AddMaskTexture RemoveMaskTexture")
function Texture:SetTexCoord(...)
  local n = select("#", ...)
  local a = { ... }
  if n == 4 then -- left, right, top, bottom
    self._uv = { a[1], a[3], a[1], a[4], a[2], a[3], a[2], a[4] }
  else
    self._uv = a
  end
end
function Texture:GetTexCoord()
  local u = self._uv or { 0, 0, 0, 1, 1, 0, 1, 1 }
  return u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8]
end
function Texture:SetBlendMode(m) self._blend = m end
function Texture:GetBlendMode() return self._blend or "BLEND" end
-- Client files: everything exists unless listed in W.missingFiles.
function Texture:GetTextureFileID()
  local t = self._texture
  if t == nil then return nil end
  if type(t) == "number" then return t end
  if W.missingFiles and W.missingFiles[t] then return nil end
  return 1000 + #t
end

inherit(Line, Region)
Line.SetColorTexture = Texture.SetColorTexture
Line.GetVertexColor = Texture.GetVertexColor
function Line:GetThickness() return 1 end
setters(Line, "SetThickness SetStartPoint SetEndPoint")

inherit(Mask, Region)
Mask.SetTexture = Texture.SetTexture
Mask.GetTexture = Texture.GetTexture
Mask.GetVertexColor = Texture.GetVertexColor

-- Fonts
function Font:SetFont(path, size, flags)
  assert(type(path) == "string" and type(size) == "number", "bad SetFont")
  self._path, self._size, self._flags = path, size, flags
  return true
end
function Font:GetFont() return self._path, self._size, self._flags end
setters(Font, "SetShadowOffset SetShadowColor")

inherit(FontString, Region)
function FontString:SetFontObject(f)
  assert(type(f) == "table" and f._isFont, "SetFontObject needs a font object")
  self._font = f
end
function FontString:GetFont()
  local f = self._font
  if not f then return nil, 12 end
  return f._path, f._size, f._flags
end
function FontString:SetText(t)
  if not self._font then error("FontString:SetText(): Font not set", 2) end
  self._text = t == nil and "" or tostring(t)
end
function FontString:GetText() return self._text end
function FontString:GetUnboundedStringWidth()
  local _, size = self:GetFont()
  return utf8len(stripCodes(self._text or "")) * size * 0.55
end
FontString.GetStringWidth = FontString.GetUnboundedStringWidth
function FontString:GetLineHeight()
  local _, size = self:GetFont()
  return size * 1.2
end
-- Lines the text needs at the current width, and lines the current height
-- allows (the client reports a wrapped height only within the set height).
function FontString:_lines()
  local need = 1
  if self._wrap and self._w and self._w > 0 then
    need = math.max(1, math.ceil(self:GetUnboundedStringWidth() / self._w))
  end
  local allow = need
  if self._h and self._h > 0 then
    allow = math.max(1, math.floor(self._h / self:GetLineHeight() + 0.01))
  end
  return need, allow
end
function FontString:GetStringHeight()
  if self._text == "" then return 0 end
  local need, allow = self:_lines()
  return math.min(need, allow) * self:GetLineHeight()
end
function FontString:SetWordWrap(v) self._wrap = v end
function FontString:CanWordWrap() return self._wrap and true or false end
function FontString:GetTextColor()
  local c = self._color or { 1, 1, 1, 1 }
  return c[1], c[2], c[3], c[4]
end
function FontString:IsTruncated()
  if self._wrap then
    local need, allow = self:_lines()
    return need > allow
  end
  return (self._w or 0) > 0 and self:GetUnboundedStringWidth() > self._w + 0.5
end
function FontString:GetJustifyH() return "LEFT" end
function FontString:SetTextColor(r, g, b, a)
  assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetTextColor needs numbers")
  self._color = { r, g, b, a }
end
setters(FontString, "SetJustifyH SetJustifyV SetMaxLines")

for _, class in ipairs(ALL) do
  for k in pairs(class) do
    if type(k) == "string" and k:match("^[A-Z]") then universe[k] = true end
  end
end

function W.new(class, fields)
  local obj = fields or {}
  obj._scripts, obj._hooks, obj._events = obj._scripts or {}, obj._hooks or {}, obj._events or {}
  return setmetatable(obj, {
    __index = function(_, k)
      local v = class[k]
      if v == nil and type(k) == "string" and k:match("^[A-Z]") and not universe[k] then
        error("stub: unknown client API method " .. k, 2)
      end
      return v
    end,
  })
end

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------

function CreateFrame(kind, name, parent)
  count(kind)
  local class = (kind == "Button") and Button or Frame
  assert(kind == "Frame" or kind == "Button", "stub: unsupported frame type " .. tostring(kind))
  local f = W.new(class, { _parent = parent, _kind = kind, _type = kind })
  W.frames[#W.frames + 1] = f
  if name then _G[name] = f end
  return f
end

UIParent = CreateFrame("Frame")
UIParent:SetSize(1920, 1080)
W.created = {}

function CreateFont(name)
  local f = W.new(Font, { _isFont = true })
  _G[name] = f
  return f
end

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
for _, name in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall" }) do
  CreateFont(name):SetFont(STANDARD_TEXT_FONT, 12, "")
end

function debugstack()
  return "[Interface/AddOns/" .. (W.loadingAddon or "FxUI") .. "/Core.lua]:1: in main chunk"
end

function geterrorhandler()
  return function(err)
    W.errors[#W.errors + 1] = tostring(err)
  end
end

W.combat = false
function InCombatLockdown() return W.combat end

C_Timer = {
  After = function(seconds, fn)
    W.timers[#W.timers + 1] = { at = W.now + seconds, fn = fn }
  end,
}

function GetCursorPosition() return W.cursorX or 0, W.cursorY or 0 end
function IsModifiedClick() return false end
function IsShiftKeyDown() return W.shift or false end
function IsLoggedIn() return W.loggedIn or false end

-- Backdrops: the mixin records what it was given.
function Mixin(obj, ...)
  for i = 1, select("#", ...) do
    for k, v in pairs((select(i, ...))) do rawset(obj, k, v) end
  end
  return obj
end
BackdropTemplateMixin = {
  SetBackdrop = function(self, def) self._backdrop = def end,
  ClearBackdrop = function(self) self._backdrop = nil end,
  SetBackdropColor = function(self, r, g, b, a) self._backdropColor = { r, g, b, a } end,
  SetBackdropBorderColor = function(self, r, g, b, a) self._backdropBorder = { r, g, b, a } end,
  OnBackdropSizeChanged = function() end,
}
function ChatEdit_InsertLink() return true end

Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }

GameTooltip = W.new(Frame, {})
function GameTooltip:SetOwner(owner) self._owner = owner end
function GameTooltip:IsOwned(f) return self._owner == f end
function GameTooltip:Hide() self._owner = nil end
function GameTooltip:Show() end
function GameTooltip:SetText() end
function GameTooltip:SetHyperlink() end
function GameTooltip:SetItemByID() end
function GameTooltip:AddLine() end
function GameTooltip:AddDoubleLine() end

local pending = {}

C_Item = {
  GetItemIconByID = function(id) return 100000 + id end,
  GetItemInfo = function(item)
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
    if not W.items[id] then return nil end
    return "Item " .. id, "|cffffffff|Hitem:" .. id .. "::|h[Item " .. id .. "]|h|r", id % 6, 10
  end,
  GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end,
  GetDetailedItemLevelInfo = function() return 10 end,
}

Item = {}
function Item:CreateFromItemID(id)
  return {
    IsItemEmpty = function() return false end,
    ContinueOnItemLoad = function(_, fn)
      pending[#pending + 1] = { id = id, fn = fn }
    end,
  }
end

SlashCmdList = {}
-- Settings panel: records what addons register.
W.settings = { categories = {}, settings = {}, initializers = {} }
Settings = { VarType = { Boolean = "boolean", Number = "number", String = "string" } }
function Settings.RegisterVerticalLayoutCategory(name)
  local category = { name = name, id = #W.settings.categories + 1 }
  function category:GetID() return self.id end
  local layout = {}
  function layout:AddInitializer(init) table.insert(W.settings.initializers, init) end
  table.insert(W.settings.categories, category)
  return category, layout
end
function Settings.RegisterAddOnSetting(category, variable, key, tbl, varType, name, default)
  assert(type(variable) == "string" and type(key) == "string" and type(tbl) == "table", "RegisterAddOnSetting arguments")
  assert(varType == type(default), "RegisterAddOnSetting type")
  if tbl[key] == nil then tbl[key] = default end
  local setting = { variable = variable, name = name, category = category }
  function setting:GetValue() return tbl[key] end
  function setting:SetValue(v)
    tbl[key] = v
    if self.cb then self.cb(self, v) end
  end
  function setting:SetValueChangedCallback(cb) self.cb = cb end
  W.settings.settings[variable] = setting
  return setting
end
function Settings.CreateCheckbox(category, setting, tooltip) setting.checkbox = true end
function Settings.CreateSliderOptions(min, max, step)
  local o = { min = min, max = max, step = step }
  function o:SetLabelFormatter(where, fn) self.formatter = fn end
  return o
end
function Settings.CreateSlider(category, setting, options, tooltip) setting.slider = options end
function Settings.CreateControlTextContainer()
  local c = { data = {} }
  function c:Add(value, label) table.insert(self.data, { value = value, label = label }) end
  function c:GetData() return self.data end
  return c
end
function Settings.CreateDropdown(category, setting, options, tooltip) setting.dropdown = options end
MinimalSliderWithSteppersMixin = { Label = { Right = 3 } }
function Settings.RegisterAddOnCategory(category) category.registered = true end
function Settings.OpenToCategory(id) W.settings.opened = id end
function CreateSettingsButtonInitializer(name, text, onClick, tooltip, search)
  return { name = name, text = text, onClick = onClick }
end

function GetBuildInfo() return "12.1.5", "70529", "Oct 2026", 120105 end
function GetPhysicalScreenSize() return 3840, 2160 end
function GetMouseFoci() return W.mouseFoci or {} end
function ReloadUI() W.reloads = (W.reloads or 0) + 1 end
-- The client's string.format stores integer conversions in 32 bits:
-- %d of 2^31 or more raises "integer overflow attempting to store".
do
  local format = string.format
  local function clientFormat(fmt, ...)
    local i = 0
    for conv in tostring(fmt):gmatch("%%[-+ #0]*%d*%.?%d*([%a%%])") do
      if conv ~= "%" then
        i = i + 1
        local v = select(i, ...)
        if (conv == "d" or conv == "i" or conv == "u" or conv == "x" or conv == "X" or conv == "o" or conv == "c")
          and type(v) == "number" and (v >= 2147483648 or v < -2147483648) then
          error("integer overflow attempting to store " .. format("%.0f", v), 2)
        end
      end
    end
    return format(fmt, ...)
  end
  string.format = clientFormat
end

time = os.time
date = os.date
strmatch = string.match

---------------------------------------------------------------------------
-- Test helpers
---------------------------------------------------------------------------

function W.loadItems()
  local list = pending
  pending = {}
  for _, p in ipairs(list) do W.items[p.id] = true end
  for _, p in ipairs(list) do p.fn() end
end

function W.fireEvent(event, ...)
  for _, f in ipairs(W.frames) do
    if f._events[event] then f:_fire("OnEvent", event, ...) end
  end
end

function W.nextFrame(elapsed)
  for _, f in ipairs(W.frames) do
    local fn = f._scripts.OnUpdate
    if fn then fn(f, elapsed or 0.016) end
  end
end

function W.advance(seconds)
  W.now = W.now + seconds
  local due, rest = {}, {}
  for _, t in ipairs(W.timers) do
    if t.at <= W.now then due[#due + 1] = t else rest[#rest + 1] = t end
  end
  W.timers = rest
  for _, t in ipairs(due) do t.fn() end
end

function W.loadAddon(dir, name)
  local ns = {}
  W.loadingAddon = name
  for line in io.lines(dir .. "/" .. name .. ".toc") do
    if not line:match("^%s*$") and not line:match("^##") then
      local path = dir .. "/" .. line:gsub("\\", "/")
      local chunk = assert(loadfile(path))
      chunk(name, ns)
    end
  end
  W.loadingAddon = nil
  W.fireEvent("ADDON_LOADED", name)
  return ns
end

-- Write globals the way the client writes a SavedVariables file.
local function serialize(v, indent, out)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "table" then
    out[#out + 1] = "{\n"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      out[#out + 1] = indent .. "\t["
      serialize(k, "", out)
      out[#out + 1] = "] = "
      serialize(v[k], indent .. "\t", out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  else
    out[#out + 1] = "nil"
  end
end

function W.writeSavedVariables(path, names)
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = "\n" .. name .. " = "
    serialize(_G[name], "", out)
    out[#out + 1] = "\n"
  end
  local f = assert(io.open(path, "w"))
  f:write(table.concat(out))
  f:close()
end

return W
