local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------

-- Props: value (copper), compact, short (largest denomination only: 7.4g),
-- signed, tone (up|down or a color token), style (font token, default
-- mono), justify.
I.defineHost("Money", {
  create = function(holder)
    local fs = holder:CreateFontString(nil, "ARTWORK")
    fs:SetWordWrap(false)
    return fs
  end,
  update = function(node, p)
    local fs = node.region
    local text = UI.formatMoney(p.value, { compact = p.compact, short = p.short, signed = p.signed, colored = true })
    I.setText(fs, text, p.style or "mono", p.tone or p.color or "text")
    fs:SetJustifyH(p.justify or "LEFT")
  end,
  measure = function(node)
    return I.measureString(node.region)
  end,
})

---------------------------------------------------------------------------
-- ItemCell
---------------------------------------------------------------------------

local function resolveItem(item)
  if type(item) == "number" then return item, nil end
  if type(item) == "string" then
    local id = tonumber(item:match("item:(%d+)")) or tonumber(item)
    local link = item:find("|H", 1, true) and item or nil
    return id, link
  end
end

local insertLink

-- Skin contract: skins.ItemCell.paintIcon(frame, color, size) draws the
-- icon frame (frame.icon, .iconBg, .mask exist).
local function paintIcon(f, color)
  local node = f.fxNode
  local size = node and node.el.props.iconSize or 24
  local skin = I.skin("ItemCell")
  if skin and skin.paintIcon then
    if f.fxMasked then
      f.icon:RemoveMaskTexture(f.mask)
      f.fxMasked = false
    end
    f.iconBg:Hide()
    skin.paintIcon(f, color, size)
  else
    I.clearSkin(f)
    if not f.fxMasked then
      f.icon:AddMaskTexture(f.mask)
      f.fxMasked = true
    end
    f.icon:SetSize(size - 2, size - 2)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("CENTER", f.iconBg, "CENTER")
    f.iconBg:Show()
    f.iconBg:SetVertexColor(I.rgba(color))
  end
end

local function refreshItem(f)
  local node = f.fxNode
  if not node then return end
  local p = node.el.props
  local id, link = f.fxItemID, f.fxItemLink
  if not id then
    f.icon:SetTexture(134400) -- question mark
    I.setText(f.name, p.placeholder or "", "body", "muted")
    paintIcon(f, "line")
    return true
  end

  local icon = C_Item.GetItemIconByID(id)
  f.icon:SetTexture(icon or 134400)

  local name, itemLink, quality, level = C_Item.GetItemInfo(link or id)
  if name then
    f.fxResolvedLink = itemLink
    local color = UI.qualityColor(quality)
    I.setText(f.name, name, p.style or "body", color)
    paintIcon(f, color)
    if p.showLevel then
      local detailed = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(itemLink)
      f.fxLevel = detailed or level
    end
    return true
  end

  I.setText(f.name, p.placeholder or ("item:" .. id), p.style or "body", "muted")
  paintIcon(f, "line")
  return false
end

local extraText

local function requestItem(f, id)
  local item = Item:CreateFromItemID(id)
  if item:IsItemEmpty() then return end
  item:ContinueOnItemLoad(function()
    if f.fxNode and f.fxItemID == id then
      local node = f.fxNode
      local prevTheme = I.enter(node)
      refreshItem(f)
      I.setText(f.extra, extraText(f, node.el.props), "body", "muted")
      f.extra:SetShown(f.extra:GetText() ~= "")
      I.leave(prevTheme)
      I.requestLayout(node.root)
    end
  end)
end

extraText = function(f, p)
  if p.qty then return "\195\151" .. p.qty end -- U+00D7
  if p.showLevel and f.fxLevel then return "ilvl " .. f.fxLevel end
  return p.note or ""
end

