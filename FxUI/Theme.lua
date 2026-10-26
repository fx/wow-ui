local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local function parseHex(hex)
  local r, g, b, a = hex:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
  assert(r, "FxUI: bad color " .. tostring(hex))
  return {
    r = tonumber(r, 16) / 255,
    g = tonumber(g, 16) / 255,
    b = tonumber(b, 16) / 255,
    a = a ~= "" and tonumber(a, 16) / 255 or 1,
    hex = hex:sub(1, 7):upper(),
  }
end
I.parseHex = parseHex

UI.QUALITY_TOKENS = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }

---------------------------------------------------------------------------
-- Theme definitions
---------------------------------------------------------------------------

-- A theme definition:
--   name, title         registry key and display name
--   base                theme it inherits from (default "default"; false for none)
--   colors              token -> "#RRGGBB" or "#RRGGBBAA"
--   fonts               token -> { file = "<FxUI media font>" | path = "<client path>",
--                                  size, flags, caps, shadow = true }
--   surfaces            role -> { bg, border, radius } or { backdrop = {...},
--                                  bgColor, borderColor } (UI.HStack/VStack surface = role)
--   money               "letters" (12g 34s) or "icons" (coin textures)
--   metrics             component -> table of numbers (heights, paddings, ...)
--   skins               component -> functions that draw it (see Skins below)
-- Everything not given is inherited.
UI.themes = UI.themes or {}


-- Resolved themes: registered names in I.resolved, unregistered definition
-- tables in I.resolvedTables. Loading a newer copy drops the named cache,
-- since its definitions and flattening may differ.
I.resolved = I.wipe(I.resolved or {})
I.resolvedTables = I.resolvedTables or setmetatable({}, { __mode = "k" })
I.nextThemeId = I.nextThemeId or 0

local function safeId(name)
  return (tostring(name):gsub("[^%w]", "_"))
end

local function applyFont(obj, spec)
  local path = spec.path or (I.media .. "Fonts\\" .. spec.file)
  local ok = obj:SetFont(path, spec.size, spec.flags or "")
  if ok == false then obj:SetFont(STANDARD_TEXT_FONT, spec.size, spec.flags or "") end
  if spec.shadow then
    obj:SetShadowOffset(1, -1)
    obj:SetShadowColor(0, 0, 0, 1)
  else
    obj:SetShadowOffset(0, 0)
  end
end

local function mergeTables(base, own)
  local out = {}
  for k, v in pairs(base or {}) do out[k] = v end
  for k, v in pairs(own or {}) do out[k] = v end
  return out
end

-- Flatten a definition with everything it inherits into a resolved theme:
-- color tokens as color tables at the top level (theme.gold), plus fonts
-- (font objects), fontSpecs, surfaces, skins, metrics, money, space, radius.
local function flatten(def, id)
  local base
  if def.base ~= false and def.name ~= "default" then
    base = I.resolve(def.base or "default")
  end
  local t = { name = def.name or id, title = def.title or def.name or id, def = def, id = id }

  if base then
    for k, v in pairs(base) do
      if type(v) == "table" and v.r and v.hex then t[k] = v end
    end
  end
  for token, hex in pairs(def.colors or {}) do t[token] = parseHex(hex) end

  t.fontSpecs = mergeTables(base and base.fontSpecs, def.fonts)
  t.fonts = {}
  for token, spec in pairs(t.fontSpecs) do
    local fontName = "FxUIFont_" .. safeId(id) .. "_" .. token
    local obj = _G[fontName] or CreateFont(fontName)
    applyFont(obj, spec)
    t.fonts[token] = obj
  end

  t.surfaces = mergeTables(base and base.surfaces, def.surfaces)
  t.money = def.money or (base and base.money) or "letters"
  t.space = def.space or (base and base.space)
  t.radius = def.radius or (base and base.radius)

  -- Metrics and skins merge per component, so a theme can override one
  -- entry or one drawing function and inherit the rest.
  t.metrics, t.skins = {}, {}
  for _, field in ipairs({ "metrics", "skins" }) do
    local merged = t[field]
    for comp, v in pairs(base and base[field] or {}) do merged[comp] = v end
    for comp, v in pairs(def[field] or {}) do
      merged[comp] = mergeTables(merged[comp], v)
    end
  end
  return t
end

-- Resolve a theme reference (a registered name or a definition table) to a
-- resolved theme. Unknown names fall back to the global theme.
function I.resolve(ref)
  if ref == nil then return I.global end
  if type(ref) == "table" then
    if ref.fonts and ref.fontSpecs then return ref end -- already resolved
    local t = I.resolvedTables[ref]
    if not t then
      I.nextThemeId = I.nextThemeId + 1
      t = flatten(ref, "custom" .. I.nextThemeId)
      I.resolvedTables[ref] = t
    end
    return t
  end
  local t = I.resolved[ref]
  if t then return t end
  local def = UI.themes[ref]
  if not def then
    if not (I.missingThemes and I.missingThemes[ref]) then
      I.missingThemes = I.missingThemes or {}
      I.missingThemes[ref] = true
      I.report("FxUI: unknown theme '" .. tostring(ref) .. "', using the global theme")
    end
    return I.global or I.resolve("default")
  end
  t = flatten(def, ref)
  I.resolved[ref] = t
  return t
