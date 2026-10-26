local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

-- Header metrics per window size.
local SIZES = {
  md = { header = 48, title = "display", pad = 16, close = 28, closeInset = 10 },
  sm = { header = 32, title = "strong", pad = 10, close = 22, closeInset = 5 },
}

-- Window metrics for its size, with the active theme's overrides
-- (metrics.Window.md / .sm: header, title, pad, close, closeInset, inset).
local function sizeOf(p)
  local key = p.size or "md"
  local base = SIZES[key] or SIZES.md
  local own = (I.metrics("Window")[key]) or {}
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(own) do out[k] = v end
  out.inset = out.inset or 0
  return out
end

local function saveGeometry(f)
  local node = f.fxNode
  if not node then return end
  local saved = node.el.props.saved
  if not saved or node.el.props.dock then return end
  local left, top = f:GetLeft(), f:GetTop()
  if not left then return end
  saved.x, saved.y = left, top
  saved.w, saved.h = f:GetWidth(), f:GetHeight()
  saved.scale = f:GetScale()
end

local function anchor(f, p)
  f:ClearAllPoints()
  if p.dock then
    local side = p.dockSide or "right"
    local gap = p.dockGap or 8
    if side == "left" then
      f:SetPoint("TOPRIGHT", p.dock, "TOPLEFT", -gap, 0)
    else
      f:SetPoint("TOPLEFT", p.dock, "TOPRIGHT", gap, 0)
    end
    return
  end
  local saved = p.saved
  if saved and saved.x then
    -- Saved in the scale the window had then; keep the same spot on screen.
    local k = (saved.scale or 1) / f:GetScale()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x * k, saved.y * k)
  else
    f:SetPoint(p.point or "CENTER", UIParent, p.point or "CENTER", p.x or 0, p.y or 0)
  end
end

local function crossLine(parent, layer)
  local line = parent:CreateLine(nil, layer or "OVERLAY")
  line:SetThickness(1.5)
  return line
end