-- Props: item (itemID or item link), qty, showLevel, note, iconSize,
-- tooltip(GameTooltip, itemID) to add lines after the item tooltip,
-- onClick(frame, itemID, link). Shift-click links the item into chat.
I.defineHost("ItemCell", {
  create = function(holder)
    local f = CreateFrame("Button", nil, holder)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.iconBg = f:CreateTexture(nil, "BACKGROUND")
    I.setFile(f.iconBg, "Round8.tga")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER", f.iconBg, "CENTER")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.mask = f:CreateMaskTexture()
    I.setFile(f.mask, "Round8.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.mask:SetAllPoints(f.icon)
    f.icon:AddMaskTexture(f.mask)
    f.fxMasked = true
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetWordWrap(false)
    f.name:SetJustifyH("LEFT")
    f.extra = f:CreateFontString(nil, "OVERLAY")
    f.extra:SetWordWrap(false)

    f:SetScript("OnEnter", function(self)
      local node = self.fxNode
      if not node or not self.fxItemID then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local link = self.fxItemLink or self.fxResolvedLink
      if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(self.fxItemID) end
      local extra = node.el.props.tooltip
      if extra then I.safecall(extra, GameTooltip, self.fxItemID) end
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
      if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    f:SetScript("OnClick", function(self, mouseButton)
      local node = self.fxNode
      if not node then return end
      local link = self.fxItemLink or self.fxResolvedLink
      if link and IsModifiedClick("CHATLINK") and insertLink then
        insertLink(link)
        return
      end
      local onClick = node.el.props.onClick
      if onClick then onClick(self, self.fxItemID, link, mouseButton) end
    end)
    return f
  end,
  update = function(node, p)
    local f = node.region
    local size = p.iconSize or 24
    f.iconBg:SetSize(size, size)
    f.icon:SetSize(size - 2, size - 2)
    f.iconBg:ClearAllPoints()
    f.iconBg:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.name:ClearAllPoints()
    f.name:SetPoint("LEFT", f.iconBg, "RIGHT", 8, 0)
    f.extra:ClearAllPoints()
    f.extra:SetPoint("LEFT", f.name, "RIGHT", 6, 0)

    local id, link = resolveItem(p.item)
    local changed = id ~= f.fxItemID or link ~= f.fxItemLink
    f.fxItemID, f.fxItemLink = id, link
    if changed then f.fxResolvedLink, f.fxLevel = nil, nil end
    if not refreshItem(f) and id then requestItem(f, id) end
    I.setText(f.extra, extraText(f, p), "body", "muted")
    f.extra:SetShown(f.extra:GetText() ~= "")
  end,
  measure = function(node, maxW)
    local f = node.region
    local size = node.el.props.iconSize or 24
    local nameW, lineH = I.measureString(f.name)
    local extraW = f.extra:GetText() ~= "" and (I.measureString(f.extra) + 6) or 0
    local w = size + 8 + nameW + extraW
    if maxW and w > maxW then w = maxW end
    return w, math.max(size, lineH)
  end,
  layout = function(node, w)
    local f = node.region
    local size = node.el.props.iconSize or 24
    local extraW = f.extra:GetText() ~= "" and (I.measureString(f.extra) + 6) or 0
    local nameW = math.max(w - size - 8 - extraW, 0)
    local natural = I.measureString(f.name)
    f.name:SetWidth(math.min(nameW, natural))
  end,
  release = function(node)
    local f = node.region
    f.fxItemID, f.fxItemLink, f.fxResolvedLink, f.fxLevel = nil, nil, nil, nil
    if GameTooltip:IsOwned(f) then GameTooltip:Hide() end
  end,
})

insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink

---------------------------------------------------------------------------
-- Meter
---------------------------------------------------------------------------

local BAR_H, HEADER_H, HEADER_GAP = 8, 18, 6

-- metrics.Meter = { barHeight, inlineValue (value text centred in the bar) }
local function meterMetrics()
  local m = I.metrics("Meter")
  return m.barHeight or BAR_H, m.inlineValue
end

-- Props: value, max, label, valueText, tone (fill color token).
-- Skin contract: skins.Meter.paint(frame, props) styles frame.track and
-- frame.fill (a texture); layout sizes the fill.
I.defineHost("Meter", {
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetPoint("TOPLEFT")
    f.value = f:CreateFontString(nil, "OVERLAY")
    f.value:SetPoint("TOPRIGHT")
    f.track = CreateFrame("Frame", nil, f)
    f.track:SetPoint("BOTTOMLEFT")
    f.track:SetPoint("BOTTOMRIGHT")
    f.fill = f.track:CreateTexture(nil, "ARTWORK")
    f.inline = f.track:CreateFontString(nil, "OVERLAY")
    f.inline:SetPoint("CENTER")
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    return f
  end,
  update = function(node, p)
    local f = node.region
    local barH, inline = meterMetrics()
    f.track:SetHeight(barH)
    local hasHeader = (p.label or (p.valueText and not inline)) and true or false
    I.setText(f.label, p.label or "", "body", "muted")
    I.setText(f.value, p.valueText or "", "mono", "text")
    I.setText(f.inline, p.valueText or "", "small", "text")
    f.label:SetShown(hasHeader)
    f.value:SetShown(hasHeader and not inline)
    f.inline:SetShown(inline and p.valueText ~= nil)
    local skin = I.skin("Meter")
    if skin and skin.paint then
      I.clearSurface(f.track)
      skin.paint(f, p)
    else
      I.clearSkin(f.track)
      f.track.fxFillInset = nil
      f.fill:ClearAllPoints()
      f.fill:SetPoint("TOPLEFT")
      f.fill:SetPoint("BOTTOMLEFT")
      I.applySurface(f.track, "ground", "line", 4)
      f.fill.fxFile, f.fill.fxShape = nil, nil
      if I.setShape(f.fill, 4, false) then
        f.fill:SetVertexColor(I.rgba(p.tone or "gold"))
      else
        f.fill:SetColorTexture(I.rgba(p.tone or "gold"))
      end
    end
  end,
  measure = function(node, maxW)
    local p = node.el.props
    local barH, inline = meterMetrics()
    local header = p.label or (p.valueText and not inline)
    local h = header and (HEADER_H + HEADER_GAP + barH) or barH
    return 200, h
  end,
  layout = function(node, w)
    local p = node.el.props
    local f = node.region
    local barH = meterMetrics()
    local inset = f.track.fxFillInset or 0
    local max = p.max or 1
    local frac = max > 0 and I.clamp((p.value or 0) / max, 0, 1) or 0
    local fillW = frac * (w - inset * 2)
    if fillW > 0 and fillW < barH and not f.track.fxFillInset then fillW = barH end
    f.fill:SetWidth(math.max(fillW, 0.001))
    f.fill:SetShown(fillW > 0)
  end,
})

---------------------------------------------------------------------------
-- Sparkline
---------------------------------------------------------------------------

local function linePool(f, field, i)
  local pool = f[field]
  local line = pool[i]
  if not line then
    line = f:CreateLine(nil, "ARTWORK")
    pool[i] = line
  end
  line:Show()
  return line
end

-- Props: values (array of numbers), color (token), reference (a value drawn
-- as a dashed line), thickness.
I.defineHost("Sparkline", {
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f.lines, f.dashes = {}, {}
    f.dot = f:CreateTexture(nil, "OVERLAY")
    I.setFile(f.dot, "Circle.tga")
    f.dot:SetSize(5, 5)
    return f
  end,
  update = I.noop,
  measure = function()
    return 120, 32
  end,
  layout = function(node, w, h)
    local f = node.region
    local p = node.el.props
    local values = p.values or {}
    local n = #values
    local used, dashes = 0, 0

    if n >= 2 and w > 0 and h > 0 then
      local lo, hi = math.huge, -math.huge
      for i = 1, n do
        local v = values[i]
        if v < lo then lo = v end
        if v > hi then hi = v end
      end
      if p.reference then
        if p.reference < lo then lo = p.reference end
        if p.reference > hi then hi = p.reference end
      end
      if hi == lo then hi, lo = hi + 1, lo - 1 end
      local inset = 3
      local function y(v) return inset + (v - lo) / (hi - lo) * (h - inset * 2) end
      local step = (w - inset * 2) / (n - 1)
      local r, g, b, a = I.rgba(p.color or "gold")
      local thick = p.thickness or 1.5

      for i = 1, n - 1 do
        local line = linePool(f, "lines", i)
        line:SetThickness(thick)
        line:SetColorTexture(r, g, b, a)
        line:SetStartPoint("BOTTOMLEFT", f, inset + (i - 1) * step, y(values[i]))
        line:SetEndPoint("BOTTOMLEFT", f, inset + i * step, y(values[i + 1]))
      end
      used = n - 1

      f.dot:ClearAllPoints()
      f.dot:SetPoint("CENTER", f, "BOTTOMLEFT", inset + (n - 1) * step, y(values[n]))
      f.dot:SetVertexColor(r, g, b, a)
      f.dot:Show()

      if p.reference then
        local ry = y(p.reference)
        local mr, mg, mb = I.rgba("muted")
        local x, dash, gap = 0, 4, 3
        while x < w do
          dashes = dashes + 1
          local line = linePool(f, "dashes", dashes)
          line:SetThickness(1)
          line:SetColorTexture(mr, mg, mb, 0.8)
          line:SetStartPoint("BOTTOMLEFT", f, x, ry)
          line:SetEndPoint("BOTTOMLEFT", f, math.min(x + dash, w), ry)
          x = x + dash + gap
        end
      end
    else
      f.dot:Hide()
    end

    for i = used + 1, #f.lines do f.lines[i]:Hide() end
    for i = dashes + 1, #f.dashes do f.dashes[i]:Hide() end
  end,
})

---------------------------------------------------------------------------
-- Chart: line or candlesticks, price column, crosshair hover
---------------------------------------------------------------------------

local INSET = 6

local function pooled(f, field, make)
  local list = f[field]
  return function(i)
    local r = list[i]
    if not r then
      r = make()
      list[i] = r
    end
    r:Show()
    return r
  end
end

local function hideFrom(list, n)
  for i = n + 1, #list do list[i]:Hide() end
end

local function defaultFormat(v)
  return UI.formatMoney(v, { short = true, colored = true })
end

local function shortPrice(v)
  return UI.formatMoney(math.floor(v + 0.5), { short = true })
end

-- A small tag: background plus one line of mono text.
local function newTag(parent)
  local t = CreateFrame("Frame", nil, parent)
  t.bg = t:CreateTexture(nil, "BACKGROUND")
  t.bg:SetAllPoints()
  t.text = t:CreateFontString(nil, "OVERLAY")
  t.text:SetPoint("LEFT", 4, 0)
  t.text:SetWordWrap(false)
  return t
end

-- Skin contract: skins.Chart.tag(frame, kind, bgColor) draws a tag's
-- background (kind: "readout", "hover" or "last"); frame.text is set.
local function setTag(t, text, bg, fg, kind)
  I.setText(t.text, text, "monoSmall", fg)
  local skin = I.skin("Chart")
  if skin and skin.tag then
    t.bg:Hide()
    skin.tag(t, kind, bg)
  else
    I.clearSkin(t)
    t.bg:Show()
    if I.setShape(t.bg, 4, false) then
      t.bg:SetVertexColor(I.rgba(bg))
    else
      t.bg:SetColorTexture(I.rgba(bg))
    end
  end
  local w = I.measureString(t.text)
  t:SetSize(w + 8, 16)
end

-- End a hover: hide the crosshair and, if a point was hovered, tell the
-- consumer with onHover(nil).
local function hideHover(f, node)
  local was = f.hoverIndex
  f.cross:Hide()
  f.hoverIndex, f.hoverY = nil, nil
  local onHover = was and node and node.el.props.onHover
  if onHover then I.safecall(onHover, nil) end
end

-- Draw the crosshair, dot, readout and price tag for the point at index i
-- with the cursor at plot height y.
local function drawHover(f, node, i, y)
  local g = node.geo
  local p = node.el.props
  local fmt = p.format or defaultFormat
  local x = g.xs[i]
  local mr, mg, mb = I.rgba("muted")

  f.vline:ClearAllPoints()
  f.vline:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, g.bottom)
  f.vline:SetSize(1, g.top - g.bottom)
  f.vline:SetColorTexture(mr, mg, mb, 0.55)
  f.hline:ClearAllPoints()
  f.hline:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", g.left, y)
  f.hline:SetSize(g.right - g.left, 1)
  f.hline:SetColorTexture(mr, mg, mb, 0.55)

  -- Price under the cursor, in the price column.
  local price = g.lo + (y - g.bottom) / (g.top - g.bottom) * (g.hi - g.lo)
  setTag(f.hoverTag, shortPrice(price), "raised", "text", "hover")
  f.hoverTag:ClearAllPoints()
  f.hoverTag:SetPoint("LEFT", f, "BOTTOMLEFT", g.right + 2, y)

  local label = p.labels and p.labels[i]
  local text
  if g.candles and g.mode == "candles" then
    local c = g.candles[i]
    local up = c.c >= c.o
    local change = c.o ~= 0 and (c.c - c.o) / c.o * 100 or 0
    local tone = I.hexOf(up and "up" or "down")
    text = string.format("O %s  H %s  L %s  C |cff%s%s|r  |cff%s%+.1f%%|r",
      fmt(c.o), fmt(c.h), fmt(c.l), tone, shortPrice(c.c), tone, change)
    f.readoutShort = string.format("|cff%s%s  %+.1f%%|r", tone, shortPrice(c.c), change)
    f.dot:Hide()
  elseif g.mode == "bars" then
    text = fmt(g.values[i])
    f.readoutShort = nil
    f.dot:Hide()
  else
    local v = g.values[i]
    text = fmt(v)
    f.readoutShort = nil
    f.dot:ClearAllPoints()
    f.dot:SetPoint("CENTER", f, "BOTTOMLEFT", x, g.y(v))
    f.dot:SetVertexColor(I.rgba(p.color or "gold"))
    f.dot:Show()
  end
  local function withLabel(t)
    if label then return "|cff" .. I.hexOf("muted") .. label .. "|r  " .. t end
    return t
  end
  setTag(f.readout, withLabel(text), I.mix("panel", "ground", 0.5), "text", "readout")
  -- Too wide for the plot: fall back to the short readout, then no label.
  local room = g.right - g.left
  if f.readout:GetWidth() > room and f.readoutShort then
    setTag(f.readout, withLabel(f.readoutShort), I.mix("panel", "ground", 0.5), "text", "readout")
  end
  if f.readout:GetWidth() > room then
    setTag(f.readout, f.readoutShort or text, I.mix("panel", "ground", 0.5), "text", "readout")
  end
  f.readout:ClearAllPoints()
  f.readout:SetPoint("TOPLEFT", f, "TOPLEFT", g.left, -2)

  f.cross:Show()
  if p.onHover then p.onHover(i) end
end

local function hoverUpdate(f)
  local node = f.fxNode
  local g = node and node.geo
  if not g or g.n == 0 or not f:IsVisible() or not f:IsMouseOver() then
    if f.hoverIndex then hideHover(f, node) end
    return
  end
  local scale = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local left, bottom = f:GetRect()
  if not left then return end
  local x, y = cx / scale - left, cy / scale - bottom
  if x < g.left or x > g.right then
    if f.hoverIndex then hideHover(f, node) end
    return
  end
  local i
  if g.slot then
    i = math.floor((x - g.left) / g.slot) + 1
  else
    i = math.floor((x - g.left) / g.step + 0.5) + 1
  end
  i = I.clamp(i, 1, g.n)
  y = I.clamp(y, g.bottom, g.top)
  if i ~= f.hoverIndex or math.abs(y - (f.hoverY or -1)) >= 1 then
    f.hoverIndex, f.hoverY = i, y
    local prevTheme = I.enter(node)
    drawHover(f, node, i, y)
    I.leave(prevTheme)
  end
end

-- Props: mode = "line" (default) | "bars" | "candles"; values (line and
-- bars) or candles = { { o, h, l, c } }; baseline (bars, default 0; bars
-- below it use the down color); labels (per point, shown on hover), color, reference
-- (dashed level), format(value) for the readout, axis (price column,
-- default on), grid (default on), onHover(index or nil).
I.defineHost("Chart", {
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f.grid, f.lines, f.dashes, f.bodies, f.wicks = {}, {}, {}, {}, {}
    f.axisHi = f:CreateFontString(nil, "OVERLAY")
    f.axisLo = f:CreateFontString(nil, "OVERLAY")
    f.lastTag = newTag(f)
    f.cross = CreateFrame("Frame", nil, f)
    f.cross:SetAllPoints()
    f.cross:SetFrameLevel(f:GetFrameLevel() + 5)
    f.vline = f.cross:CreateTexture(nil, "OVERLAY")
    f.hline = f.cross:CreateTexture(nil, "OVERLAY")
    f.dot = f.cross:CreateTexture(nil, "OVERLAY", nil, 2)
    I.setFile(f.dot, "Circle.tga")
    f.dot:SetSize(7, 7)
    f.readout = newTag(f.cross)
    f.hoverTag = newTag(f.cross)
    f.cross:Hide()
    f:SetScript("OnUpdate", hoverUpdate)
    -- A hidden chart gets no OnUpdate, so end the hover here.
    f:SetScript("OnHide", function(self)
      if self.hoverIndex then hideHover(self, self.fxNode) end
    end)
    return f
  end,
  update = I.noop,
  measure = function()
    return 240, 120
  end,
  layout = function(node, w, h)
    local f = node.region
    local p = node.el.props
    local mode = p.mode or "line"
    local candles = mode == "candles" and p.candles or nil
    if mode == "candles" and not candles then mode = "line" end
    local values = (not candles) and (p.values or {}) or nil
    local n = candles and #candles or #values
    local baseline = mode == "bars" and (p.baseline or 0) or nil
    local axis = p.axis ~= false
    local g = {
      left = INSET,
      right = w - INSET,
      bottom = INSET,
      top = h - INSET,
      n = n,
      mode = mode,
      candles = candles,
      values = values,
      xs = {},
    }
    node.geo = g
    -- New geometry: redraw the hover on the next frame (or end it there, if
    -- the cursor is no longer over a point) instead of ending it here.
    if f.hoverIndex then
      f.cross:Hide()
      f.hoverY = nil
    end

    local used = { lines = 0, dashes = 0, bodies = 0, wicks = 0, grid = 0 }
    if n == 0 or g.right <= g.left or g.top <= g.bottom then
      for k in pairs(used) do hideFrom(f[k], 0) end
      f.axisHi:Hide(); f.axisLo:Hide(); f.lastTag:Hide()
      return
    end

    -- Price range with a little headroom.
    local lo, hi = math.huge, -math.huge
    if candles then
      for i = 1, n do
        if candles[i].l < lo then lo = candles[i].l end
        if candles[i].h > hi then hi = candles[i].h end
      end
    else
      for i = 1, n do
        if values[i] < lo then lo = values[i] end
        if values[i] > hi then hi = values[i] end
      end
    end
    if p.reference then
      lo, hi = math.min(lo, p.reference), math.max(hi, p.reference)
    end
    if baseline then
      lo, hi = math.min(lo, baseline), math.max(hi, baseline)
    end
    if hi == lo then hi, lo = hi + 1, lo - 1 end
    local pad = (hi - lo) * 0.06
    -- Bars stand on their baseline: no headroom below it.
    lo, hi = (baseline and lo == baseline) and lo or lo - pad, hi + pad
    g.lo, g.hi = lo, hi

    -- The price column is as wide as its widest label.
    local last = candles and candles[n].c or values[n]
    if axis then
      I.setText(f.axisHi, shortPrice(hi), "monoSmall", "muted")
      I.setText(f.axisLo, shortPrice(lo), "monoSmall", "muted")
      I.setText(f.lastTag.text, shortPrice(last), "monoSmall")
      local widest = math.max(I.measureString(f.axisHi), I.measureString(f.axisLo), I.measureString(f.lastTag.text) + 8)
      g.right = w - math.min(math.max(widest + 6, 28), math.floor(w / 3))
    end
    local function y(v) return g.bottom + (v - lo) / (hi - lo) * (g.top - g.bottom) end
    g.y = y

    local lr, lg, lb = I.rgba("line")
    local grid = pooled(f, "grid", function() return f:CreateTexture(nil, "BACKGROUND") end)
    if p.grid ~= false then
      for k = 1, 3 do
        used.grid = used.grid + 1
        local t = grid(used.grid)
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", g.left, g.bottom + (g.top - g.bottom) * k / 4)
        t:SetSize(g.right - g.left, 1)
        t:SetColorTexture(lr, lg, lb, 0.6)
      end
    end

    local plotW = g.right - g.left
    if candles then
      local slot = plotW / n
      g.slot = slot
      local bodyW = math.max(1, math.floor(slot * 0.62))
      local body = pooled(f, "bodies", function() return f:CreateTexture(nil, "ARTWORK") end)
      local wick = pooled(f, "wicks", function() return f:CreateTexture(nil, "ARTWORK", nil, -1) end)
      for i = 1, n do
        local c = candles[i]
        local x = g.left + (i - 0.5) * slot
        g.xs[i] = x
        local r, gg, b = I.rgba(c.c >= c.o and "up" or "down")
        used.wicks = used.wicks + 1
        local wt = wick(used.wicks)
        wt:ClearAllPoints()
        wt:SetPoint("BOTTOM", f, "BOTTOMLEFT", x, y(c.l))
        wt:SetSize(1, math.max(y(c.h) - y(c.l), 1))
        wt:SetColorTexture(r, gg, b, 1)
        used.bodies = used.bodies + 1
        local bt = body(used.bodies)
        local top, bottom = y(math.max(c.o, c.c)), y(math.min(c.o, c.c))
        bt:ClearAllPoints()
        bt:SetPoint("BOTTOM", f, "BOTTOMLEFT", x, bottom)
        bt:SetSize(bodyW, math.max(top - bottom, 1))
        bt:SetColorTexture(r, gg, b, 1)
      end
    elseif mode == "bars" then
      local slot = plotW / n
      g.slot = slot
      local barW = math.max(1, math.floor(slot * 0.7))
      local body = pooled(f, "bodies", function() return f:CreateTexture(nil, "ARTWORK") end)
      for i = 1, n do
        local v = values[i]
        local x = g.left + (i - 0.5) * slot
        g.xs[i] = x
        local r, gg, b = I.rgba(v >= baseline and (p.color or "gold") or "down")
        used.bodies = used.bodies + 1
        local bt = body(used.bodies)
        local top, bottom = y(math.max(v, baseline)), y(math.min(v, baseline))
        bt:ClearAllPoints()
        bt:SetPoint("BOTTOM", f, "BOTTOMLEFT", x, bottom)
        bt:SetSize(barW, math.max(top - bottom, 1))
        bt:SetColorTexture(r, gg, b, 1)
      end
    else
      local step = n > 1 and plotW / (n - 1) or 0
      g.step = math.max(step, 1)
      local r, gg, b, a = I.rgba(p.color or "gold")
      local line = pooled(f, "lines", function() return f:CreateLine(nil, "ARTWORK") end)
      for i = 1, n do g.xs[i] = g.left + (i - 1) * step end
      for i = 1, n - 1 do
        used.lines = used.lines + 1
        local l = line(used.lines)
        l:SetThickness(1.5)
        l:SetColorTexture(r, gg, b, a)
        l:SetStartPoint("BOTTOMLEFT", f, g.xs[i], y(values[i]))
        l:SetEndPoint("BOTTOMLEFT", f, g.xs[i + 1], y(values[i + 1]))
      end
    end

    if p.reference then
      local ry = y(p.reference)
      local mr, mg, mb = I.rgba("muted")
      local dash = pooled(f, "dashes", function() return f:CreateLine(nil, "ARTWORK", nil, -2) end)
      local x = g.left
      while x < g.right do
        used.dashes = used.dashes + 1
        local l = dash(used.dashes)
        l:SetThickness(1)
        l:SetColorTexture(mr, mg, mb, 0.8)
        l:SetStartPoint("BOTTOMLEFT", f, x, ry)
        l:SetEndPoint("BOTTOMLEFT", f, math.min(x + 4, g.right), ry)
        x = x + 7
      end
    end

    for k, count in pairs(used) do hideFrom(f[k], count) end

    if axis then
      f.axisHi:ClearAllPoints()
      f.axisHi:SetPoint("TOPLEFT", f, "TOPLEFT", g.right + 4, -2)
      f.axisLo:ClearAllPoints()
      f.axisLo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", g.right + 4, 2)
      f.axisHi:Show(); f.axisLo:Show()
      local tone = p.color or "gold"
      if candles then
        tone = candles[n].c >= candles[n].o and "up" or "down"
      elseif baseline and last < baseline then
        tone = "down"
      end
      setTag(f.lastTag, shortPrice(last), tone, "ground", "last")
      f.lastTag:ClearAllPoints()
      f.lastTag:SetPoint("LEFT", f, "BOTTOMLEFT", g.right + 2, y(last))
      f.lastTag:Show()
    else
      f.axisHi:Hide(); f.axisLo:Hide(); f.lastTag:Hide()
    end
  end,
  release = function(node)
    hideHover(node.region, node)
    node.geo = nil
  end,
})

---------------------------------------------------------------------------
-- Legend: compact chips that wrap
---------------------------------------------------------------------------

local function swatch(it)
  local color = it.color or "muted"
  if it.shape == "line" then
    return UI.HStack { width = 10, height = 2, bg = color }
  elseif it.shape == "dash" then
    return UI.HStack { gap = 2, UI.HStack { width = 4, height = 2, bg = color }, UI.HStack { width = 4, height = 2, bg = color } }
  end
  return UI.Dot { size = 7, color = color }
end

-- Props: items = { { label, value (text, number or element), color,
-- shape = "dot" | "line" | "dash" } }, gap, rowGap.
UI.Legend = UI.component("Legend", function(props)
  local chips = {}
  for i, it in ipairs(props.items or {}) do
    local value = it.value
    if value ~= nil and not UI.isElement(value) then
      value = UI.Text { text = tostring(value), style = "monoSmall" }
    end
    chips[i] = UI.HStack {
      gap = 5,
      align = "center",
      swatch(it),
      UI.Text { text = it.label or "", style = "small", color = "muted" },
      value,
    }
  end
  return UI.HStack { wrap = true, gap = props.gap or 12, rowGap = props.rowGap or 4, align = "center", chips }
end)
