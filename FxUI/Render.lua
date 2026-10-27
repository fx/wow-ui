local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local HUGE = math.huge
local ELEMENT = "__fxElement"

---------------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------------

-- Array part of a props table, in order, skipping nil/false and flattening
-- plain arrays (so `UI.map(...)` results can be passed as a child).
local function collectChildren(t, out)
  local n = 0
  for k in pairs(t) do
    if type(k) == "number" and k > n then n = k end
  end
  for i = 1, n do
    local v = t[i]
    if type(v) == "table" then
      if v[ELEMENT] then
        out[#out + 1] = v
      else
        collectChildren(v, out)
      end
    end
  end
  return out
end

local function makeElement(typ, t)
  t = t or {}
  local props = {}
  for k, v in pairs(t) do
    if type(k) ~= "number" then props[k] = v end
  end
  -- Only a string or number key is an identity: a component may take a
  -- function `key` (a list's row key) that is a new closure every render.
  local key = props.key
  if type(key) ~= "string" and type(key) ~= "number" then key = nil end
  return { [ELEMENT] = true, type = typ, props = props, children = collectChildren(t, {}), key = key }
end
I.makeElement = makeElement

function UI.isElement(v)
  return type(v) == "table" and v[ELEMENT] == true
end

function UI.map(list, fn)
  local out = {}
  for i, v in ipairs(list or {}) do
    out[#out + 1] = fn(v, i)
  end
  return out
end

-- Built-in element types by name. An upgrade keeps these tables: a newer
-- copy refills each one in place instead of replacing it, so nodes and
-- elements the older copy made keep the same type identity (the reconciler
-- matches types by table) and run the newer copy's definition.
I.hosts = I.hosts or {}
I.components = I.components or {}

local function adopt(existing, def)
  if not existing or existing == def then return def end
  I.wipe(existing)
  for k, v in pairs(def) do existing[k] = v end
  return existing
end

-- A host is a built-in element type backed by a pooled client region.
function I.defineHost(name, def)
  def = adopt(I.hosts[name], def)
  def.name = name
  def.isHost = true
  I.hosts[name] = def
  UI[name] = function(t) return makeElement(def, t) end
  return def
end

local componentMeta = {
  __call = function(def, t) return makeElement(def, t) end,
}

local function componentDef(name, spec)
  local def = type(spec) == "function" and { render = spec } or spec
  assert(type(def.render) == "function", "FxUI: component needs a render function")
  def.name = name
  def.isComponent = true
  return def
end

-- UI.component(name, render) or UI.component(name, { init, render, mounted, unmounted })
function UI.component(name, spec)
  return setmetatable(componentDef(name, spec), componentMeta)
end

-- A built-in component: like UI.component, but kept across upgrades by name
-- like a host. Consumer components are theirs to keep, so UI.component
-- registers nothing.
function I.defineComponent(name, spec)
  local def = adopt(I.components[name], componentDef(name, spec))
  I.components[name] = def
  return setmetatable(def, componentMeta)
end

---------------------------------------------------------------------------
-- Region pools
---------------------------------------------------------------------------

I.holder = I.holder or CreateFrame("Frame")
I.holder:Hide()
I.pools = I.pools or {}
I.created = I.created or {}
I.active = I.active or {}

local function acquire(host, parent)
  local pool = I.pools[host.name]
  local region = pool and table.remove(pool)
  if not region then
    region = host.create(I.holder)
    I.created[host.name] = (I.created[host.name] or 0) + 1
  end
  region:SetParent(parent)
  if region.SetFrameLevel and parent.GetFrameLevel then
    region:SetFrameStrata(parent:GetFrameStrata())
    region:SetFrameLevel(parent:GetFrameLevel() + 1)
  end
  region:ClearAllPoints()
  region:Show()
  I.active[host.name] = (I.active[host.name] or 0) + 1
  return region
end

local function releaseRegion(host, region)
  region:Hide()
  region:ClearAllPoints()
  region:SetParent(I.holder)
  local pool = I.pools[host.name]
  if not pool then
    pool = {}
    I.pools[host.name] = pool
  end
  pool[#pool + 1] = region
  I.active[host.name] = I.active[host.name] - 1
end

-- Region counts per host: created (ever), active (mounted), pooled (free).
function UI.stats()
  local out, total = {}, { created = 0, active = 0, pooled = 0 }
  for name, n in pairs(I.created) do
    local pooled = I.pools[name] and #I.pools[name] or 0
    out[name] = { created = n, active = I.active[name] or 0, pooled = pooled }
    total.created = total.created + n
    total.active = total.active + (I.active[name] or 0)
    total.pooled = total.pooled + pooled
  end
  return out, total
end

---------------------------------------------------------------------------
-- Component context
---------------------------------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

function Ctx:setState(patch)
  if type(patch) == "function" then patch = patch(self.state, self.props) end
  if patch then
    for k, v in pairs(patch) do self.state[k] = v end
  end
  if self.node.alive then I.invalidate(self.node) end
end

function Ctx:forceUpdate()
  if self.node.alive then I.invalidate(self.node) end
end

function Ctx:onUnmount(fn)
  self.cleanups = self.cleanups or {}
  self.cleanups[#self.cleanups + 1] = fn
end

-- C_Timer.After that does nothing once the component is gone.
function Ctx:after(seconds, fn)
  local node = self.node
  C_Timer.After(seconds, function()
    if node.alive then I.safecall(fn) end
  end)
end

function Ctx:isMounted()
  return self.node.alive
end

---------------------------------------------------------------------------
-- Reconciler
---------------------------------------------------------------------------

I.tick = I.tick or 0

local createNode, updateNode, releaseNode, reconcileChildren

-- A node's theme: its own `theme` prop (a registered name or a definition
-- table), else its parent's, else the root's; nil means the global theme.
local function themeOf(el, parent, root)
  local own = el.props.theme
  if own ~= nil then return I.resolve(own) end
  if parent then return parent.theme end
  return root and root.theme
end
I.themeOf = themeOf

local function renderComponent(node)
  local ctx = node.ctx
  ctx.props = node.el.props
  ctx.theme = node.theme or I.global
  local prevTheme = I.enter(node)
  node.renderTick = I.tick
  node.renders = (node.renders or 0) + 1
  local ok, childEl = I.safecall(node.def.render, ctx.props, ctx)
  I.leave(prevTheme)
  if not ok or not UI.isElement(childEl) then childEl = nil end

  local child = node.child
  if childEl then
    local key = childEl.key or "c"
    if child and child.el.type == childEl.type and child.key == key then
      updateNode(child, childEl)
    else
      if child then releaseNode(child) end
      node.child = createNode(childEl, key, node, node.frame, node.root)
    end
  elseif child then
    releaseNode(child)
    node.child = nil
  end
end

local function contentFrame(node)
  local host = node.host
  if host.content then return host.content(node) end
  return node.region
end

createNode = function(el, key, parent, frame, root)
  local node = {
    el = el,
    key = key,
    parent = parent,
    frame = frame,
    root = root,
    depth = (parent and parent.depth or 0) + 1,
    alive = true,
  }
  node.theme = themeOf(el, parent, root)
  local typ = el.type
  if typ.isComponent then
    node.def = typ
    node.ctx = setmetatable({ props = el.props, state = {}, node = node, root = root }, Ctx)
    if typ.init then I.safecall(typ.init, node.ctx, el.props) end
    renderComponent(node)
    if typ.mounted then I.safecall(typ.mounted, node.ctx) end
  else
    node.host = typ
    local prevTheme = I.enter(node)
    if typ.create then
      node.region = acquire(typ, frame)
      node.region.fxNode = node
    end
    if typ.init then typ.init(node) end
    typ.update(node, el.props, nil)
    I.leave(prevTheme)
    if typ.container then
      reconcileChildren(node, contentFrame(node), el.children)
    end
    if el.props.ref and node.region then I.safecall(el.props.ref, node.region) end
  end
  return node
end

updateNode = function(node, el)
  local old = node.el.props
  node.el = el
  node.theme = themeOf(el, node.parent, node.root)
  if node.def then
    renderComponent(node)
  else
    local prevTheme = I.enter(node)
    node.host.update(node, el.props, old)
    I.leave(prevTheme)
    if node.host.container then
      reconcileChildren(node, contentFrame(node), el.children)
    end
  end
end

releaseNode = function(node)
  if not node.alive then return end
  node.alive = false
  if node.def then
    if node.def.unmounted then I.safecall(node.def.unmounted, node.ctx) end
    local cleanups = node.ctx.cleanups
    if cleanups then
      for i = 1, #cleanups do I.safecall(cleanups[i]) end
    end
    if node.child then releaseNode(node.child) end
  else
    if node.children then
      for i = 1, #node.children do releaseNode(node.children[i]) end
    end
    if node.host.release then node.host.release(node) end
    if node.region then
      node.region.fxNode = nil
      releaseRegion(node.host, node.region)
    end
  end
end

-- Match new child elements to existing child nodes by key and type; reuse
-- matches, create the rest, release what is left over. `field` names the list
-- on `parent` that holds the children (default "children").
reconcileChildren = function(parent, frame, els, field)
  field = field or "children"
  local old = parent[field]
  local byKey = {}
  if old then
    for i = 1, #old do
      local n = old[i]
      if byKey[n.key] then releaseNode(byKey[n.key]) end
      byKey[n.key] = n
    end
  end
  local new = {}
  for i = 1, #els do
    local el = els[i]
    local key = el.key ~= nil and ("k:" .. tostring(el.key)) or ("i:" .. i)
    local n = byKey[key]
    if n and n.el.type == el.type then
      byKey[key] = nil
      updateNode(n, el)
    else
      n = createNode(el, key, parent, frame, parent.root)
    end
    new[i] = n
  end
  for _, n in pairs(byKey) do releaseNode(n) end
  parent[field] = new
  return new
end

I.createNode, I.updateNode, I.releaseNode, I.reconcileChildren = createNode, updateNode, releaseNode, reconcileChildren

---------------------------------------------------------------------------
-- Layout: measure (bottom-up natural size) and place (top-down)
---------------------------------------------------------------------------

-- Layout props may sit on a component element too; they win over its child's.
local function layoutProp(node, name)
  while node do
    local v = node.el.props[name]
    if v ~= nil then return v end
    if node.def then
      node = node.child
    else
      local host = node.host
      if name == "flex" then
        local d = host.defaultFlex
        if type(d) == "function" then return d(node) end
        return d
      end
      if name == "alignSelf" then return host.alignSelf end
      return nil
    end
  end
end
I.layoutProp = layoutProp

local function bound(v, lo, hi)
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

-- A node's natural size within maxW x maxH. The box props (width, height,
-- minWidth, minHeight, maxWidth) are resolved through a component chain, a
-- component's own winning over its rendered child's, and bound the space the
-- content is measured in, so content is measured at the width it will get.
-- exact ("w" or "h") makes the offer along that axis the node's size there,
-- whatever its own props say: a flexible child measured at its share.
function I.measure(node, maxW, maxH, exact)
  local w, h = layoutProp(node, "width"), layoutProp(node, "height")
  local minW, minH = layoutProp(node, "minWidth"), layoutProp(node, "minHeight")
  local maxWidth = layoutProp(node, "maxWidth")
  if exact == "w" then
    w, minW, maxWidth = maxW, nil, nil
  elseif exact == "h" then
    h, minH = maxH, nil
  end
  if w and h then return bound(w, minW, maxWidth), bound(h, minH) end
  local host = node
  while host and host.def do host = host.child end
  local nw, nh = 0, 0
  if host and host.host.measure then
    local prevTheme = I.enter(host)
    nw, nh = host.host.measure(host, bound(w or maxW or HUGE, minW, maxWidth), bound(h or maxH or HUGE, minH))
    I.leave(prevTheme)
  end
  return bound(w or nw, minW, maxWidth), bound(h or nh, minH)
end

function I.place(node, x, y, w, h)
  if node.def then
    if node.child then I.place(node.child, x, y, w, h) end
    return
  end
  local host = node.host
  local prevTheme = I.enter(node)
  if host.floating then
    if host.layoutSelf then host.layoutSelf(node) end
    node.x, node.y = nil, nil
    node.w, node.h = node.region:GetSize()
    I.leave(prevTheme)
    return
  end
  node.x, node.y, node.w, node.h = x, y, w, h
  local r = node.region
  if r then
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", node.frame, "TOPLEFT", x, -y)
    r:SetSize(math.max(w, 0), math.max(h, 0))
  end
  if host.layout then host.layout(node, w, h) end
  I.leave(prevTheme)
end

-- CSS-style shorthand: n | {v, h} | {t, h, b} | {t, r, b, l}
function I.padding(p)
  if not p then return 0, 0, 0, 0 end
  if type(p) == "number" then return p, p, p, p end
  local n = #p
  if n == 1 then return p[1], p[1], p[1], p[1] end
  if n == 2 then return p[1], p[2], p[1], p[2] end
  if n == 3 then return p[1], p[2], p[3], p[2] end
  return p[1], p[2], p[3], p[4]
end

-- Measure a stack child. A Spacer's fixed size runs along the stack's main
-- axis only.
local function measureChild(c, horizontal, maxW, maxH, exact)
  if c.host and c.host.name == "Spacer" then
    local size = c.el.props.size or 0
    if horizontal then return size, 0 end
    return 0, size
  end
  return I.measure(c, maxW, maxH, exact)
end

-- A wrapping row: split children into lines no wider than innerW.
local function wrapLines(kids, gap, innerW, innerH)
  local lines, line, used = {}, nil, 0
  for i = 1, #kids do
    local c = kids[i]
    local cw, ch = measureChild(c, true, innerW, innerH)
    if line and used + gap + cw > innerW then line = nil end
    if line then
      used = used + gap
    else
      line = { items = {}, w = 0, h = 0 }
      lines[#lines + 1] = line
      used = 0
    end
    line.items[#line.items + 1] = { node = c, w = cw, h = ch }
    used = used + cw
    line.w = used
    if ch > line.h then line.h = ch end
  end
  return lines
end

local function wrapMeasure(kids, props, maxW, maxH)
  local t, r, b, l = I.padding(props.padding)
  local gap = props.gap or 0
  local rowGap = props.rowGap or gap
  local lines = wrapLines(kids, gap, math.max((maxW or HUGE) - l - r, 0), math.max((maxH or HUGE) - t - b, 0))
  local w, h = 0, 0
  for i, line in ipairs(lines) do
    if line.w > w then w = line.w end
    h = h + line.h + (i > 1 and rowGap or 0)
  end
  return w + l + r, h + t + b
end

local function wrapLayout(kids, props, w, h)
  local t, r, b, l = I.padding(props.padding)
  local gap = props.gap or 0
  local rowGap = props.rowGap or gap
  local innerW, innerH = math.max(w - l - r, 0), math.max(h - t - b, 0)
  local align = props.align or "center"
  local justify = props.justify or "start"
  local y = t
  for _, line in ipairs(wrapLines(kids, gap, innerW, innerH)) do
    local free = innerW - line.w
    local x, between = l, gap
    if free > 0 then
      if justify == "center" then
        x = l + free / 2
      elseif justify == "end" then
        x = l + free
      elseif justify == "between" and #line.items > 1 then
        between = gap + free / (#line.items - 1)
      end
    end
    for _, item in ipairs(line.items) do
      local a = layoutProp(item.node, "alignSelf") or align
      local cs, co = item.h, 0
      if a == "stretch" then
        cs = line.h
      elseif a == "center" then
        co = (line.h - cs) / 2
      elseif a == "end" then
        co = line.h - cs
      end
      I.place(item.node, x, y + co, item.w, cs)
      x = x + item.w + between
    end
    y = y + line.h + rowGap
  end
end

-- A child's minimum along a stack's main axis: minWidth in a row, minHeight
-- in a column, 0 when unset. The other axis's minimum never stands in.
local function mainMin(c, horizontal)
  local m
  if horizontal then
    m = layoutProp(c, "minWidth")
  else
    m = layoutProp(c, "minHeight")
  end
  return m or 0
end

-- Main-axis sizes of a stack's children inside an innerW x innerH box: the
-- one computation both measuring and placing use, so a stack is measured
-- exactly as it will be placed. Fixed children get their natural size, each
-- within what the children before it and the gaps between them leave (a
-- flexible child counting at its minimum); flexible children share what the
-- fixed children and gaps leave, in proportion to their flex, never below
-- their minimum (a child held at its minimum leaves the rest to the others),
-- and are measured at that share. Along an unbounded main axis (measuring
-- with no limit) a flexible child keeps its minimum and is measured without
-- a limit. Returns mains, crosses, flexes, totalFlex and the free space.
local function stackSizes(kids, props, horizontal, innerW, innerH)
  local innerMain = horizontal and innerW or innerH
  local gap = props.gap or 0
  local n = #kids
  local mains, crosses, flexes = {}, {}, {}
  local used, reserved, totalFlex = 0, 0, 0

  for i = 1, n do
    local c = kids[i]
    local flex = (not props.noFlex and layoutProp(c, "flex")) or 0
    flexes[i] = flex
    if flex > 0 then
      totalFlex = totalFlex + flex
      mains[i] = mainMin(c, horizontal)
      reserved = reserved + mains[i]
    else
      local left = math.max(innerMain - used - reserved - gap * (i - 1), 0)
      local cw, ch
      if horizontal then
        cw, ch = measureChild(c, true, left, innerH)
        mains[i], crosses[i] = cw, ch
      else
        cw, ch = measureChild(c, false, innerW, left)
        mains[i], crosses[i] = ch, cw
      end
      used = used + mains[i]
    end
  end

  local free = innerMain - used - gap * math.max(n - 1, 0)
  if totalFlex > 0 then
    local unbounded = free >= HUGE / 2
    if not unbounded then
      -- A child whose proportional share falls below its minimum keeps the
      -- minimum; the others share what is left, until every share holds.
      local held, left, flexLeft = {}, math.max(free, 0), totalFlex
      local changed = true
      while changed do
        changed = false
        for i = 1, n do
          if flexes[i] > 0 and not held[i] and left * flexes[i] / flexLeft < mains[i] then
            held[i], changed = true, true
            left, flexLeft = left - mains[i], flexLeft - flexes[i]
          end
        end
      end
      for i = 1, n do
        if flexes[i] > 0 and not held[i] then mains[i] = left * flexes[i] / flexLeft end
      end
    end
    for i = 1, n do
      if flexes[i] > 0 then
        local m = mains[i]
        local cw, ch
        if horizontal then
          cw, ch = measureChild(kids[i], true, unbounded and innerW or m, innerH, not unbounded and "w" or nil)
        else
          cw, ch = measureChild(kids[i], false, innerW, unbounded and innerH or m, not unbounded and "h" or nil)
        end
        crosses[i] = horizontal and ch or cw
      end
    end
  end
  return mains, crosses, flexes, totalFlex, free
end

-- Natural size of a stack of child nodes: fixed children at their natural
-- size and flexible ones at their minimum along the main axis; across it,
-- the largest child, each measured as stackSizes places it.
function I.stackMeasure(kids, props, horizontal, maxW, maxH)
  if horizontal and props.wrap then return wrapMeasure(kids, props, maxW, maxH) end
  local t, r, b, l = I.padding(props.padding)
  local gap = props.gap or 0
  local innerW, innerH = math.max((maxW or HUGE) - l - r, 0), math.max((maxH or HUGE) - t - b, 0)
  local mains, crosses, flexes = stackSizes(kids, props, horizontal, innerW, innerH)
  local main, cross = 0, 0
  for i = 1, #kids do
    if flexes[i] > 0 then
      main = main + mainMin(kids[i], horizontal)
    else
      main = main + mains[i]
    end
    if crosses[i] > cross then cross = crosses[i] end
  end

  main = main + gap * math.max(#kids - 1, 0)
  if horizontal then return main + l + r, cross + t + b end
  return cross + l + r, main + t + b
end

-- Size and position child nodes inside a w x h box.
function I.stackLayout(kids, props, horizontal, w, h)
  if horizontal and props.wrap then return wrapLayout(kids, props, w, h) end
  local t, r, b, l = I.padding(props.padding)
  local gap = props.gap or 0
  local innerW, innerH = math.max(w - l - r, 0), math.max(h - t - b, 0)
  local innerCross = horizontal and innerH or innerW
  local n = #kids
  local mains, crosses, _, totalFlex, free = stackSizes(kids, props, horizontal, innerW, innerH)
  local offset, between = 0, gap
  if totalFlex == 0 and free > 0 then
    local justify = props.justify or "start"
    if justify == "center" then
      offset = free / 2
    elseif justify == "end" then
      offset = free
    elseif justify == "between" and n > 1 then
      between = gap + free / (n - 1)
    end
  end

  local align = props.align or (horizontal and "center" or "stretch")
  local pos = offset
  for i = 1, n do
    local c = kids[i]
    local a = layoutProp(c, "alignSelf") or align
    local cs = crosses[i] or 0
    local co = 0
    if a == "stretch" then
      cs = innerCross
    else
      if cs > innerCross then cs = innerCross end
      if a == "center" then
        co = (innerCross - cs) / 2
      elseif a == "end" then
        co = innerCross - cs
      end
    end
    local m = mains[i]
    if horizontal then
      I.place(c, l + pos, t + co, m, cs)
    else
      I.place(c, l + co, t + pos, cs, m)
    end
    pos = pos + m + between
  end
end

---------------------------------------------------------------------------
-- Scheduler: batch state changes into one render per frame
---------------------------------------------------------------------------

local dirtyNodes, dirtyRoots = {}, {}
local driver = CreateFrame("Frame")
local scheduled = false

local function flush()
  driver:SetScript("OnUpdate", nil)
  scheduled = false
  I.tick = I.tick + 1

  local list = {}
  for node in pairs(dirtyNodes) do list[#list + 1] = node end
  I.wipe(dirtyNodes)
  table.sort(list, function(a, b) return a.depth < b.depth end)
  for i = 1, #list do
    local node = list[i]
    if node.alive and node.renderTick ~= I.tick then
      renderComponent(node)
      dirtyRoots[node.root] = true
    end
  end

  local roots = {}
  for root in pairs(dirtyRoots) do roots[#roots + 1] = root end
  I.wipe(dirtyRoots)
  for i = 1, #roots do
    if roots[i].alive then I.safecall(roots[i].layout, roots[i]) end
  end
end

function I.schedule()
  if not scheduled then
    scheduled = true
    driver:SetScript("OnUpdate", flush)
  end
end

function I.invalidate(node)
  dirtyNodes[node] = true
  I.schedule()
end

function I.requestLayout(root)
  if root and root.alive then
    dirtyRoots[root] = true
    I.schedule()
  end
end

-- Run pending renders now instead of on the next frame.
function UI.flush()
  if scheduled then flush() end
end

---------------------------------------------------------------------------
-- Roots
---------------------------------------------------------------------------

I.roots = I.roots or {}

local Root = {}
Root.__index = Root
-- Roots an older copy mounted take this copy's methods.
for root in pairs(I.roots) do setmetatable(root, Root) end

local function onParentSize(frame)
  for root in pairs(I.roots) do
    if root.frame == frame then I.requestLayout(root) end
  end
end

-- Mount an element into a frame. The element fills the frame, except a
-- floating element (Window) which positions itself.
-- opts.theme: a registered theme name or a theme definition for the whole
-- tree (default: the global theme). Any element can also set `theme`.
function UI.mount(frame, el, opts)
  assert(UI.isElement(el), "FxUI: mount needs an element")
  local root = setmetatable({ frame = frame, el = el, alive = true }, Root)
  -- Keep the reference, not just the resolved theme, so an update picks up a
  -- re-registered theme.
  root.themeRef = opts and opts.theme
  if root.themeRef ~= nil then root.theme = I.resolve(root.themeRef) end
  root.node = createNode(el, "root", nil, frame, root)
  I.roots[root] = true
  if not frame.fxSizeHooked then
    frame.fxSizeHooked = true
    frame:HookScript("OnSizeChanged", onParentSize)
  end
  root:layout()
  return root
end

function Root:update(el)
  if not self.alive then return end
  self.el = el or self.el
  I.tick = I.tick + 1
  if self.themeRef ~= nil then self.theme = I.resolve(self.themeRef) end
  local node = self.node
  if node and node.el.type == self.el.type and node.el.key == self.el.key then
    updateNode(node, self.el)
  else
    if node then releaseNode(node) end
    self.node = createNode(self.el, "root", nil, self.frame, self)
  end
  self:layout()
end

function Root:layout()
  if not self.alive or not self.node then return end
  local w, h = self.frame:GetSize()
  I.place(self.node, 0, 0, w or 0, h or 0)
end

function Root:unmount()
  if not self.alive then return end
  self.alive = false
  I.roots[self] = nil
  if self.node then releaseNode(self.node) end
  self.node = nil
end

function I.rerenderAll()
  local list = {}
  for root in pairs(I.roots) do list[#list + 1] = root end
  for i = 1, #list do I.safecall(list[i].update, list[i]) end
end
