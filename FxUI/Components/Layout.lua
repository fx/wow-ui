local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local function newFrame(holder)
  return CreateFrame("Frame", nil, holder)
end

local function updateBox(node, p)
  local f = node.region
  I.paintSurface(f, p)
  f:SetClipsChildren(p.clip and true or false)
  f:SetAlpha(p.alpha or 1)
end

local function stack(horizontal)
  return {
    container = true,
    create = newFrame,
    update = updateBox,
    measure = function(node, maxW, maxH)
      return I.stackMeasure(node.children, node.el.props, horizontal, maxW, maxH)
    end,
    layout = function(node, w, h)
      I.stackLayout(node.children, node.el.props, horizontal, w, h)
    end,
  }
end

-- Props: gap, padding, align (start|center|end|stretch), justify
-- (start|center|end|between), surface (a theme role: card, inset, ...),
-- or bg, border, radius directly, clip, plus the layout props
-- every element takes: width, height, flex, alignSelf, minWidth, minHeight.
-- HStack also takes wrap (flow onto new lines; flex is ignored) and rowGap.
I.defineHost("HStack", stack(true))
I.defineHost("VStack", stack(false))

-- Takes the free space in a stack, or a fixed `size` along both axes.
I.defineHost("Spacer", {
  defaultFlex = function(node)
    return node.el.props.size and 0 or 1
  end,
  update = I.noop,
  measure = function(node)
    local size = node.el.props.size or 0
    return size, size
  end,
})

-- A 1 px line in the `line` color; `vertical = true` for a column rule.
I.defineHost("Divider", {
  alignSelf = "stretch",
  create = function(holder)
    return holder:CreateTexture(nil, "ARTWORK")
  end,
  update = function(node, p)
    node.region:SetColorTexture(I.rgba(p.color or "line"))
  end,
  measure = function(node)
    if node.el.props.vertical then return 1, 0 end
    return 0, 1
  end,
})

-- A filled circle: status dots, legend keys.
I.defineHost("Dot", {
  create = function(holder)
    return holder:CreateTexture(nil, "ARTWORK")
  end,
  update = function(node, p)
    local t = node.region
    I.setFile(t, "Circle.tga")
    t:SetVertexColor(I.rgba(p.color or "muted"))
  end,
  measure = function(node)
    local size = node.el.props.size or 8
    return size, size
  end,
})

-- Measure a font string: unbounded width, or wrapped height inside maxW.
-- The client reports a string's height within its current size, so every
-- branch sets the size it measures at first (0 = automatic: unbounded width,
-- or a height that fits the lines), and never trusts a wrapped result below
-- what the line count needs.
function I.measureString(fs, maxW, wrap)
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
  local _, size = fs:GetFont()
  size = size or 13
  local lineH = fs.GetLineHeight and fs:GetLineHeight() or 0
  if lineH <= 0 then lineH = size * 1.15 end
  if wrap and maxW and maxW < w then
    fs:SetSize(maxW, 0)
    -- No narrower than a glyph: a zero-width box would need endless lines.
    local lines = math.ceil(w * 1.08 / math.max(maxW, size))
    local h = math.max(fs:GetStringHeight(), lines * lineH, size)
    return maxW, math.ceil(h)
  end
  fs:SetSize(0, 0)
  return math.ceil(w) + 1, math.ceil(math.max(fs:GetStringHeight(), size))
end

-- Apply a font token, color and text to a font string.
function I.setText(fs, text, style, color)
  style = style or "body"
  fs:SetFontObject(UI.font(style))
  text = text == nil and "" or tostring(text)
  local spec = UI.fontSpec(style)
  if spec and spec.caps then text = text:upper() end
  fs:SetText(text)
  if color then fs:SetTextColor(I.rgba(color)) end
end

