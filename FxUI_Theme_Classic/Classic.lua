-- Classic: FxUI drawn with the vanilla-era art the client still ships —
-- dialog and tooltip backdrops, red panel buttons, checkboxes, character
-- tabs, the red close button, Friz Quadrata text and coin icons. Any file
-- the client lacks falls back to FxUI's own drawing and is reported once.

local UI = LibStub("FxUI-1.0")
local K = UI.skinKit

local T = {
  dialogBg = "Interface\\DialogFrame\\UI-DialogBox-Background",
  dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tooltipBg = "Interface\\Tooltips\\UI-Tooltip-Background",
  tooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
  buttonUp = "Interface\\Buttons\\UI-Panel-Button-Up",
  buttonDown = "Interface\\Buttons\\UI-Panel-Button-Down",
  buttonHighlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
  buttonDisabled = "Interface\\Buttons\\UI-Panel-Button-Disabled",
  checkUp = "Interface\\Buttons\\UI-CheckBox-Up",
  checkHighlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
  check = "Interface\\Buttons\\UI-CheckBox-Check",
  checkDisabled = "Interface\\Buttons\\UI-CheckBox-Check-Disabled",
  tabActive = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab",
  tabInactive = "Interface\\OptionsFrame\\UI-OptionsFrame-InActiveTab",
  tabHighlight = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight",
  dialogHeader = "Interface\\DialogFrame\\UI-DialogBox-Header",
  columnTabs = "Interface\\FriendsFrame\\WhoFrame-ColumnTabs",
  rowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
  iconFrame = "Interface\\Common\\WhiteIconFrame",
  closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
  closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
  statusBar = "Interface\\TargetingFrame\\UI-StatusBar",
  knob = "Interface\\Buttons\\UI-ScrollBar-Knob",
  goldIcon = "Interface\\MoneyFrame\\UI-GoldIcon",
}

