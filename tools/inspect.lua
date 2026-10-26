#!/usr/bin/env lua
-- Print an FxUI Dev snapshot (/fx dev) as a readable tree with problems flagged.
--
-- Usage: lua tools/inspect.lua <SavedVariables/FxUI_Dev.lua> [options]
--   --snapshot N   which snapshot (1 = oldest; default newest; -1 = previous)
--   --node ID      only the subtree of node ID, with full props and parts
--   --parts        list every node's sub-regions (labels, backgrounds, ...)
--   --props        list every node's full props
--   --frames       include frames dumped by name (/fx dev all FrameName)
--   --list         list stored snapshots and exit

local args = { ... }
local path
local opts = {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "--snapshot" or a == "--node" then
    opts[a:sub(3)] = tonumber(args[i + 1])
    i = i + 1
  elseif a:sub(1, 2) == "--" then
    opts[a:sub(3)] = true
  else
    path = a
  end
  i = i + 1
end

if not path then
  io.stderr:write("usage: lua tools/inspect.lua <SavedVariables/FxUI_Dev.lua> [--snapshot N] [--node ID] [--parts] [--props] [--frames] [--list]\n")
  os.exit(2)
end

-- SavedVariables files are plain assignments; run them in an empty sandbox.
local chunk = assert(loadfile(path))
-- The client writes non-finite numbers as nan / inf (a size measured from
-- an endless height, for example); keep them readable and flag them.
local env = { nan = 0 / 0, inf = math.huge }
setfenv(chunk, env)
chunk()
local db = env.FxUIDevDB or env.FxUIInspectDB
if not db or not db.snapshots or #db.snapshots == 0 then
  print("No snapshots in " .. path)
  os.exit(1)
end

local snaps = db.snapshots
if opts.list then
  for n, s in ipairs(snaps) do
    print(string.format("%d  %s  %d roots  %d errors", n, s.date or "?", #(s.roots or {}), #(s.errors or {})))
  end
  os.exit(0)
end

local index = opts.snapshot or #snaps
if index < 1 then index = #snaps + index end
local snap = snaps[index]
assert(snap, "no snapshot " .. tostring(opts.snapshot))

local out = {}
local function emit(s) out[#out + 1] = s end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. (type(x) == "table" and "{...}" or tostring(x)) end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return tostring(v)
end

local function n2(v)
  if type(v) ~= "number" then return "?" end
  if v == math.floor(v) then return tostring(v) end
  return string.format("%.1f", v)
end

-- Client rect as top-left origin box.
local function box(region)
  local r = region and region.rect
  if not r then return nil end
  local left, bottom, w, h = r[1], r[2], r[3], r[4]
  return { left = left, top = bottom + h, w = w, h = h, right = left + w, bottom = bottom }
end

local KEY_PROPS = { "text", "title", "label", "value", "variant", "size", "tone", "style", "color", "bg", "count", "selected", "checked", "item", "qty" }

local function propSummary(props, full)
  if not props then return "" end
  local parts, seen = {}, {}
  for _, k in ipairs(KEY_PROPS) do
    if props[k] ~= nil and type(props[k]) ~= "table" then
      seen[k] = true
      if k == "text" or k == "title" or k == "label" then
        parts[#parts + 1] = fmt(props[k])
      else
        parts[#parts + 1] = k .. "=" .. fmt(props[k])
      end
    end
  end
  if full then
    local rest = {}
    for k, v in pairs(props) do
      if not seen[k] then rest[#rest + 1] = k .. "=" .. fmt(v) end
    end
    table.sort(rest)
    for _, s in ipairs(rest) do parts[#parts + 1] = s end
  end
  return table.concat(parts, " ")
end

local function partLine(p)
  local bits = { (p.field or "?") .. ":" .. (p.type or "?") }
  if p.type == "FontString" then
    bits[#bits + 1] = fmt(p.text or "")
    if p.font then bits[#bits + 1] = p.font.file .. " " .. n2(p.font.size) end
    if p.color then bits[#bits + 1] = p.color end
    if p.textWidth then bits[#bits + 1] = "w=" .. n2(p.textWidth) end
    if p.truncated then bits[#bits + 1] = "TRUNCATED" end
  elseif p.type == "Texture" or p.type == "MaskTexture" then
    if p.texture then bits[#bits + 1] = tostring(p.texture) end
    if p.vertex then bits[#bits + 1] = p.vertex end
    if p.slice then bits[#bits + 1] = "slice " .. table.concat(p.slice, ",") end
    if p.uv then bits[#bits + 1] = string.format("uv %s-%s %s-%s%s", n2(p.uv[1]), n2(p.uv[2]), n2(p.uv[3]), n2(p.uv[4]), p.uv.flipped and " flipped" or "") end
    if p.blend then bits[#bits + 1] = p.blend end
  elseif p.type == "Line" then
    if p.vertex then bits[#bits + 1] = p.vertex end
  end
  local b = box(p)
  if b then bits[#bits + 1] = n2(b.w) .. "x" .. n2(b.h) end
  if p.alpha then bits[#bits + 1] = "alpha " .. n2(p.alpha) end
  if p.shown == false then bits[#bits + 1] = "hidden" end
  return table.concat(bits, " ")
end

local hover = {}
for _, h in ipairs(snap.hover or {}) do
  if h.node then hover[h.node] = true end
end

local issues = {}
local collecting = true -- off while printing the selection, so issues list once

local function flagsFor(node, parentBox)
  local flags = {}
  local region = node.region
  local b = box(region)
  if region then
    local nonFinite = false
    for _, v in ipairs(region.rect or {}) do
      if v ~= v or v == math.huge or v == -math.huge then nonFinite = true end
    end
    if nonFinite then
      flags[#flags + 1] = "NONFINITE"
      b = nil
    elseif not b and region.visible then
      flags[#flags + 1] = "NO-RECT"
    end
    if region.truncated then flags[#flags + 1] = "TRUNCATED" end
    if b and region.visible and (b.w <= 0 or b.h <= 0) then flags[#flags + 1] = "ZERO" end
    if b and node.layout then
      local lw, lh = node.layout[3], node.layout[4]
      if math.abs(lw - b.w) > 0.5 or math.abs(lh - b.h) > 0.5 then
        flags[#flags + 1] = string.format("SIZE %sx%s!=layout %sx%s", n2(b.w), n2(b.h), n2(lw), n2(lh))
      end
    end
    if b and parentBox and region.visible then
      local over = math.max(parentBox.left - b.left, b.right - parentBox.right, b.top - parentBox.top, parentBox.bottom - b.bottom)
      if over > 0.5 then
        flags[#flags + 1] = "OVERFLOW " .. n2(over)
      elseif parentBox.pad then
        -- Inside the parent but into its padding: spacing no longer uniform.
        local p = parentBox.pad
        local into = math.max(parentBox.left + p[4] - b.left, b.right - (parentBox.right - p[2]),
          b.top - (parentBox.top - p[1]), (parentBox.bottom + p[3]) - b.bottom)
        if into > 0.5 then flags[#flags + 1] = "PADDING " .. n2(into) end
      end
    end
  end
  for _, p in ipairs(node.parts or {}) do
    if p.truncated and p.shown ~= false then flags[#flags + 1] = "TRUNCATED(" .. (p.field or "?") .. ")" end
  end
  -- Labels and tags drawn inside a component that stick out of it.
  if b and region and region.visible then
    local function check(list)
      for _, p in ipairs(list or {}) do
        local pb = box(p)
        -- A scroll area's content frame is larger than the area by design.
        if pb and p.visible ~= false and p.shown ~= false and p.field ~= "scrollContent"
          and (p.type == "FontString" or p.type == "Frame" or p.type == "Button") then
          local over = math.max(b.left - pb.left, pb.right - b.right, pb.top - b.top, b.bottom - pb.bottom)
          if over > 0.5 then flags[#flags + 1] = "OVERFLOW(" .. (p.field or "?") .. ") " .. n2(over) end
        end
      end
    end
    check(node.parts)
    for _, p in ipairs(node.parts or {}) do
      -- A part that clips its children hides whatever sticks out of it.
      if p.shown ~= false and p.visible ~= false and not p.clips then check(p.parts) end
    end
  end
  return flags
end

-- CSS-style padding shorthand from serialized props: n | {v,h} | {t,h,b} | {t,r,b,l}.
local function paddingOf(p)
  if type(p) == "number" then return { p, p, p, p } end
  if type(p) ~= "table" then return nil end
  local a, b, c, d = p[1], p[2], p[3], p[4]
  if not a then return nil end
  if not b then return { a, a, a, a } end
  if not c then return { a, b, a, b } end
  if not d then return { a, b, c, b } end
  return { a, b, c, d }
end

local PADDED = { HStack = true, VStack = true, ScrollView = true }

local function walk(node, depth, parentBox, path, full)
  local indent = string.rep("  ", depth)
  local name = node.component or node.host
  local label = (node.component and "<" .. name .. ">" or name)
  local here = path .. " > " .. name

  if node.component then
    local state = node.state and next(node.state) and (" state" .. fmt(node.state)) or ""
    emit(string.format("%s#%d %s %s%s", indent, node.id, label, propSummary(node.props, full or opts.props), state))
    for _, c in ipairs(node.children or {}) do walk(c, depth + 1, parentBox, here, full) end
    return
  end

  local b = box(node.region)
  local geo = ""
  if b then
    local x, y = b.left, b.top
    if parentBox then x, y = b.left - parentBox.left, parentBox.top - b.top end
    geo = string.format("  @%s,%s %sx%s", n2(x), n2(y), n2(b.w), n2(b.h))
  elseif node.layout then
    geo = string.format("  layout %sx%s", n2(node.layout[3]), n2(node.layout[4]))
  end
  local region = node.region or {}
  local extra = {}
  if region.visible == false then extra[#extra + 1] = "invisible" end
  if region.alpha then extra[#extra + 1] = "alpha " .. n2(region.alpha) end
  if region.strata and depth == 0 then extra[#extra + 1] = region.strata .. "/" .. tostring(region.level) end
  if region.clips then extra[#extra + 1] = "clips" end
  if node.theme then extra[#extra + 1] = "theme " .. node.theme end
  if node.scroll then
    local sx, mx, sy, my = node.scroll[1], node.scroll[2], node.scroll[3], node.scroll[4]
    local parts = {}
    if (my or 0) > 0 then parts[#parts + 1] = "y " .. n2(sy) .. "/" .. n2(my) end
    if (mx or 0) > 0 then parts[#parts + 1] = "x " .. n2(sx) .. "/" .. n2(mx) end
    extra[#extra + 1] = "scrolls " .. table.concat(parts, " ")
  end
  if region.enabled == false then extra[#extra + 1] = "disabled" end
  if region.type == "FontString" and region.font then
    extra[#extra + 1] = region.font.file .. " " .. n2(region.font.size) .. " " .. tostring(region.color)
  end

  local flags = flagsFor(node, parentBox)
  if collecting then
    for _, f in ipairs(flags) do issues[#issues + 1] = string.format("#%d %s: %s", node.id, here:sub(4), f) end
  end
  local flagText = #flags > 0 and ("  !! " .. table.concat(flags, " ")) or ""
  local hoverText = hover[node.id] and "  <== HOVER" or ""
  if snap.selected == node.id then hoverText = hoverText .. "  <== SELECTED" end

  emit(string.format("%s#%d %s %s%s%s%s%s", indent, node.id, label, propSummary(node.props, full or opts.props), geo,
    #extra > 0 and ("  [" .. table.concat(extra, ", ") .. "]") or "", flagText, hoverText))

  if full or opts.parts then
    for _, p in ipairs(node.parts or {}) do
      emit(indent .. "    . " .. partLine(p))
      for _, q in ipairs(p.parts or {}) do emit(indent .. "        . " .. partLine(q)) end
    end
  end

  local childBox = (region.type ~= "FontString" and region.type ~= "Texture") and b or parentBox
  -- Content of a scrolling container may sit outside it while scrolled away.
  -- A List clips and keeps a few rows just outside its edges (overscan).
  if node.scroll or node.host == "List" then childBox = nil end
  if childBox and childBox == b and PADDED[node.host] then
    local pad = paddingOf(node.props and node.props.padding)
    if pad then
      childBox = { left = b.left, top = b.top, right = b.right, bottom = b.bottom, w = b.w, h = b.h, pad = pad }
    end
  end
  for _, c in ipairs(node.children or {}) do walk(c, depth + 1, childBox, here, full) end
end

local function findNode(node, id)
  if node.id == id then return node end
  for _, c in ipairs(node.children or {}) do
    local f = findNode(c, id)
    if f then return f end
  end
end

local function walkFrame(info, depth)
  local indent = string.rep("  ", depth)
  emit(indent .. partLine(info))
  for _, p in ipairs(info.parts or {}) do walkFrame(p, depth + 1) end
end

-- Header
local c = snap.client or {}
emit(string.format("Snapshot %d/%d  %s  client %s (%s, interface %s)  %s", index, #snaps, snap.date or "?",
  tostring(c.version), tostring(c.build), tostring(c.interface), tostring(snap.fxui)))
emit(string.format("UI %sx%s at scale %s (FxUI x%s) on a %sx%s screen  theme %s  regions active %s / pooled %s / created %s",
  n2(snap.uiSize and snap.uiSize[1]), n2(snap.uiSize and snap.uiSize[2]), string.format("%.2f", snap.uiScale or 0), string.format("%.2f", snap.fxScale or 1),
  tostring(snap.screen and snap.screen[1]), tostring(snap.screen and snap.screen[2]), tostring(snap.theme),
  tostring(snap.stats and snap.stats.active), tostring(snap.stats and snap.stats.pooled), tostring(snap.stats and snap.stats.created)))

if snap.errors and #snap.errors > 0 then
  emit("")
  emit("Errors (" .. #snap.errors .. "):")
  for _, e in ipairs(snap.errors) do
    emit("  " .. os.date("%H:%M:%S", e.time or 0) .. "  " .. (e.message or ""):gsub("\n", "\n    "))
  end
end

if snap.hover and #snap.hover > 0 then
  emit("")
  emit("Under the mouse:")
  for _, h in ipairs(snap.hover) do
    emit(string.format("  %s %s%s", tostring(h.type), tostring(h.name or "<anonymous>"), h.node and (" -> node #" .. h.node) or ""))
  end
end

-- Root positions read from the top-left of UIParent.
local uiBox
if snap.uiSize then
  uiBox = { left = 0, top = snap.uiSize[2], right = snap.uiSize[1], bottom = 0, w = snap.uiSize[1], h = snap.uiSize[2] }
end

local pixelRect

-- A node's rect in screen pixels from the top-left of the game's client
-- area, for cropping a screenshot: x,y wxh (ImageMagick -crop WxH+X+Y).
pixelRect = function(node)
  while node and node.component do node = node.children and node.children[1] end
  local b = node and box(node.region)
  if not b or not snap.screen or not snap.uiSize then return nil end
  -- Rects are in the region's own scale: pixels per unit = scale * screenHeight / 768.
  local ppu = node.scale and (node.scale * snap.screen[2] / 768) or (snap.screen[2] / snap.uiSize[2])
  local x, y = b.left * ppu, snap.screen[2] - b.top * ppu
  return string.format("%d,%d %dx%d  (crop %dx%d+%d+%d)", x, y, b.w * ppu, b.h * ppu, b.w * ppu, b.h * ppu, x, y)
end

if snap.selected and not opts.node then
  for _, root in ipairs(snap.roots or {}) do
    local n = findNode(root.tree, snap.selected)
    if n then
      emit("")
      emit("Selected #" .. snap.selected .. " (picked in game)")
      local px = pixelRect(n)
      if px then emit("  screen pixels: " .. px) end
      collecting = false
      walk(n, 0, uiBox, "", true)
      collecting = true
    end
  end
end

for r, root in ipairs(snap.roots or {}) do
  local tree = root.tree
  if opts.node then
    local n = findNode(tree, opts.node)
    if n then
      emit("")
      emit("Node #" .. opts.node .. " (root " .. r .. ")")
      local px = pixelRect(n)
      if px then emit("  screen pixels: " .. px) end
      walk(n, 0, uiBox, "", true)
    end
  else
    emit("")
    emit("Root " .. r .. " in " .. tostring(root.parent))
    walk(tree, 0, uiBox, "", false)
  end
end

if opts.frames then
  for _, f in ipairs(snap.frames or {}) do
    emit("")
    emit("Frame " .. f.name .. (f.missing and " (not found)" or ""))
    if f.tree then walkFrame(f.tree, 1) end
  end
end

if not opts.node then
  emit("")
  if #issues == 0 then
    emit("No layout issues flagged.")
  else
    emit("Issues (" .. #issues .. "):")
    for _, s in ipairs(issues) do emit("  " .. s) end
  end
end

print(table.concat(out, "\n"))
