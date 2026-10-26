local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local SLICE_STRETCHED = Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched

-- Point a texture at one of FxUI's media files and remember which, since the
-- client reports addon files only by a temporary file ID.
function I.setFile(tex, name, wrapH, wrapV)
  if tex.fxFile == name then return end
  tex:SetTexture(I.media .. "Textures\\" .. name, wrapH, wrapV)
  tex.fxFile = name
end

function I.radiusOf(radius)
  if type(radius) == "string" then return UI.theme.radius[radius] or 0 end
  return radius or 0
end

-- Point a texture at a rounded shape (nine-sliced) or a plain square.
-- Returns false when the shape needs the square fallback.
function I.setShape(tex, radius, ring)
  local name, margin
  if radius >= 8 then
    name, margin = "Round8", 8
  elseif radius >= 4 then
    name, margin = "Round4", 4
  end
  if not name or not tex.SetTextureSliceMargins then return false end
  local key = name .. (ring and "Ring" or "")
  if tex.fxShape ~= key then
    tex:SetTexture(I.media .. "Textures\\" .. key .. ".tga")
    tex.fxFile = key .. ".tga"
    tex:SetTextureSliceMargins(margin, margin, margin, margin)
    if SLICE_STRETCHED then tex:SetTextureSliceMode(SLICE_STRETCHED) end
    tex.fxShape = key
  end
  return true
end

local function squareFill(tex, r, g, b, a)
  tex.fxShape, tex.fxFile = nil, nil
  tex:SetColorTexture(r, g, b, a)
  tex:SetVertexColor(1, 1, 1, 1)
end

local EDGES = {
  { "TOPLEFT", "TOPRIGHT", "height" },
  { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
  { "TOPLEFT", "BOTTOMLEFT", "width" },
  { "TOPRIGHT", "BOTTOMRIGHT", "width" },
}

local function squareBorder(frame, r, g, b, a)
  local edges = frame.fxEdges
  if not edges then
    edges = {}
    for i, e in ipairs(EDGES) do
      local t = frame:CreateTexture(nil, "BORDER")
      t:SetPoint(e[1])
      t:SetPoint(e[2])
      if e[3] == "height" then t:SetHeight(1) else t:SetWidth(1) end
      edges[i] = t
    end
    frame.fxEdges = edges
  end
  for i = 1, 4 do
    edges[i]:SetColorTexture(r, g, b, a)
    edges[i]:Show()
  end
end

local function hideEdges(frame)
  if frame.fxEdges then
    for i = 1, 4 do frame.fxEdges[i]:Hide() end
  end
end

-- Background and border for a frame. bg / border: color spec or nil.
function I.applySurface(frame, bg, border, radius, bgAlpha)
  local rad = I.radiusOf(radius)
  if bg then
    local t = frame.fxBg
    if not t then
      t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
      t:SetAllPoints()
      frame.fxBg = t
    end
    local r, g, b, a = I.rgba(bg, bgAlpha)
    if I.setShape(t, rad, false) then
      t:SetVertexColor(r, g, b, a)
    else
      squareFill(t, r, g, b, a)
    end
    t:Show()
  elseif frame.fxBg then
    frame.fxBg:Hide()
  end

  if border then
    local r, g, b, a = I.rgba(border)
    local t = frame.fxRing
    if rad > 0 then
      if not t then
        t = frame:CreateTexture(nil, "BORDER")
        t:SetAllPoints()
        frame.fxRing = t
      end
      if I.setShape(t, rad, true) then
        t:SetVertexColor(r, g, b, a)
        t:Show()
        hideEdges(frame)
        return
      end
      t:Hide()
    end
    if frame.fxRing then frame.fxRing:Hide() end
    squareBorder(frame, r, g, b, a)
  else
    if frame.fxRing then frame.fxRing:Hide() end
    hideEdges(frame)
  end
end

function I.clearSurface(frame)
  if frame.fxBg then frame.fxBg:Hide() end
  if frame.fxRing then frame.fxRing:Hide() end
  hideEdges(frame)
end

---------------------------------------------------------------------------
-- Theme support: backdrops, skin textures, surface roles, texture probes
---------------------------------------------------------------------------

-- Classic-style backdrops (bgFile/edgeFile) on any frame, through the
-- client's BackdropTemplateMixin.
function I.setBackdrop(frame, def, bgColor, borderColor)
  if not frame.fxBackdropReady then
    if not (BackdropTemplateMixin and Mixin) then return false end
    Mixin(frame, BackdropTemplateMixin)
    frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
    frame.fxBackdropReady = true
  end
  frame:SetBackdrop(def)
  if bgColor then frame:SetBackdropColor(I.rgba(bgColor)) end
  if borderColor then frame:SetBackdropBorderColor(I.rgba(borderColor)) end
  frame.fxHasBackdrop = true
  return true
end

function I.clearBackdrop(frame)
  if frame.fxHasBackdrop then
    frame:ClearBackdrop()
    frame.fxHasBackdrop = false
  end
end

-- A texture a skin owns on a frame; I.clearSkin hides them all again, so a
-- pooled frame drawn by one theme is clean for the next.
function I.skinTexture(frame, key, layer, sublayer)
  frame.fxSkinTex = frame.fxSkinTex or {}
  local t = frame.fxSkinTex[key]
  if not t then
    t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sublayer)
    frame.fxSkinTex[key] = t
  end
  t:Show()
  return t