local DIALOG = {
  bgFile = T.dialogBg,
  edgeFile = T.dialogBorder,
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local TOOLTIP = {
  bgFile = T.tooltipBg,
  edgeFile = T.tooltipBorder,
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local THIN = {
  bgFile = T.tooltipBg,
  edgeFile = T.tooltipBorder,
  tile = true, tileSize = 16, edgeSize = 10,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Which client files exist, checked once; missing ones are reported.
local missing = {}
local function has(path)
  local ok = K.textureExists(path)
  if not ok and not missing[path] then
    missing[path] = true
    local handler = geterrorhandler and geterrorhandler()
    local msg = "FxUI Classic: the client has no " .. path .. "; using FxUI's own drawing for it"
    if handler then handler(msg) else print(msg) end
  end
  return ok
end

local GOLD, WHITE, GRAY = "#FFD100", "#FFFFFF", "#808080"

-- A three-slice texture set (left cap, stretched middle, right cap) from one
-- file; coords are the u ranges of the caps and the v range of the art.
local function threeSlice(frame, prefix, file, layer, capW, u1, u2, u3, u4, v1, v2)
  local l = K.texture(frame, prefix .. "L", layer)
  local m = K.texture(frame, prefix .. "M", layer)
  local r = K.texture(frame, prefix .. "R", layer)
  for _, t in ipairs({ l, m, r }) do
    t:SetTexture(file)
    t:ClearAllPoints()
  end
  l:SetTexCoord(u1, u2, v1, v2)
  m:SetTexCoord(u2, u3, v1, v2)
  r:SetTexCoord(u3, u4, v1, v2)
  l:SetPoint("TOPLEFT")
  l:SetPoint("BOTTOMLEFT")
  l:SetWidth(capW)
  r:SetPoint("TOPRIGHT")
  r:SetPoint("BOTTOMRIGHT")
  r:SetWidth(capW)
  m:SetPoint("TOPLEFT", l, "TOPRIGHT")
  m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  return l, m, r
end

local function hideSlices(frame, prefix)
  if not frame.fxSkinTex then return end
  for _, k in ipairs({ "L", "M", "R" }) do
    local t = frame.fxSkinTex[prefix .. k]
    if t then t:Hide() end
  end
end

---------------------------------------------------------------------------
-- Skins
---------------------------------------------------------------------------

local skins = {}

skins.Button = {
  paint = function(b, p, st)
    local label = b.label
    if p.variant == "ghost" then
      K.clear(b)
      label:SetTextColor(K.color(st.enabled and (st.hover and WHITE or GOLD) or GRAY))
      label:SetPoint("CENTER")
      return
    end
    local file = (not st.enabled and T.buttonDisabled) or (st.pressed and T.buttonDown) or T.buttonUp
    if has(file) then
      -- The art fills the left 80x22 of a 128x32 file.
      threeSlice(b, "bg", file, "BACKGROUND", 12, 0, 0.09375, 0.53125, 0.625, 0, 0.6875)
      local hl = K.texture(b, "hl", "HIGHLIGHT")
      hl:SetTexture(T.buttonHighlight)
      hl:SetTexCoord(0, 0.625, 0, 0.6875)
      hl:SetBlendMode("ADD")
      hl:ClearAllPoints()
      hl:SetAllPoints()
      hl:SetShown(st.enabled)
    else
      hideSlices(b, "bg")
      K.surface(b, st.pressed and "#5A0A0A" or "#7A1010", "#3A0000", 4)
    end
    label:SetTextColor(K.color(st.enabled and (st.hover and WHITE or GOLD) or GRAY))
    label:SetPoint("CENTER", st.pressed and 1 or 0, st.pressed and -1 or 0)
  end,
}

skins.Toggle = {
  paint = function(b, p, st)
    b.track:Hide()
    b.knob:Hide()
    b:SetAlpha(1)
    local box = K.texture(b, "box", "ARTWORK")
    box:ClearAllPoints()
    box:SetPoint("LEFT")
    box:SetSize(24, 24)
    local check = K.texture(b, "check", "OVERLAY")
    check:ClearAllPoints()
    check:SetAllPoints(box)
    local hl = K.texture(b, "hl", "HIGHLIGHT")
    hl:ClearAllPoints()
    hl:SetAllPoints(box)
    if has(T.checkUp) then
      box:SetTexture(T.checkUp)
      box:SetVertexColor(1, 1, 1, 1)
      check:SetTexture(st.enabled and T.check or T.checkDisabled)
      hl:SetTexture(T.checkHighlight)
      hl:SetBlendMode("ADD")
    else
      box:SetColorTexture(0.1, 0.1, 0.1, 1)
      check:SetColorTexture(K.color(GOLD))
    end
    check:SetShown(st.checked)
    hl:SetShown(st.enabled)
    b.label:SetTextColor(K.color(st.enabled and WHITE or GRAY))
  end,
}

-- Options-window top tabs: 24 tall, 20 px caps; the selected tab hangs
-- 3 px lower so it joins the frame below; tabs overlap by 10.
-- The Options-window tab art is drawn 24 tall; TAB_H scales it (classic's
-- own top tabs are 32 tall), and everything measured in the art scales by
-- TAB_SCALE.
local TAB_H = 30
local TAB_SCALE = TAB_H / 24

local function tabSlices(b, prefix, file, anchor, dy)
  local l = K.texture(b, prefix .. "L", "BORDER")
  local m = K.texture(b, prefix .. "M", "BORDER")
  local r = K.texture(b, prefix .. "R", "BORDER")
  for _, t in ipairs({ l, m, r }) do
    t:SetTexture(file)
    t:ClearAllPoints()
    t:SetHeight(TAB_H)
  end
  l:SetTexCoord(0, 0.15625, 0, 1)
  m:SetTexCoord(0.15625, 0.84375, 0, 1)
  r:SetTexCoord(0.84375, 1, 0, 1)
  l:SetWidth(20)
  r:SetWidth(20)
  l:SetPoint(anchor .. "LEFT", b, anchor .. "LEFT", 0, dy)
  r:SetPoint(anchor .. "RIGHT", b, anchor .. "RIGHT", 0, dy)
  m:SetPoint("TOPLEFT", l, "TOPRIGHT")
  m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
end

-- An edge-only tooltip border: the rail under the tabs is its top edge.
local EDGE = {
  edgeFile = T.tooltipBorder,
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

skins.Tab = {
  paint = function(b, p, st)
    b.underline:Hide()
    b.label:SetFontObject(UI.font("small"))
    if b.count then b.count:SetFontObject(UI.font("small")) end
    if has(T.tabActive) then
      -- Every tab uses the full-height tab art; inactive ones are darker and
      -- sit on the rail, the selected one hangs 3 px lower into the panel.
      -- All tabs hang the same: the art's transparent foot sits below the
      -- row so every tab's flared feet land on the rail (see AGENTS.md).
      tabSlices(b, "on", T.tabActive, "BOTTOM", -5 * TAB_SCALE)
      local shade = st.selected and 1 or (st.hover and 0.85 or 0.65)
      for _, k in ipairs({ "onL", "onM", "onR" }) do b.fxSkinTex[k]:SetVertexColor(shade, shade, shade, 1) end
      hideSlices(b, "off")
      local hl = K.texture(b, "hl", "HIGHLIGHT")
      hl:SetTexture(T.tabHighlight)
      hl:SetBlendMode("ADD")
      hl:ClearAllPoints()
      hl:SetPoint("LEFT", b, "LEFT", 10, -4)
      hl:SetPoint("RIGHT", b, "RIGHT", -10, -4)
      hl:SetShown(not st.selected)
    else
      hideSlices(b, "on")
      hideSlices(b, "off")
      K.surface(b, st.selected and "#2A2A2A" or "#141414", "#5A4A2A", 4)
    end
    -- Centre label and count together, 2 px above the art's centre (the
    -- art hangs 5 below the button), the same in every tab.
    local countW = (b.count and b.count:IsShown()) and (b.count:GetStringWidth() + 6) or 0
    b.label:ClearAllPoints()
    b.label:SetPoint("CENTER", b, "CENTER", -countW / 2, (-5 + 2) * TAB_SCALE)
    b.label:SetTextColor(K.color((st.selected or st.hover) and WHITE or GOLD))
  end,
  -- The rail opens under the selected tab: its flared feet sit 10.4 units
  -- inside the art's edges (measured, AGENTS.md); open 9.5 in so the rail
  -- runs just under them.
  railGap = function(b)
    local l = b.fxSkinTex and b.fxSkinTex.onL
    local r = b.fxSkinTex and b.fxSkinTex.onR
    if l and r and l:IsShown() and l:GetLeft() and r:GetRight() then return l:GetLeft() + 9.5, r:GetRight() - 9.5 end
    return b:GetLeft(), b:GetRight()
  end,
  -- The rail is the top edge of a tooltip border, clipped by its segment.
  paintRail = function(seg)
    if not has(T.tooltipBorder) then
      seg.fill:Show()
      seg.fill:SetColorTexture(0.4, 0.4, 0.4, 1)
      return
    end
    local inner = seg.fxInner
    if not inner then
      inner = CreateFrame("Frame", nil, seg)
      seg.fxInner = inner
    end
    inner:Show()
    inner:ClearAllPoints()
    inner:SetPoint("TOPLEFT", seg, "TOPLEFT", -16, 0)
    inner:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 16, -32)
    K.backdrop(inner, EDGE, nil, "#999999")
  end,
}

skins.Window = {
  paint = function(f, p, size)
    if not K.backdrop(f, DIALOG) then
      K.surface(f, "#0B0B0B", "#5A4A2A", 4)
    end
    for i = 1, 3 do f.grip.lines[i]:SetColorTexture(K.color(GOLD)) end
    -- The gold title banner across the top border.
    if size.banner and has(T.dialogHeader) and (p.title or "") ~= "" then
      local h = f.header
      local mid = K.texture(h, "bannerM", "ARTWORK")
      local left = K.texture(h, "bannerL", "ARTWORK")
      local right = K.texture(h, "bannerR", "ARTWORK")
      for _, t in ipairs({ mid, left, right }) do
        t:SetTexture(T.dialogHeader)
        t:ClearAllPoints()
        t:SetHeight(40)
      end
      mid:SetTexCoord(0.31, 0.67, 0, 0.63)
      left:SetTexCoord(0.21, 0.31, 0, 0.63)
      right:SetTexCoord(0.67, 0.77, 0, 0.63)
      mid:SetPoint("TOP", f, "TOP", 0, 12)
      mid:SetWidth((f.title:GetStringWidth() or 0) + 10)
      left:SetWidth(30)
      right:SetWidth(30)
      left:SetPoint("RIGHT", mid, "LEFT")
      right:SetPoint("LEFT", mid, "RIGHT")
      f.title:ClearAllPoints()
      f.title:SetPoint("TOP", mid, "TOP", 0, -14)
    end
  end,
  paintFooter = function(footer)
    if not K.backdrop(footer, TOOLTIP, "#000000B3", "#808080") then
      K.surface(footer, "#000000", "#808080", 0)
    end
  end,
  paintClose = function(button, hover)
    local up = K.texture(button, "up", "ARTWORK")
    up:ClearAllPoints()
    up:SetAllPoints()
    if has(T.closeUp) then
      up:SetTexture(T.closeUp)
      up:SetVertexColor(1, 1, 1, 1)
      local hl = K.texture(button, "hl", "HIGHLIGHT")
      hl:SetTexture(T.closeHighlight)
      hl:SetBlendMode("ADD")
      hl:ClearAllPoints()
      hl:SetAllPoints()
    else
      up:SetColorTexture(0.6, 0.1, 0.1, hover and 1 or 0.8)
    end
  end,
}

skins.Meter = {
  paint = function(f, p)
    if not K.backdrop(f.track, THIN, "#000000AA", "#909090") then
      K.surface(f.track, "#000000", "#909090", 0)
    end
    local fill = f.fill
    f.track.fxFillInset = 3
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", f.track, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMLEFT", f.track, "BOTTOMLEFT", 3, 3)
    if fill.SetTextureSliceMargins then fill:SetTextureSliceMargins(0, 0, 0, 0) end
    fill.fxShape = nil
    if has(T.statusBar) then
      fill:SetTexture(T.statusBar)
      fill.fxFile = "UI-StatusBar"
      fill:SetVertexColor(K.color(p.tone or "gold"))
    else
      fill:SetColorTexture(K.color(p.tone or "gold"))
    end
  end,
}

-- The classic scrollbar knob: a fixed 16x24 nub (it does not stretch with
-- the thumb), centred in the thumb, on a faint dark track.
skins.Scroll = {
  paintThumb = function(thumb, hot)
    if thumb.track then thumb.track:SetVertexColor(0, 0, 0, 0.45) end
    if not has(T.knob) then return end
    thumb.tex:Hide()
    local knob = K.texture(thumb, "knob", "OVERLAY")
    knob:SetTexture(T.knob)
    knob:ClearAllPoints()
    knob:SetPoint("CENTER")
    if thumb.axis == "x" then
      knob:SetTexCoord(0.2, 0.875, 0.8, 0.875, 0.2, 0.125, 0.8, 0.125)
      knob:SetSize(24, 16)
    else
      knob:SetTexCoord(0.2, 0.8, 0.125, 0.875)
      knob:SetSize(16, 24)
    end
    knob:SetVertexColor(1, 1, 1, hot and 1 or 0.9)
  end,
}

-- Badges: a thin tooltip frame in the tone's color with tone text.
skins.Badge = {
  paint = function(f, p, tone)
    local r, g, b = K.color(tone)
    if p.solid then
      -- A darkened tone with white text stays readable for every tone.
      local fill = K.mix(tone, "#000000", 0.55)
      if not K.backdrop(f, THIN, fill) then K.surface(f, fill, nil, 4) end
      if f.SetBackdropBorderColor then f:SetBackdropBorderColor(r, g, b, 1) end
      f.label:SetTextColor(1, 1, 1, 1)
    else
      if not K.backdrop(f, THIN, "#000000CC") then K.surface(f, "#000000", nil, 4) end
      if f.SetBackdropBorderColor then f:SetBackdropBorderColor(r * 0.8, g * 0.8, b * 0.8, 1) end
      f.label:SetTextColor(r, g, b, 1)
    end
    f.label:SetFontObject(UI.font("small"))
  end,
}

-- List and table rows: the quest-log highlight on hover, gold for the
-- selected row.
skins.List = {
  paintRow = function(row, state)
    local hl = K.texture(row, "rowHL", "BACKGROUND", 1)
    if has(T.rowHighlight) then
      hl:SetTexture(T.rowHighlight)
      hl:SetBlendMode("ADD")
    else
      hl:SetColorTexture(1, 1, 1, 1)
      hl:SetBlendMode("ADD")
    end
    hl:ClearAllPoints()
    hl:SetAllPoints()
    if state == "pressed" then
      hl:SetVertexColor(1, 0.82, 0, 1)
    elseif state == "selected" then
      hl:SetVertexColor(1, 0.82, 0, 0.7)
    elseif state == "hover" then
      hl:SetVertexColor(1, 1, 1, 0.55)
    else
      hl:Hide()
    end
  end,
}

-- Table headers: the Who-list column tabs.
skins.HeaderCell = {
  paint = function(b, p, st)
    if has(T.columnTabs) then
      local l = K.texture(b, "colL", "BACKGROUND")
      local m = K.texture(b, "colM", "BACKGROUND")
      local r = K.texture(b, "colR", "BACKGROUND")
      for _, t in ipairs({ l, m, r }) do
        t:SetTexture(T.columnTabs)
        t:ClearAllPoints()
      end
      l:SetTexCoord(0, 0.078125, 0, 0.59375)
      m:SetTexCoord(0.078125, 0.90625, 0, 0.59375)
      r:SetTexCoord(0.90625, 0.96875, 0, 0.59375)
      l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(5)
      r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(4)
      m:SetPoint("TOPLEFT", l, "TOPRIGHT")
      m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
      if p.sortable then
        local hl = K.texture(b, "hl", "HIGHLIGHT")
        hl:SetTexture(T.tabHighlight)
        hl:SetBlendMode("ADD")
        hl:ClearAllPoints()
        hl:SetAllPoints()
      end
    end
    b.label:SetFontObject(UI.font("small"))
    b.label:SetTextColor(K.color(st.active and GOLD or WHITE))
  end,
}

-- Item icons: square, with the quality-tinted icon frame.
skins.ItemCell = {
  paintIcon = function(f, color, size)
    f.icon:SetSize(size, size)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    local frame = K.texture(f, "iconFrame", "OVERLAY")
    frame:ClearAllPoints()
    frame:SetAllPoints(f.icon)
    if has(T.iconFrame) then
      frame:SetTexture(T.iconFrame)
      frame:SetVertexColor(K.color(color))
    else
      frame:Hide()
    end
  end,
}

-- Chart readout and price tags in tooltip frames.
skins.Chart = {
  tag = function(t, kind, bg)
    if kind == "last" then
      -- Like a badge: tone border and tone text on black.
      local r, g, b = K.color(bg)
      if not K.backdrop(t, THIN, "#000000E6") then K.surface(t, "#000000", bg, 2) end
      if t.SetBackdropBorderColor then t:SetBackdropBorderColor(r * 0.8, g * 0.8, b * 0.8, 1) end
      t.text:SetTextColor(r, g, b, 1)
    else
      if not K.backdrop(t, THIN, "#000000E6", "#909090") then K.surface(t, "#000000", "#909090", 2) end
    end
  end,
}

---------------------------------------------------------------------------
-- The theme
---------------------------------------------------------------------------

local FRIZ, MORPHEUS, ARIAL = "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.TTF", "Fonts\\ARIALN.TTF"

UI.registerTheme({
  name = "classic",
  title = "Classic",
  base = "default",
  colors = {
    ground = "#000000",
    panel = "#0B0B0B",
    raised = "#1E1E1E",
    line = "#5A4A2A",
    text = "#FFFFFF",
    muted = GOLD,
    gold = GOLD,
    onGold = "#000000",
    info = "#69CCF0",
    up = "#1EFF00",
    down = "#FF3030",
    warn = "#FF8000",
    poor = "#9D9D9D",
    common = "#FFFFFF",
    uncommon = "#1EFF00",
    rare = "#0070DD",
    epic = "#A335EE",
    legendary = "#FF8000",
  },
  fonts = {
    display = { path = MORPHEUS, size = 22, shadow = true },
    title = { path = FRIZ, size = 14, shadow = true },
    body = { path = FRIZ, size = 12, shadow = true },
    strong = { path = FRIZ, size = 12, shadow = true },
    label = { path = FRIZ, size = 10, shadow = true },
    mono = { path = ARIAL, size = 13, shadow = true },
    small = { path = FRIZ, size = 10, shadow = true },
    monoSmall = { path = ARIAL, size = 11, shadow = true },
  },
  surfaces = {
    card = { backdrop = TOOLTIP, bgColor = "#000000B3", borderColor = "#B0B0B0" },
    toast = { backdrop = TOOLTIP, bgColor = "#000000E6", borderColor = "#B0B0B0" },
    inset = { backdrop = THIN, bgColor = "#00000080", borderColor = "#808080" },
  },
  money = "icons",
  metrics = {
    Button = {
      sizes = {
        sm = { height = 20, pad = 10 },
        md = { height = 22, pad = 14 },
        lg = { height = 26, pad = 18 },
      },
    },
    Toggle = { width = 24, height = 24, gap = 4 },
    -- The pane border under the tabs starts 1 px above the tab bottoms (as
    -- in AceGUI's tab groups): inactive tabs overlap it, the selected tab's
    -- art (hanging 3 px lower) covers it. 40% gray like AceGUI's pane.
    Tab = { height = 30, pad = 22, gap = -10, openSelected = true, rail = 5, railColor = "#666666", railAbove = true, railHighlight = false },
    Badge = { height = 18, pad = 7 },
    Meter = { barHeight = 16, inlineValue = true },
    HeaderCell = { height = 19, pad = 8 },
    Scroll = { width = 18, thumb = 16 },
    Window = {
      actions = "footer",
      status = "footer",
      md = { header = 34, title = "title", pad = 18, close = 32, closeInset = 2, inset = 10, titleColor = GOLD, banner = true, footer = 28, footerPad = 10 },
      sm = { header = 30, title = "strong", pad = 14, close = 28, closeInset = 0, inset = 8, titleColor = GOLD, banner = true, footer = 26, footerPad = 8 },
    },
  },
  skins = skins,
})
