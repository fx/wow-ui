local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local WHITE, BLACK = "#FFFFFF", "#000000"

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local TOOLTIP_MAX_W, TOOLTIP_GAP = 260, 6

local TooltipView = I.defineComponent("FxTooltip", function(props)
  local body = { gap = 4, padding = { 8, 10 }, surface = "tooltip", maxWidth = props.maxWidth or TOOLTIP_MAX_W }
  local titled = props.title ~= nil and props.title ~= ""
  if titled then
    body[#body + 1] = UI.Text { text = props.title, style = "strong", wrap = true }
  end
  if props.text and props.text ~= "" then
    body[#body + 1] = UI.Text { text = props.text, color = titled and "muted" or "text", wrap = true }
  end
  return UI.VStack(body)
end)

-- One tooltip for every copy of the library: an upgrade keeps it.
I.tooltip = I.tooltip or {}
local TT = I.tooltip

-- Show FxUI's tooltip for `owner`: `spec` is text, or { title, text,
-- maxWidth }. It sits above the owner, or below when there is no room
-- above, sized to its content, in the `tooltip` surface of the owner's
-- theme (the theme of the FxUI element the owner is, else the global one).
function UI.showTooltip(owner, spec)
  if type(spec) ~= "table" then spec = { text = spec } end
  if (not spec.title or spec.title == "") and (not spec.text or spec.text == "") then return end
  local node = owner and owner.fxNode
  local el = TooltipView({ title = spec.title, text = spec.text, maxWidth = spec.maxWidth,
    theme = node and node.alive and node.theme or nil })
  if not TT.host then
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("TOOLTIP")
    host:SetClampedToScreen(true)
    I.followScale(host, false)
    TT.host = host
    TT.root = UI.mount(host, el)
  else
    TT.root:update(el)
  end
  local host = TT.host
  local w, h = I.measure(TT.root.node, spec.maxWidth or TOOLTIP_MAX_W, 2000)
  host:SetSize(w, h)
  TT.root:layout()
  host:ClearAllPoints()
  -- Below the owner when the tooltip would not fit above it.
  local top = owner:GetTop()
  local room = top and UIParent:GetTop() and (UIParent:GetTop() * UIParent:GetEffectiveScale() - top * owner:GetEffectiveScale())
  if room and room < (h + TOOLTIP_GAP) * host:GetEffectiveScale() then
    host:SetPoint("TOP", owner, "BOTTOM", 0, -TOOLTIP_GAP)
  else
    host:SetPoint("BOTTOM", owner, "TOP", 0, TOOLTIP_GAP)
  end
  host:Show()
  TT.owner = owner
end

-- Hide the tooltip when `owner` shows it (any owner when nil).
function UI.hideTooltip(owner)
  if TT.host and (owner == nil or TT.owner == owner) then
    TT.host:Hide()
    TT.owner = nil
  end
end

-- The frame the tooltip is shown for, or nil while it is hidden.
function UI.tooltipOwner()
  return TT.host and TT.host:IsShown() and TT.owner or nil
end

local function showTooltip(frame, text) UI.showTooltip(frame, text) end
local function hideTooltip(frame) UI.hideTooltip(frame) end

---------------------------------------------------------------------------
-- Help: a small "?" that explains something in a tooltip
---------------------------------------------------------------------------

local HELP_SIZE = 14

-- Skin contract: skins.Help.paint(frame, props, state) with state =
-- { hover }; frame.circle and .mark exist. metrics.Help.size (14).
local function paintHelp(f)
  local node = f.fxNode
  if not node then return end
  local prevTheme = I.enter(node)
  local skin = I.skin("Help")
  if skin and skin.paint then
    skin.paint(f, node.el.props, { hover = f.fxHover })
  else
    I.clearSkin(f)
    f.circle:Show()
    f.mark:Show()
    f.circle:SetVertexColor(I.rgba(f.fxHover and "muted" or "line"))
    f.mark:SetTextColor(I.rgba(f.fxHover and "text" or "muted"))
  end
  I.leave(prevTheme)
end

-- Props: text, title, maxWidth (the tooltip's); size.
I.defineHost("Help", {
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f:EnableMouse(true)
    f.circle = f:CreateTexture(nil, "ARTWORK")
    f.circle:SetAllPoints()
    I.setFile(f.circle, "Circle.tga")
    f.mark = f:CreateFontString(nil, "OVERLAY")
    f.mark:SetPoint("CENTER", 0, 0)
    f:SetScript("OnEnter", function(self)
      self.fxHover = true
      paintHelp(self)
      local node = self.fxNode
      if node then
        local p = node.el.props
        UI.showTooltip(self, { title = p.title, text = p.text, maxWidth = p.maxWidth })
      end
    end)
    f:SetScript("OnLeave", function(self)
      self.fxHover = false
      paintHelp(self)
      UI.hideTooltip(self)
    end)
    return f
  end,
  update = function(node)
    I.setText(node.region.mark, "?", "label", "muted")
    paintHelp(node.region)
  end,
  measure = function(node)
    local s = node.el.props.size or I.metrics("Help").size or HELP_SIZE
    return s, s
  end,
  release = function(node)
    node.region.fxHover = false
    UI.hideTooltip(node.region)
  end,
})

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------

local SIZES = {
  sm = { height = 24, pad = 10, radius = "r4" },
  md = { height = 30, pad = 14, radius = "r4" },
  lg = { height = 40, pad = 20, radius = "r8" },
}

-- bg, border, text for a variant in a state.
local function buttonColors(variant, hover, pressed, enabled)
  if not enabled then
    return "panel", "line", I.mix("muted", "panel", 0.35)
  end
  if variant == "primary" then
    local bg = "gold"
    if pressed then bg = I.mix("gold", BLACK, 0.12) elseif hover then bg = I.mix("gold", WHITE, 0.14) end
    return bg, nil, "onGold"
  elseif variant == "danger" then
    local bg = I.mix("panel", "down", hover and 0.22 or 0.12)
    if pressed then bg = I.mix("panel", "down", 0.3) end
    return bg, I.mix("panel", "down", 0.45), I.mix("down", WHITE, 0.25)
  elseif variant == "ghost" then
    local bg = (hover or pressed) and "raised" or nil
    return bg, nil, (hover or pressed) and "text" or "muted"
  end
  local bg = "raised"
  if pressed then bg = I.mix("raised", BLACK, 0.15) elseif hover then bg = I.mix("raised", WHITE, 0.06) end
  return bg, I.mix("line", WHITE, 0.08), "text"
end

local function buttonEnabled(p)
  return not p.disabled and not p.busy and not (p.secure and I.inCombat)
end

local function buttonSize(p)
  local sizes = I.metrics("Button").sizes or SIZES
  return sizes[p.size or "md"] or sizes.md or SIZES.md
end

-- Skin contract: skins.Button.paint(button, props, state) with
-- state = { hover, pressed, enabled, size }; button.label is the text.
-- metrics.Button.sizes = { sm/md/lg = { height, pad, radius } }, .font.
local function paintButton(b)
  local node = b.fxNode
  if not node then return end
  local prevTheme = I.enter(node)
  local p = node.el.props
  local enabled = buttonEnabled(p)
  local size = buttonSize(p)
  local pressed = b.fxPressed and enabled
  local skin = I.skin("Button")
  b.label:ClearAllPoints()
  if skin and skin.paint then
    I.clearSurface(b)
    skin.paint(b, p, { hover = b.fxHover, pressed = pressed, enabled = enabled, size = size })
  else
    I.clearSkin(b)
    local bg, border, text = buttonColors(p.variant or "secondary", b.fxHover, pressed, enabled)
    I.applySurface(b, bg, border, p.radius or size.radius)
    b.label:SetTextColor(I.rgba(text))
    b.label:SetPoint("CENTER", 0, pressed and -1 or 0)
  end
  if enabled then b:Enable() else b:Disable() end
  I.leave(prevTheme)
end
I.paintButton = paintButton

I.secureButtons = I.secureButtons or setmetatable({}, { __mode = "k" })
I.combatListeners[function()
  for node in pairs(I.secureButtons) do
    if node.alive and node.region then paintButton(node.region) end
  end
end] = true

-- Props: text, variant (primary|secondary|danger|ghost), size (sm|md|lg),
-- onClick(frame, mouseButton), disabled, busy (true or replacement text),
-- secure (the handler may make a protected call; disabled in combat),
-- tooltip.
I.defineHost("Button", {
  create = function(holder)
    local b = CreateFrame("Button", nil, holder)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetMotionScriptsWhileDisabled(true)
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetPoint("CENTER")
    b.label:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
      self.fxHover = true
      paintButton(self)
      local node = self.fxNode
      if node then showTooltip(self, node.el.props.tooltip) end
    end)
    b:SetScript("OnLeave", function(self)
      self.fxHover = false
      self.fxPressed = false
      paintButton(self)
      hideTooltip(self)
    end)
    b:SetScript("OnMouseDown", function(self)
      self.fxPressed = true
      paintButton(self)
    end)
    b:SetScript("OnMouseUp", function(self)
      self.fxPressed = false
      paintButton(self)
    end)
    -- The handler runs synchronously inside the real click, so a protected
    -- call made from it keeps the hardware event.
    b:SetScript("OnClick", function(self, mouseButton)
      local node = self.fxNode
      if not node then return end
      local p = node.el.props
      if not buttonEnabled(p) then return end
      if p.onClick then p.onClick(self, mouseButton) end
    end)
    return b
  end,
  update = function(node, p)
    local b = node.region
    local text = p.text
    if p.busy and type(p.busy) == "string" then text = p.busy end
    I.setText(b.label, text, p.font or I.metrics("Button").font or "strong")
    if p.secure then I.secureButtons[node] = true else I.secureButtons[node] = nil end
    paintButton(b)
  end,
  measure = function(node)
    local size = buttonSize(node.el.props)
    local w = I.measureString(node.region.label)
    return w + size.pad * 2, size.height
  end,
  release = function(node)
    I.secureButtons[node] = nil
    local b = node.region
    b.fxHover, b.fxPressed = false, false
    hideTooltip(b)
  end,
})

---------------------------------------------------------------------------
-- Pressable
---------------------------------------------------------------------------

-- Hover and press shade the area in the theme's raised role (a skin's
-- paint replaces that); disabled, it is drawn as is.
local function paintPressable(f)
  local node = f.fxNode
  if not node then return end
  local prevTheme = I.enter(node)
  local p = node.el.props
  local enabled = not p.disabled
  local skin = I.skin("Pressable")
  if skin and skin.paint then
    skin.paint(f, p, { hover = f.fxHover and enabled, pressed = f.fxPressed and enabled, enabled = enabled })
  elseif enabled and (f.fxHover or f.fxPressed) then
    I.applySurface(f, f.fxPressed and I.mix("raised", BLACK, 0.15) or "raised", nil, p.radius or "r4")
  else
    I.clearSurface(f)
  end
  I.leave(prevTheme)