end

function I.clearSkin(frame)
  if frame.fxSkinTex then
    for _, t in pairs(frame.fxSkinTex) do t:Hide() end
  end
  I.clearBackdrop(frame)
end

-- Paint a stack's surface: explicit bg/border/radius props win; otherwise
-- the active theme's `surface` role (colors or a backdrop).
function I.paintSurface(frame, p)
  if p.bg or p.border then
    I.clearBackdrop(frame)
    I.applySurface(frame, p.bg, p.border, p.radius, p.bgAlpha)
    return
  end
  local role = p.surface and I.theme().surfaces[p.surface]
  if role and role.backdrop then
    I.clearSurface(frame)
    if not I.setBackdrop(frame, role.backdrop, role.bgColor, role.borderColor) then
      I.applySurface(frame, role.bgColor, role.borderColor, 0)
    end
  elseif role and (role.bg or role.border) then
    I.clearBackdrop(frame)
    I.applySurface(frame, role.bg, role.border, role.radius)
  else
    I.clearBackdrop(frame)
    I.clearSurface(frame)
  end
end

-- Whether the client has a texture file. Themes that use client art check
-- before relying on it and fall back to FxUI's own drawing.
I.textureCache = I.textureCache or {}
function UI.textureExists(path)
  local known = I.textureCache[path]
  if known ~= nil then return known end
  I.probe = I.probe or I.holder:CreateTexture()
  local ok = I.probe:SetTexture(path)
  local id = I.probe.GetTextureFileID and I.probe:GetTextureFileID()
  local exists = ok ~= false and id ~= nil and id ~= 0
  I.probe:SetTexture(nil)
  I.textureCache[path] = exists
  return exists
end

-- The toolkit theme addons draw skins with (see the Theme.lua comments for
-- the skin contracts):
--   texture(frame, key, layer, sublayer)  a texture owned by the skin
--   clear(frame)                          hide a frame's skin textures and backdrop
--   backdrop(frame, def, bg, border)      classic backdrop (bgFile/edgeFile)
--   surface(frame, bg, border, radius)    FxUI's rounded surface
--   color(spec)                           r, g, b, a for a token or "#RRGGBB[AA]"
--   mix(a, b, t)                          blend two colors
--   setText(fontString, text, font, color)
--   textureExists(path)                   whether the client ships a file
UI.skinKit = {
  texture = I.skinTexture,
  clear = I.clearSkin,
  backdrop = I.setBackdrop,
  surface = I.applySurface,
  color = function(spec, alpha) return I.rgba(spec, alpha) end,
  mix = function(a, b, t) return I.mix(a, b, t) end,
  setText = function(fs, text, font, color) return I.setText(fs, text, font, color) end,
  textureExists = UI.textureExists,
}