-- A floating window on UIParent. Props: title, width, height, minWidth,
-- minHeight, saved (a table the window stores its position and size in, e.g.
-- the consumer's per-character SavedVariables), dock (frame to attach to),
-- dockSide (right|left), dockGap, onClose, header (elements after the title),
-- padding, gap, strata, shown, size (md|sm: header height and title font),
-- scroll (default on: the body scrolls when its content is taller than it),
-- footer (elements in a status bar along the bottom; the bar exists only
-- when something is in it), status (text or elements: version, counts, ...)
-- and actions ({ { text, onClick, tooltip, variant, disabled } }), both
-- placed by the theme in the header (default) or the footer (Classic).
I.defineHost("Window", {
  floating = true,
  container = true,
  create = function(holder)
    local f = CreateFrame("Frame", nil, holder)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetToplevel(true)

    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT")
    f.header:SetPoint("TOPRIGHT")
    f.header:SetHeight(SIZES.md.header)
    f.header:EnableMouse(true)
    f.header:RegisterForDrag("LeftButton")
    f.header:SetScript("OnDragStart", function()
      local node = f.fxNode
      if node and not node.el.props.dock then f:StartMoving() end
    end)
    f.header:SetScript("OnDragStop", function()
      f:StopMovingOrSizing()
      saveGeometry(f)
    end)
    -- Square off the header's lower corners against the body.
    f.headerFoot = f.header:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.headerFoot:SetPoint("BOTTOMLEFT")
    f.headerFoot:SetPoint("BOTTOMRIGHT")
    f.headerFoot:SetHeight(10)
    f.headerLine = f.header:CreateTexture(nil, "BORDER")
    f.headerLine:SetPoint("BOTTOMLEFT")
    f.headerLine:SetPoint("BOTTOMRIGHT")
    f.headerLine:SetHeight(1)

    f.title = f.header:CreateFontString(nil, "OVERLAY")
    f.title:SetPoint("LEFT", SIZES.md.pad, 0)
    f.title:SetWordWrap(false)

    f.headerContent = CreateFrame("Frame", nil, f.header)

    f.close = CreateFrame("Button", nil, f.header)
    f.close:SetSize(SIZES.md.close, SIZES.md.close)
    f.close:SetPoint("RIGHT", -SIZES.md.closeInset, 0)
    f.close.a = crossLine(f.close)
    f.close.b = crossLine(f.close)
    f.close.a:SetStartPoint("CENTER", f.close, -5, -5)
    f.close.a:SetEndPoint("CENTER", f.close, 5, 5)
    f.close.b:SetStartPoint("CENTER", f.close, -5, 5)
    f.close.b:SetEndPoint("CENTER", f.close, 5, -5)
    local function paintClose(self)
      local prevTheme = I.enter(f.fxNode)
      local skin = I.skin("Window")
      if skin and skin.paintClose then
        self.a:Hide()
        self.b:Hide()
        I.clearSurface(self)
        skin.paintClose(self, self.fxHover)
      else
        I.clearSkin(self)
        self.a:Show()
        self.b:Show()
        local c = self.fxHover and "text" or "muted"
        self.a:SetColorTexture(I.rgba(c))
        self.b:SetColorTexture(I.rgba(c))
        if self.fxHover then I.applySurface(self, "line", nil, "r4") else I.clearSurface(self) end
      end
      I.leave(prevTheme)
    end
    f.close.paint = paintClose
    f.close:SetScript("OnEnter", function(self) self.fxHover = true; paintClose(self) end)
    f.close:SetScript("OnLeave", function(self) self.fxHover = false; paintClose(self) end)
    f.close:SetScript("OnClick", function()
      local node = f.fxNode
      if not node then return end
      if node.el.props.onClose then node.el.props.onClose() else f:Hide() end
    end)

    f.footer = CreateFrame("Frame", nil, f)
    f.footer.line = f.footer:CreateTexture(nil, "BORDER")
    f.footer.line:SetPoint("TOPLEFT")
    f.footer.line:SetPoint("TOPRIGHT")
    f.footer.line:SetHeight(1)
    f.footerContent = CreateFrame("Frame", nil, f.footer)
    f.footerContent:SetAllPoints()

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 0, -SIZES.md.header)
    f.body:SetPoint("BOTTOMRIGHT")
    f.body:SetClipsChildren(true)
    I.createScroller(f.body)

    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetFrameLevel(f:GetFrameLevel() + 20)
    f.grip:SetSize(16, 16)
    f.grip:SetPoint("BOTTOMRIGHT", -3, 3)
    f.grip.lines = {}
    for i = 1, 3 do
      local line = crossLine(f.grip, "OVERLAY")
      line:SetThickness(1)
      local o = i * 4
      line:SetStartPoint("BOTTOMRIGHT", f.grip, -o, 0)
      line:SetEndPoint("BOTTOMRIGHT", f.grip, 0, o)
      f.grip.lines[i] = line
    end
    f.grip:SetScript("OnMouseDown", function()
      local node = f.fxNode
      if node and not node.el.props.dock then f:StartSizing("BOTTOMRIGHT") end
    end)
    f.grip:SetScript("OnMouseUp", function()
      f:StopMovingOrSizing()
      saveGeometry(f)
    end)

    f:SetScript("OnSizeChanged", function(self)
      local node = self.fxNode
      if node then I.requestLayout(node.root) end
    end)
    return f
  end,
  content = function(node)
    return node.region.body.fxScroller.content
  end,
  init = function(node)
    node.fresh = true
  end,
  update = function(node, p, old)
    local f = node.region
    f:SetFrameStrata(p.strata or "HIGH")
    f:SetParent(UIParent)
    f:SetFrameStrata(p.strata or "HIGH")

    if node.fresh then
      f.fxAfterScale = saveGeometry
      I.followScale(f, false)
    end
    if node.fresh or (old and (old.dock ~= p.dock or old.dockSide ~= p.dockSide)) then
      local saved = p.saved
      local w = saved and not p.dock and saved.w or p.width or 640
      local h = saved and not p.dock and saved.h or p.height or 480
      f:SetSize(w, h)
      anchor(f, p)
      node.fresh = false
    end
    -- Docked windows move with their dock; free ones keep their spot on screen.
    I.scaled[f] = not p.dock
    if f.SetResizeBounds then
      f:SetResizeBounds(p.minWidth or 320, p.minHeight or 200)
    end

    local size = sizeOf(p)
    -- Skin contract: skins.Window.paint(frame, props, size) draws the frame
    -- and header (frame.header, .title, .headerFoot, .headerLine, .grip);
    -- skins.Window.paintClose(button, hover) draws the close button.
    local skin = I.skin("Window")
    if skin and skin.paint then
      I.clearSurface(f)
      I.clearSurface(f.header)
      f.headerFoot:Hide()
      f.headerLine:Hide()
    else
      I.clearSkin(f)
      I.clearSkin(f.header)
      f.headerFoot:Show()
      f.headerLine:Show()
      I.applySurface(f, "panel", I.mix("line", "#FFFFFF", 0.06), "r8")
      I.applySurface(f.header, "raised", nil, "r8")
      f.headerFoot:SetColorTexture(I.rgba("raised"))
      f.headerLine:SetColorTexture(I.rgba("line"))
    end
    f.header:SetHeight(size.header)
    f.title:ClearAllPoints()
    f.title:SetPoint("LEFT", size.pad, 0)
    f.close:SetSize(size.close, size.close)
    f.close:ClearAllPoints()
    f.close:SetPoint("RIGHT", -size.closeInset, 0)
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", size.inset, -(size.header + size.inset))
    f.body:SetPoint("BOTTOMRIGHT", -size.inset, size.inset)
    I.setText(f.title, p.title or "", size.title, size.titleColor or I.mix("text", "gold", 0.12))
    if skin and skin.paint then skin.paint(f, p, size) end
    f.close.paint(f.close)
    I.paintScroller(f.body.fxScroller)
    f.close:SetShown(p.closable ~= false)
    f.grip:SetShown(not p.dock)
    f.grip:SetFrameLevel(f:GetFrameLevel() + 20)
    for i = 1, 3 do f.grip.lines[i]:SetColorTexture(I.rgba(size.gripColor or "muted")) end

    -- Header and footer contents: the addon's own `header` and `footer`
    -- elements, plus `status` and `actions`, which go where the theme wants
    -- them (metrics.Window.status / .actions: "header", the default, or
    -- "footer"). A footer exists only when something lands in it.
    local wm = I.metrics("Window")
    local statusAt, actionsAt = wm.status or "header", wm.actions or "header"
    local headerEls, footerEls = {}, {}
    for _, el in ipairs(p.header or {}) do headerEls[#headerEls + 1] = el end
    for _, el in ipairs(p.footer or {}) do footerEls[#footerEls + 1] = el end
    if p.status ~= nil then
      local target = statusAt == "footer" and footerEls or headerEls
      local list = p.status
      if type(list) ~= "table" or UI.isElement(list) then list = { list } end
      for i, item in ipairs(list) do
        if not UI.isElement(item) then
          item = UI.Text { key = "fxStatus" .. i, text = tostring(item), style = "small", color = "muted" }
        end
        target[#target + 1] = item
      end
    end
    if p.actions and #p.actions > 0 then
      local placement = actionsAt
      local target = placement == "footer" and footerEls or headerEls
      target[#target + 1] = UI.Spacer { key = "fxActionsSpacer" }
      for i, a in ipairs(p.actions) do
        target[#target + 1] = UI.Button {
          key = "fxAction" .. i,
          text = a.text,
          size = "sm",
          variant = a.variant or (placement == "footer" and "secondary" or "ghost"),
          tooltip = a.tooltip,
          disabled = a.disabled,
          onClick = a.onClick,
        }
      end
    end
    I.reconcileChildren(node, f.headerContent, headerEls, "headerChildren")
    I.reconcileChildren(node, f.footerContent, footerEls, "footerChildren")
    node.hasFooter = #footerEls > 0
    f.footer:SetShown(node.hasFooter)
    if node.hasFooter then
      -- Skin contract: skins.Window.paintFooter(footerFrame).
      if skin and skin.paintFooter then
        f.footer.line:Hide()
        I.clearSurface(f.footer)
        skin.paintFooter(f.footer)
      else
        I.clearSkin(f.footer)
        f.footer.line:Show()
        f.footer.line:SetColorTexture(I.rgba("line"))
        I.applySurface(f.footer, I.mix("panel", "ground", 0.5), nil, 0)
      end
    end
    f:SetShown(p.shown ~= false)
  end,
  layoutSelf = function(node)
    local f = node.region
    local p = node.el.props
    local w, h = f:GetSize()
    local size = sizeOf(p)
    -- A banner title with nothing else in the header (classic) needs only a
    -- thin strip; the close button then sits in the top-right corner.
    local compact = size.banner and #(node.headerChildren or {}) == 0
    local headerH = compact and (size.compactHeader or 14) or size.header
    f.header:SetHeight(headerH)
    f.close:ClearAllPoints()
    if compact then
      f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(size.closeInset or 0) - 2, -2)
    else
      f.close:SetPoint("RIGHT", f.header, "RIGHT", -size.closeInset, 0)
    end

    -- A banner title (classic) sits centred above the header, out of the way.
    local titleW = size.banner and 0 or I.measureString(f.title)
    local left = size.banner and size.pad or (size.pad + titleW + size.pad)
    local right = (p.closable ~= false) and (size.close + size.closeInset * 2) or size.pad
    f.headerContent:ClearAllPoints()
    f.headerContent:SetPoint("TOPLEFT", f.header, "TOPLEFT", left, 0)
    f.headerContent:SetSize(math.max(w - left - right, 0), headerH)
    I.stackLayout(node.headerChildren or {}, { gap = size.pad, align = "center" }, true, math.max(w - left - right, 0), headerH)

    local footerH = node.hasFooter and (size.footer or 28) or 0
    if node.hasFooter then
      f.footer:ClearAllPoints()
      -- The footer spans the full width; the resize grip sits on top of it,
      -- and only the footer's content keeps clear of the grip.
      f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", size.inset, size.inset)
      f.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -size.inset, size.inset)
      f.footer:SetHeight(footerH)
      local fw = w - size.inset * 2
      local pad = size.footerPad or 10
      local gripRoom = p.dock and 0 or 14
      I.stackLayout(node.footerChildren or {}, { gap = size.pad, align = "center", padding = { 0, pad + gripRoom, 0, pad } }, true, fw, footerH)
    end
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", size.inset, -(headerH + size.inset))
    f.body:SetPoint("BOTTOMRIGHT", -size.inset, size.inset + footerH)

    local bodyW = w - size.inset * 2
    local bodyH = h - headerH - size.inset * 2 - footerH
    local props = { gap = p.gap or 0, padding = p.padding, align = "stretch" }
    local sc = f.body.fxScroller
    if p.scroll == false then
      sc.maxX, sc.maxY = 0, 0
      I.scrollTo(sc, 0, 0)
      sc.content:SetSize(bodyW, bodyH)
      I.stackLayout(node.children or {}, props, false, bodyW, bodyH)
    else
      node.scroll = I.scrollLayout(sc, node.children or {}, props, bodyW, bodyH)
    end
  end,

  release = function(node)
    I.unfollowScale(node.region)
    local sc = node.region.body.fxScroller
    sc.offsetX, sc.offsetY = 0, 0
    if node.headerChildren then
      for i = 1, #node.headerChildren do I.releaseNode(node.headerChildren[i]) end
      node.headerChildren = nil
    end
    if node.footerChildren then
      for i = 1, #node.footerChildren do I.releaseNode(node.footerChildren[i]) end
      node.footerChildren = nil
    end
  end,
})