-- Props: text, style (font token), color, justify (LEFT|CENTER|RIGHT),
-- wrap, maxLines.
I.defineHost("Text", {
  create = function(holder)
    return holder:CreateFontString(nil, "ARTWORK")
  end,
  update = function(node, p)
    local fs = node.region
    I.setText(fs, p.text, p.style, p.color or "text")
    fs:SetJustifyH(p.justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(p.wrap and true or false)
    fs:SetMaxLines(p.maxLines or 0)
    fs:SetAlpha(p.alpha or 1)
  end,
  measure = function(node, maxW)
    return I.measureString(node.region, maxW, node.el.props.wrap)
  end,
})

---------------------------------------------------------------------------
-- Scrolling: a clip frame whose content scrolls when larger than the clip
---------------------------------------------------------------------------

local THUMB_MIN = 24

-- metrics.Scroll = { width (gutter), thumb (thumb thickness) }
local function scrollW() return I.metrics("Scroll").width or 10 end
local function thumbW() return I.metrics("Scroll").thumb or 6 end
I.scrollGutter = scrollW

-- Thumbs paint with the theme their scroll area was laid out with.
local function paintThumb(thumb)
  local sc = thumb.fxScroller
  local prev = I.activeTheme
  I.activeTheme = sc and sc.theme or I.activeTheme
  local hot = thumb.fxHover or thumb.fxDrag
  local skin = I.skin("Scroll")
  if skin and skin.paintThumb then
    skin.paintThumb(thumb, hot)
  else
    I.clearSkin(thumb)
    thumb.tex:Show()
    thumb.track:SetAlpha(1)
    thumb.tex:SetVertexColor(I.rgba(hot and "muted" or I.mix("line", "#FFFFFF", 0.1)))
  end
  I.activeTheme = prev
end

-- Place both thumbs for the current offsets.
local function placeThumbs(sc)
  local clip = sc.clip
  if sc.maxY > 0 then
    local track = sc.viewH
    local th = math.max(THUMB_MIN, track * sc.viewH / sc.contentH)
    sc.thumbY.size = th
    sc.thumbY.travel = track - th
    sc.thumbY:ClearAllPoints()
    sc.thumbY:SetPoint("TOPRIGHT", clip, "TOPRIGHT", -2, -(sc.offsetY / sc.maxY) * (track - th))
    sc.thumbY:SetSize(sc.thumbW or 6, th)
  end
  if sc.maxX > 0 then
    local track = sc.viewW
    local tw = math.max(THUMB_MIN, track * sc.viewW / sc.contentW)
    sc.thumbX.size = tw
    sc.thumbX.travel = track - tw
    sc.thumbX:ClearAllPoints()
    sc.thumbX:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", (sc.offsetX / sc.maxX) * (track - tw), 2)
    sc.thumbX:SetSize(tw, sc.thumbW or 6)
  end
end

function I.scrollTo(sc, x, y)
  sc.offsetX = I.clamp(x or sc.offsetX, 0, sc.maxX)
  sc.offsetY = I.clamp(y or sc.offsetY, 0, sc.maxY)
  sc.content:ClearAllPoints()
  sc.content:SetPoint("TOPLEFT", sc.clip, "TOPLEFT", -sc.offsetX, sc.offsetY)
  placeThumbs(sc)
end

local function dragUpdate(thumb)
  local sc = thumb.fxScroller
  local d = thumb.fxDrag
  if not d then
    thumb:SetScript("OnUpdate", nil)
    return
  end
  if (thumb.travel or 0) <= 0 then return end
  local scale = sc.clip:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  if thumb.axis == "y" then
    I.scrollTo(sc, nil, d.offset + (d.at - cy / scale) * sc.maxY / thumb.travel)
  else
    I.scrollTo(sc, d.offset + (cx / scale - d.at) * sc.maxX / thumb.travel, nil)
  end
end

local function newThumb(sc, axis)
  local clip = sc.clip
  local track = clip:CreateTexture(nil, "OVERLAY")
  if axis == "y" then
    track:SetPoint("TOPRIGHT", -2, 0)
    track:SetPoint("BOTTOMRIGHT", -2, 0)
    track:SetWidth(6)
  else
    track:SetPoint("BOTTOMLEFT", 0, 2)
    track:SetPoint("BOTTOMRIGHT", 0, 2)
    track:SetHeight(6)
  end
  local thumb = CreateFrame("Button", nil, clip)
  thumb.axis = axis
  thumb.track = track
  thumb.fxScroller = sc
  thumb.tex = thumb:CreateTexture(nil, "OVERLAY")
  thumb.tex:SetAllPoints()
  thumb:SetScript("OnEnter", function(self) self.fxHover = true; paintThumb(self) end)
  thumb:SetScript("OnLeave", function(self) self.fxHover = false; paintThumb(self) end)
  thumb:SetScript("OnMouseDown", function(self)
    local scale = clip:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    if axis == "y" then
      self.fxDrag = { at = cy / scale, offset = sc.offsetY }
    else
      self.fxDrag = { at = cx / scale, offset = sc.offsetX }
    end
    paintThumb(self)
    self:SetScript("OnUpdate", dragUpdate)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self.fxDrag = nil
    paintThumb(self)
    self:SetScript("OnUpdate", nil)
  end)
  return thumb
end

local function showAxis(thumb, on)
  thumb:SetShown(on)
  thumb.track:SetShown(on)
end

-- Turn `clip` into a scroll area; children go into the returned scroller's
-- `content` frame. The wheel scrolls vertically, or horizontally with Shift
-- held or when there is nothing to scroll vertically.
function I.createScroller(clip)
  clip:SetClipsChildren(true)
  clip:EnableMouseWheel(true)
  local sc = { clip = clip, offsetX = 0, offsetY = 0, maxX = 0, maxY = 0, viewW = 0, viewH = 0, contentW = 0, contentH = 0, step = 48 }
  sc.content = CreateFrame("Frame", nil, clip)
  sc.content:SetPoint("TOPLEFT")
  sc.thumbY = newThumb(sc, "y")
  sc.thumbX = newThumb(sc, "x")
  showAxis(sc.thumbY, false)
  showAxis(sc.thumbX, false)
  clip:SetScript("OnMouseWheel", function(_, delta)
    local horizontal = sc.maxX > 0 and (sc.maxY <= 0 or IsShiftKeyDown())
    if horizontal then
      I.scrollTo(sc, sc.offsetX - delta * sc.step, nil)
    elseif sc.maxY > 0 then
      I.scrollTo(sc, nil, sc.offsetY - delta * sc.step)
    end
  end)
  clip.fxScroller = sc
  return sc
end

-- Stop scrolling: no range, offset 0, no scrollbars.
function I.scrollOff(sc)
  sc.maxX, sc.maxY = 0, 0
  showAxis(sc.thumbX, false)
  showAxis(sc.thumbY, false)
  I.scrollTo(sc, 0, 0)
end

-- A released scroll area is clean for its next user: not scrolled, no
-- scrollbars, no thumb hovered or dragged.
function I.resetScroller(sc)
  for _, thumb in ipairs({ sc.thumbX, sc.thumbY }) do
    thumb.fxDrag, thumb.fxHover = nil, false
    thumb:SetScript("OnUpdate", nil)
  end
  I.scrollOff(sc)
end

function I.paintScroller(sc)
  sc.thumbW = thumbW()
  sc.thumbY.track:SetWidth(sc.thumbW)
  sc.thumbX.track:SetHeight(sc.thumbW)
  for _, thumb in ipairs({ sc.thumbY, sc.thumbX }) do
    if I.setShape(thumb.track, 4, false) then
      thumb.track:SetVertexColor(I.rgba("ground"))
    else
      thumb.track:SetColorTexture(I.rgba("ground"))
    end
    if not I.setShape(thumb.tex, 4, false) then thumb.tex:SetColorTexture(1, 1, 1, 1) end
    paintThumb(thumb)
  end
end

local function withoutFlex(props, horizontal)
  local fixed = {}
  for k, v in pairs(props) do fixed[k] = v end
  fixed.noFlex = true
  return fixed
end

-- The measuring limit along one axis: none (nil) where the area scrolls on
-- that axis, so content keeps its natural size there; size otherwise.
local function limit(scrolls, size)
  if scrolls then return nil end
  return size
end

-- Lay out kids as a stack (vertical, or horizontal with opts.horizontal) in
-- a w x h scroll area that scrolls along opts.axis ("y", "x" or "both").
-- When the content fits, flex children share the free space as usual; when
-- it does not, children take their natural size along the scrolling axis.
-- Returns true when the area scrolls.
function I.scrollLayout(sc, kids, props, w, h, opts)
  opts = opts or {}
  sc.theme = I.activeTheme
  local axis = opts.axis or "y"
  local horizontal = opts.horizontal or false
  local scrollX, scrollY = axis ~= "y", axis ~= "x"

  -- Natural size, unbounded along the scrolling axes. Flexible children
  -- count at their natural size here: they may stretch to fill, but must
  -- not shrink below what their content needs.
  local fixed = withoutFlex(props)
  local natW, natH = I.stackMeasure(kids, fixed, horizontal, limit(scrollX, w), limit(scrollY, h))
  local overX = scrollX and natW > w + 0.5
  local overY = scrollY and natH > h + 0.5
  -- A scrollbar takes room from the other axis, which can cause overflow there.
  local gutter = scrollW()
  sc.thumbW = thumbW()
  if overY and scrollX and not overX then overX = natW > w - gutter + 0.5 end
  if overX and scrollY and not overY then overY = natH > h - gutter + 0.5 end

  local viewW = w - (overY and gutter or 0)
  local viewH = h - (overX and gutter or 0)
  sc.viewW, sc.viewH = viewW, viewH

  if not overX and not overY then
    sc.contentW, sc.contentH = w, h
    sc.content:SetSize(math.max(w, 0), math.max(h, 0))
    I.stackLayout(kids, props, horizontal, w, h)
    I.scrollOff(sc)
    return false
  end

  natW, natH = I.stackMeasure(kids, fixed, horizontal, limit(overX, viewW), limit(overY, viewH))
  local cw = overX and math.max(natW, viewW) or viewW
  local ch = overY and math.max(natH, viewH) or viewH
  sc.contentW, sc.contentH = cw, ch
  sc.maxX, sc.maxY = math.max(cw - viewW, 0), math.max(ch - viewH, 0)
  sc.content:SetSize(cw, ch)
  I.stackLayout(kids, fixed, horizontal, cw, ch)
  showAxis(sc.thumbY, sc.maxY > 0)
  showAxis(sc.thumbX, sc.maxX > 0)
  I.scrollTo(sc, sc.offsetX, sc.offsetY)
  return true
end

-- A stack that scrolls when its content is larger than its box.
-- Props: as VStack (gap, padding, align), direction (vertical | horizontal
-- | both; horizontal lays children out in a row), plus the layout props.
I.defineHost("ScrollView", {
  container = true,
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    I.createScroller(f)
    return f
  end,
  content = function(node)
    return node.region.fxScroller.content
  end,
  update = function(node, p)
    node.region.fxScroller.theme = node.theme
    I.paintScroller(node.region.fxScroller)
    I.paintSurface(node.region, p)
  end,
  measure = function(node, maxW, maxH)
    local p = node.el.props
    return I.stackMeasure(node.children, p, p.direction == "horizontal", maxW, maxH)
  end,
  layout = function(node, w, h)
    local p = node.el.props
    local dir = p.direction or "vertical"
    local horizontal = dir == "horizontal"
    local axis = dir == "both" and "both" or (horizontal and "x" or "y")
    local props = { gap = p.gap, padding = p.padding, align = p.align or (horizontal and "start" or (dir == "both" and "start" or "stretch")) }
    node.scroll = I.scrollLayout(node.region.fxScroller, node.children, props, w, h, { axis = axis, horizontal = horizontal })
  end,
  release = function(node)
    I.resetScroller(node.region.fxScroller)
  end,
})
