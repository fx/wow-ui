local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local function scrollW() return I.metrics("Scroll").width or 10 end
local function thumbW() return I.metrics("Scroll").thumb or 6 end
local THUMB_MIN = 24

local refresh

-- Index of the row under the cursor, or nil (outside, past the end, or
-- over the scrollbar).
local function rowAt(node)
  local f = node.region
  if not f:IsVisible() or not f:IsMouseOver() then return nil end
  local p = node.el.props
  local rowH = p.rowHeight or 32
  local scale = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local left, bottom, width, height = f:GetRect()
  if not left then return nil end
  if node.scrolls and cx > left + width - (node.gutter or 10) then return nil end
  local i = math.floor((bottom + height - cy + (node.offset or 0)) / rowH) + 1
  if i < 1 or i > #(p.items or {}) then return nil end
  return i
end

local function setOffset(node, offset)
  node.offset = offset
  if node.viewW then refresh(node, node.viewW, node.viewH) end
end

local function maxOffset(node)
  local p = node.el.props
  local total = #(p.items or {}) * (p.rowHeight or 32)
  return math.max(total - (node.viewH or 0), 0)
end

local function thumbHeight(node)
  local p = node.el.props
  local total = #(p.items or {}) * (p.rowHeight or 32)
  local viewH = node.viewH or 0
  if total <= 0 then return viewH end
  return math.max(THUMB_MIN, viewH * viewH / total)
end

local function paintThumb(thumb)
  local node = thumb:GetParent().fxNode
  local prevTheme = I.enter(node)
  local hot = thumb.fxHover or thumb.fxDrag
  local skin = I.skin("Scroll")
  if skin and skin.paintThumb then
    thumb.axis = "y"
    skin.paintThumb(thumb, hot)
    I.leave(prevTheme)
    return
  end
  I.clearSkin(thumb)
  thumb.tex:Show()
  thumb.tex:SetVertexColor(I.rgba(hot and "muted" or I.mix("line", "#FFFFFF", 0.1)))
  I.leave(prevTheme)
end

local function dragUpdate(thumb)
  local f = thumb:GetParent()
  local node = f.fxNode
  if not node or not thumb.fxDrag then
    thumb:SetScript("OnUpdate", nil)
    return
  end
  local _, cy = GetCursorPosition()
  cy = cy / f:GetEffectiveScale()
  local travel = (node.viewH or 0) - thumbHeight(node)
  if travel <= 0 then return end
  local dy = thumb.fxDrag.y - cy
  setOffset(node, thumb.fxDrag.offset + dy * maxOffset(node) / travel)
end

local function keyOf(p, item, i)
  local key, k = p.key, nil
  if type(key) == "function" then
    k = key(item, i)
  elseif key and type(item) == "table" then
    k = item[key]
  end
  if k == nil then k = i end
  return k
end

-- Row background by state: pressed > selected > hover > stripe.
local function rowBg(node, p, i, k)
  if node.pressed == i then return I.mix("panel", "gold", 0.26), 1 end
  if p.selected ~= nil and p.selected == k then return I.mix("panel", "gold", 0.15), 1 end
  if node.hover == i and p.highlight ~= false then return I.mix("panel", "raised", 1.6), 1 end
  if p.striped and i % 2 == 0 then return "raised", 0.45 end
  return nil, nil
end

refresh = function(node, w, h)
  local prevTheme = I.enter(node)
  local f = node.region
  local p = node.el.props
  local items = p.items or {}
  local rowH = p.rowHeight or 32
  local overscan = p.overscan or 2
  local n = #items
  local total = n * rowH
  node.viewW, node.viewH = w, h

  local offset = I.clamp(node.offset or 0, 0, math.max(total - h, 0))
  node.offset = offset

  local first = math.max(math.floor(offset / rowH) + 1 - overscan, 1)
  local last = math.min(math.ceil((offset + h) / rowH) + overscan, n)

  -- Skin contract: skins.List.paintRow(rowFrame, state) with state
  -- "pressed" | "selected" | "hover" | "stripe" | nil.
  local skin = I.skin("List")
  local rowSkin = skin and skin.paintRow
  local els = {}
  for i = first, last do
    local item = items[i]
    local k = keyOf(p, item, i)
    local ok, row = I.safecall(p.render, item, i)
    local bg, alpha
    if not rowSkin then bg, alpha = rowBg(node, p, i, k) end
    els[#els + 1] = UI.VStack {
      key = k,
      justify = "center",
      padding = p.rowPadding or { 0, 12 },
      bg = bg,
      bgAlpha = alpha,
      ok and row or nil,
    }
  end
  I.reconcileChildren(node, f.content, els)

  local scrolls = total > h
  node.gutter = scrollW()
  local rowW = w - ((scrolls or p.scrollbar == "always") and node.gutter or 0)
  node.scrolls = scrolls
  for j = 1, #node.children do
    local i = first + j - 1
    local child = node.children[j]
    I.place(child, 0, (i - 1) * rowH - offset, rowW, rowH)
    if child.region then
      if rowSkin then
        local k = child.el.key
        local state
        if node.pressed == i then state = "pressed"
        elseif p.selected ~= nil and p.selected == k then state = "selected"
        elseif node.hover == i and p.highlight ~= false then state = "hover"
        elseif p.striped and i % 2 == 0 then state = "stripe" end
        rowSkin(child.region, state)
      else
        I.clearSkin(child.region)
      end
    end
  end

  f.track:SetShown(scrolls)
  f.thumb:SetShown(scrolls)
  if scrolls then
    local th = thumbHeight(node)
    local maxOff = math.max(total - h, 1)
    local ty = (offset / maxOff) * (h - th)
    f.thumb:ClearAllPoints()
    f.thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -ty)
    f.thumb:SetSize(thumbW(), th)
  end

  f.empty:SetShown(n == 0 and p.empty ~= nil)
  if n == 0 and p.empty then I.setText(f.empty, p.empty, "body", "muted") end
  I.leave(prevTheme)