end

-- Any content as a click target: its children are laid out as a VStack
-- (gap, padding, align, justify), or an HStack with horizontal = true.
-- Props: onClick(frame, mouseButton), disabled, tooltip, radius.
I.defineHost("Pressable", {
  container = true,
  create = function(holder)
    local f = CreateFrame("Button", nil, holder)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetMotionScriptsWhileDisabled(true)
    f:SetScript("OnEnter", function(self)
      self.fxHover = true
      paintPressable(self)
      local node = self.fxNode
      if node then showTooltip(self, node.el.props.tooltip) end
    end)
    f:SetScript("OnLeave", function(self)
      self.fxHover, self.fxPressed = false, false
      paintPressable(self)
      hideTooltip(self)
    end)
    f:SetScript("OnMouseDown", function(self)
      self.fxPressed = true
      paintPressable(self)
    end)
    f:SetScript("OnMouseUp", function(self)
      self.fxPressed = false
      paintPressable(self)
    end)
    f:SetScript("OnClick", function(self, mouseButton)
      local node = self.fxNode
      if not node then return end
      local p = node.el.props
      if not p.disabled and p.onClick then p.onClick(self, mouseButton) end
    end)
    return f
  end,
  update = function(node, p)
    if p.disabled then node.region:Disable() else node.region:Enable() end
    paintPressable(node.region)
  end,
  measure = function(node, maxW, maxH)
    return I.stackMeasure(node.children, node.el.props, node.el.props.horizontal, maxW, maxH)
  end,
  layout = function(node, w, h)
    I.stackLayout(node.children, node.el.props, node.el.props.horizontal, w, h)
  end,
  release = function(node)
    local f = node.region
    f.fxHover, f.fxPressed = false, false
    I.clearSurface(f)
    hideTooltip(f)
  end,
})

