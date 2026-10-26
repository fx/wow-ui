local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local WHITE, BLACK = "#FFFFFF", "#000000"

local function showTooltip(frame, text)
  if not text or text == "" then return end
  GameTooltip:SetOwner(frame, "ANCHOR_TOP")
  GameTooltip:SetText(text, 1, 1, 1, 1, true)
  GameTooltip:Show()
end

local function hideTooltip(frame)
  if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

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