end

-- Virtualized list: only visible rows (plus overscan) exist as frames.
-- Props: items, key (field name or function(item, i)), rowHeight,
-- render(item, i) -> element, striped, overscan, rowPadding, empty,
-- highlight (hover highlight, default on), selected (key of the active row),
-- onSelect(item, i, key) (row clicks select; buttons inside rows keep their
-- own clicks), onContextMenu(item, i, key) (a row right-clicked),
-- scrollbar ("always" reserves its width even when not needed).
I.defineHost("List", {
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f:SetClipsChildren(true)
    f:EnableMouseWheel(true)
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetAllPoints()

    f.track = f:CreateTexture(nil, "OVERLAY")
    f.track:SetPoint("TOPRIGHT", -2, 0)
    f.track:SetPoint("BOTTOMRIGHT", -2, 0)
    f.track:SetWidth(6)

    f.thumb = CreateFrame("Button", nil, f)
    f.thumb:SetFrameLevel(f.content:GetFrameLevel() + 10)
    f.thumb.tex = f.thumb:CreateTexture(nil, "OVERLAY")
    f.thumb.tex:SetAllPoints()
    f.thumb.track = f.track
    f.thumb:SetScript("OnEnter", function(self) self.fxHover = true; paintThumb(self) end)
    f.thumb:SetScript("OnLeave", function(self) self.fxHover = false; paintThumb(self) end)
    f.thumb:SetScript("OnMouseDown", function(self)
      local node = f.fxNode
      if not node then return end
      local _, cy = GetCursorPosition()
      self.fxDrag = { y = cy / f:GetEffectiveScale(), offset = node.offset or 0 }
      paintThumb(self)
      self:SetScript("OnUpdate", dragUpdate)
    end)
    f.thumb:SetScript("OnMouseUp", function(self)
      self.fxDrag = nil
      paintThumb(self)
      self:SetScript("OnUpdate", nil)
    end)

    f.empty = f:CreateFontString(nil, "OVERLAY")
    f.empty:SetPoint("CENTER")

    -- Hover follows the cursor; the row under it re-renders only on change.
    f:SetScript("OnUpdate", function(self)
      local node = self.fxNode
      if not node or not node.viewW then return end
      local i = rowAt(node)
      if i ~= node.hover then
        node.hover = i
        if node.pressed and node.pressed ~= i then node.pressed = nil end
        refresh(node, node.viewW, node.viewH)
      end
    end)
    f:SetScript("OnMouseDown", function(self, button)
      local node = self.fxNode
      if not node or button ~= "LeftButton" or not node.el.props.onSelect then return end
      node.pressed = rowAt(node)
      refresh(node, node.viewW, node.viewH)
    end)
    f:SetScript("OnMouseUp", function(self, button)
      local node = self.fxNode
      if not node then return end
      if button == "RightButton" then
        local p, i = node.el.props, rowAt(node)
        if i and p.onContextMenu then
          local item = (p.items or {})[i]
          p.onContextMenu(item, i, keyOf(p, item, i))
        end
        return
      end
      if not node.pressed then return end
      local i = node.pressed
      node.pressed = nil
      local p = node.el.props
      if button == "LeftButton" and rowAt(node) == i and p.onSelect then
        local item = (p.items or {})[i]
        p.onSelect(item, i, keyOf(p, item, i))
      end
      if node.alive then refresh(node, node.viewW, node.viewH) end
    end)

    f:SetScript("OnMouseWheel", function(self, delta)
      local node = self.fxNode
      if not node then return end
      local rowH = node.el.props.rowHeight or 32
      setOffset(node, (node.offset or 0) - delta * rowH * 3)
    end)
    return f
  end,
  init = function(node)
    node.offset = 0
  end,
  update = function(node, p)
    local f = node.region
    f:EnableMouse(p.onSelect ~= nil or p.onContextMenu ~= nil)
    f.track:SetWidth(thumbW())
    if I.setShape(f.track, 4, false) then
      f.track:SetVertexColor(I.rgba("ground"))
    else
      f.track:SetColorTexture(I.rgba("ground"))
    end
    if not I.setShape(f.thumb.tex, 4, false) then f.thumb.tex:SetColorTexture(1, 1, 1, 1) end
    paintThumb(f.thumb)
  end,
  measure = function(node)
    local p = node.el.props
    return 200, (p.rowHeight or 32) * (p.visibleRows or 8)
  end,
  layout = function(node, w, h)
    refresh(node, w, h)
  end,
  release = function(node)
    node.hover, node.pressed = nil, nil
    local thumb = node.region.thumb
    thumb.fxDrag, thumb.fxHover = nil, false
    thumb:SetScript("OnUpdate", nil)
  end,
})

-- Scroll a mounted list (by its node) to make row i visible.
function UI.scrollListTo(frame, i)
  local node = frame and frame.fxNode
  if not node or node.host ~= I.hosts.List then return end
  local rowH = node.el.props.rowHeight or 32
  setOffset(node, (i - 1) * rowH)
end