---------------------------------------------------------------------------
-- Badge
---------------------------------------------------------------------------

local TONES = {
  neutral = "muted",
  gold = "gold",
  info = "info",
  up = "up",
  down = "down",
  warn = "warn",
}

-- Props: text, tone (neutral|gold|info|up|down|warn), solid.
I.defineHost("Badge", {
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetPoint("CENTER", 0, 0)
    f.label:SetWordWrap(false)
    return f
  end,
  -- Skin contract: skins.Badge.paint(frame, props, toneToken) styles
  -- frame and frame.label (text already set). metrics.Badge = { height, pad }.
  update = function(node, p)
    local f = node.region
    local base = TONES[p.tone or "neutral"] or p.tone
    local skin = I.skin("Badge")
    if skin and skin.paint then
      I.clearSurface(f)
      I.setText(f.label, p.text, "label")
      skin.paint(f, p, base)
    elseif p.solid then
      I.clearSkin(f)
      I.applySurface(f, base, nil, "pill")
      I.setText(f.label, p.text, "label", base == "gold" and "onGold" or "ground")
    else
      I.clearSkin(f)
      I.applySurface(f, I.mix("panel", base, 0.16), nil, "pill")
      I.setText(f.label, p.text, "label", I.mix(base, WHITE, 0.25))
    end
  end,
  measure = function(node)
    local m = I.metrics("Badge")
    return I.measureString(node.region.label) + (m.pad or 7) * 2, m.height or 18
  end,
})

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------