end

-- Register a theme. UI.registerTheme(def) with def.name, or the older
-- UI.registerTheme(name, base, { colors, fonts, ... }).
function UI.registerTheme(name, base, overrides)
  local def = name
  if type(name) == "string" then
    def = overrides or {}
    def.name = name
    def.base = def.base == nil and (base or "default") or def.base
  end
  assert(type(def) == "table" and type(def.name) == "string", "FxUI: a theme needs a name")
  UI.themes[def.name] = def
  -- Re-resolve this theme and everything inheriting from it.
  I.wipe(I.resolved)
  if I.global then
    I.global = I.resolve(UI.themeName or "default")
    UI.theme = I.global
  end
  if I.onThemesChanged then I.onThemesChanged() end
  return def
end

-- Registered themes, sorted by title: { { name, title }, ... }
function UI.listThemes()
  local out = {}
  for name, def in pairs(UI.themes) do
    out[#out + 1] = { name = name, title = def.title or name }
  end
  table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
  return out
end

---------------------------------------------------------------------------
-- Global and active theme
---------------------------------------------------------------------------

-- The global theme applies wherever no element sets one. While a subtree
-- with its own theme renders, lays out or handles an event, I.activeTheme points
-- at that theme; everything resolves colors and fonts through I.theme().
function I.theme()
  return I.activeTheme or I.global
end

-- Make a node's theme active (nil node or theme: the global one); returns
-- the previous active theme for I.leave.
function I.enter(node)
  local prev = I.activeTheme
  I.activeTheme = node and node.theme or nil
  return prev
end

function I.leave(prev)
  I.activeTheme = prev
end

function UI.setTheme(name)
  assert(UI.themes[name], "FxUI: unknown theme " .. tostring(name))
  UI.themeName = name
  I.global = I.resolve(name)
  UI.theme = I.global
  if I.db then I.db.theme = name end
  if I.rerenderAll then I.rerenderAll() end
end

-- Resolve a color: a token name, "#RRGGBB", or a color table. Returns r, g, b, a.
function I.rgba(spec, alpha)
  local c = spec
  if type(spec) == "string" then
    c = I.theme()[spec]
    if not c or not c.hex then
      if spec:sub(1, 1) == "#" then
        c = parseHex(spec)
      else
        error("FxUI: unknown color token " .. spec, 3)
      end
    end
  end
  return c.r, c.g, c.b, alpha or c.a or 1
end

function I.colorTable(spec, alpha)
  local r, g, b, a = I.rgba(spec, alpha)
  return { r = r, g = g, b = b, a = a }
end

-- Mix color a toward color b by t (0..1).
function I.mix(a, b, t)
  local ar, ag, ab = I.rgba(a)
  local br, bg, bb = I.rgba(b)
  return { r = ar + (br - ar) * t, g = ag + (bg - ag) * t, b = ab + (bb - ab) * t, a = 1 }
end

function I.hexOf(spec)
  local r, g, b = I.rgba(spec)
  return string.format("%02X%02X%02X", I.round(r * 255), I.round(g * 255), I.round(b * 255))
end

-- WCAG contrast ratio between two colors.
local function luminance(spec)
  local r, g, b = I.rgba(spec)
  local function ch(x)
    if x <= 0.03928 then return x / 12.92 end
    return ((x + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end

function UI.contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end

function UI.font(token)
  local f = I.theme().fonts[token] or I.global.fonts[token]
  if not f then error("FxUI: unknown font token " .. tostring(token), 2) end
  return f
end

function UI.fontSpec(token)
  return I.theme().fontSpecs[token] or I.global.fontSpecs[token]
end

-- The active theme's skin for a component, or nil for FxUI's own drawing.
function I.skin(component)
  local s = I.theme().skins[component]
  if s and next(s) then return s end
end

function I.metrics(component)
  return I.theme().metrics[component] or {}
end

-- Color for an item quality index; falls back to the client's table for
-- qualities without a token (artifact, heirloom, ...).
function UI.qualityColor(quality)
  local token = UI.QUALITY_TOKENS[quality or 1]
  if token then return I.theme()[token] end
  if C_Item and C_Item.GetItemQualityColor then
    local r, g, b = C_Item.GetItemQualityColor(quality)
    if r then return { r = r, g = g, b = b, a = 1 } end
  end
  return I.theme().common
end

I.global = I.resolve(UI.themeName or "default")
UI.theme = I.global
UI.themeName = UI.themeName or "default"