local TRACK_W, TRACK_H, KNOB = 30, 16, 12

-- Skin contract: skins.Toggle.paint(button, props, state) with state =
-- { hover, checked, enabled }; button.track, .knob, .label exist (hide what
-- the skin does not use). metrics.Toggle = { width, height, gap }.
local function paintToggle(b)
  local node = b.fxNode
  if not node then return end
  local prevTheme = I.enter(node)
  local p = node.el.props
  local on = p.checked and true or false
  local skin = I.skin("Toggle")
  local m = I.metrics("Toggle")
  b.label:ClearAllPoints()
  if skin and skin.paint then
    skin.paint(b, p, { hover = b.fxHover, checked = on, enabled = not p.disabled })
    b.label:SetPoint("LEFT", b, "LEFT", (m.width or TRACK_W) + (m.gap or 10), 0)
  else
    I.clearSkin(b)
    b.track:Show()
    b.knob:Show()
    local track = on and "gold" or "line"
    if b.fxHover and not p.disabled then track = I.mix(track, WHITE, 0.12) end
    b.track:SetVertexColor(I.rgba(track))
    b.knob:SetVertexColor(I.rgba(on and "onGold" or "text"))
    b.knob:ClearAllPoints()
    b.knob:SetPoint("LEFT", b.track, "LEFT", on and (TRACK_W - KNOB - 2) or 2, 0)
    b.label:SetPoint("LEFT", b.track, "RIGHT", 10, 0)
    b:SetAlpha(p.disabled and 0.5 or 1)
  end
  I.leave(prevTheme)
end

-- Props: checked, onChange(newValue), label, disabled.
I.defineHost("Toggle", {
  create = function(holder)
    local b = CreateFrame("Button", nil, holder)
    b.track = b:CreateTexture(nil, "BACKGROUND")
    b.track:SetSize(TRACK_W, TRACK_H)
    b.track:SetPoint("LEFT")
    I.setShape(b.track, 8, false)
    if not b.track.fxShape then b.track:SetColorTexture(1, 1, 1, 1) end
    b.knob = b:CreateTexture(nil, "ARTWORK")
    b.knob:SetSize(KNOB, KNOB)
    I.setFile(b.knob, "Circle.tga")
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) self.fxHover = true; paintToggle(self) end)
    b:SetScript("OnLeave", function(self) self.fxHover = false; paintToggle(self) end)
    b:SetScript("OnClick", function(self)
      local node = self.fxNode
      if not node then return end
      local p = node.el.props
      if p.disabled then return end
      if p.onChange then p.onChange(not p.checked) end
    end)
    return b
  end,
  update = function(node, p)
    I.setText(node.region.label, p.label, "body", "text")
    paintToggle(node.region)
  end,
  measure = function(node)
    local p = node.el.props
    local m = I.metrics("Toggle")
    local tw, th, gap = m.width or TRACK_W, m.height or 20, m.gap or 10
    if not p.label or p.label == "" then return tw, th end
    local w = I.measureString(node.region.label)
    return tw + gap + w, th
  end,
  release = function(node)
    node.region.fxHover = false
  end,
})

---------------------------------------------------------------------------
-- Slider
---------------------------------------------------------------------------

local SLIDER_TRACK_H, SLIDER_KNOB, SLIDER_GAP, SLIDER_TRACK_W = 4, 12, 10, 120

local SLIDER_MAX_STOPS = 1000

-- The stops a slider moves between: `values` as given, or min to max by
-- step. A range that would need more than 1,000 stops steps by the
-- smallest whole multiple of `step` that keeps it to 1,000.
local function sliderStops(p)
  if type(p.values) == "table" and #p.values > 0 then return p.values end
  local lo, hi = tonumber(p.min) or 0, tonumber(p.max) or 1
  local step = tonumber(p.step) or 1
  if step <= 0 then step = 1 end
  if hi < lo then hi = lo end
  step = step * math.max(math.ceil((hi - lo) / ((SLIDER_MAX_STOPS - 1) * step) - 1e-9), 1)
  local out, i = {}, 0
  while lo + i * step < hi - step * 1e-6 do
    out[#out + 1] = lo + i * step
    i = i + 1
  end
  out[#out + 1] = hi
  return out
end

-- Index of the stop nearest `value` (the first of equals).
local function sliderIndex(stops, value)
  value = tonumber(value) or stops[1]
  local best, bestD = 1, math.huge
  for i, s in ipairs(stops) do
    local d = math.abs(s - value)
    if d < bestD then best, bestD = i, d end
  end
  return best
end

local function sliderText(p, v)
  if p.format then return tostring(p.format(v)) end
  return tostring(v)
end

-- Skin contract: skins.Slider.paint(frame, props, state) with state =
-- { hover, dragging, enabled, fraction }; frame.track, .fill, .knob, .label,
-- .valueText exist (hide what the skin does not use; the knob's position is
-- FxUI's).
local function paintSlider(f)
  local node = f.fxNode
  if not node or not f.fxStops then return end
  local prevTheme = I.enter(node)
  local p = node.el.props
  local n = #f.fxStops
  local frac = n > 1 and (sliderIndex(f.fxStops, p.value) - 1) / (n - 1) or 0
  local tw = f.track:GetWidth()
  f.fill:SetWidth(math.max(frac * tw, 0.01))
  f.knob:ClearAllPoints()
  f.knob:SetPoint("CENTER", f.track, "LEFT", frac * tw, 0)
  local skin = I.skin("Slider")
  if skin and skin.paint then
    skin.paint(f, p, { hover = f.fxHover, dragging = f.fxDrag, enabled = not p.disabled, fraction = frac })
  else
    I.clearSkin(f)
    f.track:Show()
    f.fill:Show()
    f.knob:Show()
    local hot = (f.fxHover or f.fxDrag) and not p.disabled
    f.track:SetVertexColor(I.rgba("line"))
    f.fill:SetVertexColor(I.rgba(p.tone or "gold"))
    f.knob:SetVertexColor(I.rgba(hot and I.mix("text", WHITE, 0.2) or "text"))
    f:SetAlpha(p.disabled and 0.5 or 1)
  end
  I.leave(prevTheme)
end

-- The stop under the cursor's x.
local function sliderAt(f)
  local left = f.track:GetLeft()
  local tw = f.track:GetWidth()
  local n = #f.fxStops
  if not left or tw <= 0 or n < 2 then return 1 end
  local cx = GetCursorPosition()
  cx = cx / f:GetEffectiveScale()
  local frac = math.min(math.max((cx - left) / tw, 0), 1)
  return math.floor(frac * (n - 1) + 0.5) + 1
end

-- Move to stop i; onChange only when the stop changes: from the value
-- shown, or for the drag (`drag` true) from the last stop it reached, so a
-- consumer that has not taken the value yet hears of each stop once. Only
-- the drag reads or moves that stop; the wheel steps from the value shown.
local function sliderSet(f, i, drag)
  local node = f.fxNode
  if not node then return end
  local p = node.el.props
  local stops = f.fxStops
  i = math.min(math.max(i, 1), #stops)
  local from = drag and f.fxDragStop or sliderIndex(stops, p.value)
  if drag then f.fxDragStop = i end
  if i == from then return end
  if p.onChange then p.onChange(stops[i]) end
end

local function sliderEndDrag(f)
  f.fxDrag, f.fxDragStop = nil, nil
  f:SetScript("OnUpdate", nil)
end

local function sliderDrag(f)
  local node = f.fxNode
  if not f.fxDrag or not node or node.el.props.disabled then
    sliderEndDrag(f)
    paintSlider(f)
    return
  end
  sliderSet(f, sliderAt(f), true)
end

-- The label's width with its gap, and room for the widest value, so the
-- track does not move as the value changes.
local function sliderWidths(node)
  local f = node.region
  local p = node.el.props
  local labelW = (p.label and p.label ~= "") and (I.measureString(f.label) + SLIDER_GAP) or 0
  local shown = f.valueText:GetText()
  local valueW = 0
  local stops = f.fxStops
  local probe = #stops <= 64 and stops or { stops[1], stops[#stops] }
  for _, v in ipairs(probe) do
    f.valueText:SetText(sliderText(p, v))
    valueW = math.max(valueW, I.measureString(f.valueText))
  end
  f.valueText:SetText(shown)
  return labelW, valueW
end

-- Props: value, min, max, step (default 1) or values (ascending stops),
-- onChange(value), label, format(value) -> text, tone (fill color),
-- disabled, tooltip.
I.defineHost("Slider", {
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetWordWrap(false)
    f.valueText = f:CreateFontString(nil, "OVERLAY")
    f.valueText:SetWordWrap(false)
    f.track = f:CreateTexture(nil, "BACKGROUND")
    f.track:SetHeight(SLIDER_TRACK_H)
    I.setShape(f.track, 2, false)
    if not f.track.fxShape then f.track:SetColorTexture(1, 1, 1, 1) end
    f.fill = f:CreateTexture(nil, "BORDER")
    f.fill:SetHeight(SLIDER_TRACK_H)
    f.fill:SetPoint("LEFT", f.track, "LEFT", 0, 0)
    I.setShape(f.fill, 2, false)
    if not f.fill.fxShape then f.fill:SetColorTexture(1, 1, 1, 1) end
    f.knob = f:CreateTexture(nil, "ARTWORK")
    f.knob:SetSize(SLIDER_KNOB, SLIDER_KNOB)
    I.setFile(f.knob, "Circle.tga")
    f:SetScript("OnEnter", function(self)
      self.fxHover = true
      paintSlider(self)
      local node = self.fxNode
      if node then showTooltip(self, node.el.props.tooltip) end
    end)
    f:SetScript("OnLeave", function(self)
      self.fxHover = false
      paintSlider(self)
      hideTooltip(self)
    end)
    f:SetScript("OnMouseDown", function(self, button)
      local node = self.fxNode
      if not node or node.el.props.disabled or (button and button ~= "LeftButton") then return end
      self.fxDrag = true
      sliderSet(self, sliderAt(self), true)
      paintSlider(self)
      self:SetScript("OnUpdate", sliderDrag)
    end)
    f:SetScript("OnMouseUp", function(self, button)
      if button and button ~= "LeftButton" then return end
      sliderEndDrag(self)
      paintSlider(self)
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
      local node = self.fxNode
      if not node or node.el.props.disabled then return end
      sliderSet(self, sliderIndex(self.fxStops, node.el.props.value) + (delta > 0 and 1 or -1))
    end)
    return f
  end,
  update = function(node, p)
    local f = node.region
    f.fxStops = sliderStops(p)
    if p.disabled and f.fxDrag then sliderEndDrag(f) end
    I.setText(f.label, p.label, "body", "text")
    f.label:SetShown(p.label ~= nil and p.label ~= "")
    I.setText(f.valueText, sliderText(p, f.fxStops[sliderIndex(f.fxStops, p.value)]), "mono", "text")
    f.valueText:SetJustifyH("RIGHT")
    paintSlider(f)
  end,
  measure = function(node)
    local labelW, valueW = sliderWidths(node)
    return labelW + SLIDER_TRACK_W + SLIDER_GAP + valueW, 20
  end,
  layout = function(node, w, h)
    local f = node.region
    local labelW, valueW = sliderWidths(node)
    f.label:ClearAllPoints()
    f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.label:SetSize(math.max(labelW - SLIDER_GAP, 0), h)
    f.valueText:ClearAllPoints()
    f.valueText:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.valueText:SetSize(valueW, h)
    -- Half a knob of room at each end, so the knob stays inside.
    local half = SLIDER_KNOB / 2
    local tw = math.max(w - labelW - valueW - SLIDER_GAP - SLIDER_KNOB, 1)
    f.track:ClearAllPoints()
    f.track:SetPoint("LEFT", f, "LEFT", labelW + half, 0)
    f.track:SetWidth(tw)
    paintSlider(f)
  end,
  release = function(node)
    local f = node.region
    f.fxHover = false
    sliderEndDrag(f)
    hideTooltip(f)
  end,
})

---------------------------------------------------------------------------
-- Tab and TabBar
---------------------------------------------------------------------------

-- Skin contract: skins.Tab.paint(button, props, state) with state =
-- { hover, selected }; button.label, .count, .underline exist.
-- metrics.Tab = { height, pad }.
local function paintTab(b)
  local node = b.fxNode
  if not node then return end
  local prevTheme = I.enter(node)
  local p = node.el.props
  local selected = p.selected
  local skin = I.skin("Tab")
  if skin and skin.paint then
    I.clearSurface(b)
    skin.paint(b, p, { hover = b.fxHover, selected = selected })
    I.leave(prevTheme)
    return
  end
  -- Plain tabs: state shows in the text color; the selected tab's mark is
  -- drawn on the line under the row (TabRail), not on the tab.
  I.clearSkin(b)
  I.clearSurface(b)
  b.label:SetTextColor(I.rgba((selected or b.fxHover) and "text" or "muted"))
  b.underline:SetShown(false)
  I.leave(prevTheme)
end

-- Props: text, count, selected, onSelect(id), id.
I.defineHost("Tab", {
  create = function(holder)
    local b = CreateFrame("Button", nil, holder)
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
    b.underline = b:CreateTexture(nil, "OVERLAY")
    b.underline:SetPoint("BOTTOMLEFT")
    b.underline:SetPoint("BOTTOMRIGHT")
    b.underline:SetHeight(2)
    b:SetScript("OnEnter", function(self) self.fxHover = true; paintTab(self) end)
    b:SetScript("OnLeave", function(self) self.fxHover = false; paintTab(self) end)
    b:SetScript("OnClick", function(self)
      local node = self.fxNode
      if not node then return end
      local p = node.el.props
      if p.onSelect then p.onSelect(p.id) end
    end)
    return b
  end,
  update = function(node, p)
    local b = node.region
    -- One font for every state, so tabs keep their width when selected.
    I.setText(b.label, p.text, "strong")
    if p.count ~= nil then
      I.setText(b.count, p.count, "mono", "gold")
      b.count:Show()
    else
      I.setText(b.count, "", "mono")
      b.count:Hide()
    end
    b.underline:SetColorTexture(I.rgba("gold"))
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", I.metrics("Tab").pad or 14, 0)
    paintTab(b)
  end,
  measure = function(node)
    local b = node.region
    local m = I.metrics("Tab")
    local w = I.measureString(b.label)
    if node.el.props.count ~= nil then w = w + 6 + I.measureString(b.count) end
    return w + (m.pad or 14) * 2, m.height or 34
  end,
  release = function(node)
    node.region.fxHover = false
  end,
})

-- The line under a tab row. With metrics.Tab.openSelected (classic tabs)
-- it leaves a gap under the selected tab, so that tab opens into the panel
-- below. metrics.Tab.rail (rail height), .lineWidth, .railColor, .railAbove
-- (draw over the tabs), .railHighlight + .markColor (mark the selected tab
-- on the line).
I.defineHost("TabRail", {
  alignSelf = "stretch",
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    for _, side in ipairs({ "left", "right" }) do
      local seg = CreateFrame("Frame", nil, f)
      seg:SetClipsChildren(true)
      seg.fill = seg:CreateTexture(nil, "ARTWORK")
      f[side] = seg
    end
    f.mark = f:CreateTexture(nil, "OVERLAY")
    return f
  end,
  -- Skin contract: skins.Tab.paintRail(segmentFrame) draws one stretch of
  -- the rail (the segment clips its children); skins.Tab.railGap(tabButton)
  -- returns the screen x range the selected tab's art opens over.
  update = function(node)
    local m = I.metrics("Tab")
    local skin = I.skin("Tab")
    local r, g, b, a = I.rgba(m.railColor or "line")
    for _, seg in ipairs({ node.region.left, node.region.right }) do
      if skin and skin.paintRail then
        seg.fill:Hide()
        skin.paintRail(seg)
      else
        I.clearSkin(seg)
        if seg.fxInner then seg.fxInner:Hide() end
        -- The line sits at the bottom of the rail; the selected mark covers
        -- the rail's full height.
        seg.fill:Show()
        seg.fill:ClearAllPoints()
        seg.fill:SetPoint("BOTTOMLEFT")
        seg.fill:SetPoint("BOTTOMRIGHT")
        seg.fill:SetHeight(m.lineWidth or 1)
        seg.fill:SetColorTexture(r, g, b, a)
      end
    end
    node.region.mark:SetColorTexture(I.rgba(m.markColor or "gold"))
  end,
  measure = function()
    return 0, I.metrics("Tab").rail or 1
  end,
  layout = function(node, w, h)
    local f = node.region
    local m = I.metrics("Tab")
    local skin = I.skin("Tab")
    local gapX, gapW = w, 0
    -- The tab row is the element before the rail; find its selected tab and
    -- open the rail under where its art actually is on screen.
    local peers = node.parent and node.parent.children or {}
    local row
    for i, c in ipairs(peers) do
      if c == node then row = peers[i - 1] end
    end
    local railLeft = f:GetLeft()
    local selL, selR
    if row and row.children and railLeft then
      for _, tab in ipairs(row.children) do
        local b = tab.region
        if tab.el.props.selected and b then
          local l, r = b:GetLeft(), b:GetRight()
          if skin and skin.railGap then l, r = skin.railGap(b) end
          if l and r then selL, selR = l - railLeft, r - railLeft end
        end
      end
    end
    if m.openSelected and selL then gapX, gapW = selL, selR - selL end
    gapX = I.clamp(gapX, 0, w)
    -- metrics.Tab.railHighlight: the selected tab's mark on the line itself.
    f.mark:ClearAllPoints()
    if m.railHighlight and selL then
      f.mark:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", selL, 0)
      f.mark:SetSize(math.max(selR - selL, 0.001), h)
      f.mark:Show()
    else
      f.mark:Hide()
    end
    -- metrics.Tab.railAbove: the rail crosses over the tabs' bottoms (classic
    -- tabs tuck behind the panel's border; the selected one opens through).
    if m.railAbove and row and row.region then
      f:SetFrameLevel(row.region:GetFrameLevel() + 5)
    end
    -- railOffset lifts the line into the bottom of the tab row.
    local lift = m.railOffset or 0
    f.left:ClearAllPoints()
    f.left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, lift)
    f.left:SetSize(math.max(gapX, 0.001), h)
    f.right:ClearAllPoints()
    f.right:SetPoint("TOPLEFT", f, "TOPLEFT", gapX + gapW, lift)
    f.right:SetSize(math.max(w - gapX - gapW, 0.001), h)
    f.right:SetShown(gapX + gapW < w)
  end,
})

-- Props: tabs = { { id, text, count } }, selected, onSelect(id), padding.
UI.TabBar = I.defineComponent("TabBar", function(props)
  local tabs = {}
  for i, t in ipairs(props.tabs or {}) do
    tabs[i] = UI.Tab {
      key = t.id,
      id = t.id,
      text = t.text,
      count = t.count,
      selected = t.id == props.selected,
      onSelect = props.onSelect,
    }
  end
  return UI.VStack {
    gap = 0,
    UI.HStack { gap = I.metrics("Tab").gap or 4, padding = props.padding or { 8, 16, 0 }, align = "end", tabs },
    UI.TabRail {},
  }
end)
