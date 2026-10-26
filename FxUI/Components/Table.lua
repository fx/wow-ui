local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local CHEVRON_W = 8

---------------------------------------------------------------------------
-- Header cell: a column title that sorts on click
---------------------------------------------------------------------------

-- Skin contract: skins.HeaderCell.paint(button, props, state) with state =
-- { hover, active }; button.label, .up, .down (chevron lines) exist.
-- metrics.HeaderCell = { height }.
local function paintHeader(b)
  local node = b.fxNode
  if not node then return end
  local prevTheme = I.enter(node)
  local p = node.el.props
  local active = p.sortDir ~= nil
  local skin = I.skin("HeaderCell")
  if skin and skin.paint then
    skin.paint(b, p, { hover = b.fxHover, active = active })
  else
    I.clearSkin(b)
  end
  if not (skin and skin.paint) then
    local color = (active or (b.fxHover and p.sortable)) and "text" or "muted"
    b.label:SetTextColor(I.rgba(color))
  end
  local r, g, bl = I.rgba(active and "gold" or "muted")
  b.up:SetColorTexture(r, g, bl, 1)
  b.down:SetColorTexture(r, g, bl, 1)
  b.up:SetShown(active)
  b.down:SetShown(active)
  I.leave(prevTheme)
end

-- Draw the chevron pointing up (ascending) or down (descending).
local function placeChevron(b, dir, x)
  local h = 3
  local tip = dir == "asc" and h or -h
  b.up:SetStartPoint("LEFT", b, x, -tip / 2)
  b.up:SetEndPoint("LEFT", b, x + CHEVRON_W / 2, tip / 2)
  b.down:SetStartPoint("LEFT", b, x + CHEVRON_W / 2, tip / 2)
  b.down:SetEndPoint("LEFT", b, x + CHEVRON_W, -tip / 2)
end

-- Props: text, align (LEFT|RIGHT), sortable, sortDir (asc|desc|nil), onSort().
I.defineHost("HeaderCell", {
  create = function(holder)
    local b = CreateFrame("Button", nil, holder)
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetWordWrap(false)
    b.up = b:CreateLine(nil, "OVERLAY")
    b.down = b:CreateLine(nil, "OVERLAY")
    b.up:SetThickness(1.5)
    b.down:SetThickness(1.5)
    b:SetScript("OnEnter", function(self) self.fxHover = true; paintHeader(self) end)
    b:SetScript("OnLeave", function(self) self.fxHover = false; paintHeader(self) end)
    b:SetScript("OnClick", function(self)
      local node = self.fxNode
      if not node then return end
      local p = node.el.props
      if p.sortable and p.onSort then p.onSort() end
    end)
    return b
  end,
  update = function(node, p)
    local b = node.region
    I.setText(b.label, p.text, "label")
    b:EnableMouse(p.sortable and true or false)
    paintHeader(b)
  end,
  measure = function(node)
    local m = I.metrics("HeaderCell")
    local w, h = I.measureString(node.region.label)
    return w + 4 + CHEVRON_W + (m.pad or 0) * 2, m.height or math.max(h, 16)
  end,
  layout = function(node, w)
    local b = node.region
    local p = node.el.props
    local pad = I.metrics("HeaderCell").pad or 0
    local labelW = I.measureString(b.label)
    b.label:ClearAllPoints()
    local dir = p.sortDir or "asc"
    if p.align == "RIGHT" then
      b.label:SetPoint("RIGHT", b, "RIGHT", -pad, 0)
      placeChevron(b, dir, math.max(w - pad - labelW - 4 - CHEVRON_W, 0))
    else
      b.label:SetPoint("LEFT", b, "LEFT", pad, 0)
      placeChevron(b, dir, pad + labelW + 4)
    end
  end,
  release = function(node)
    node.region.fxHover = false
  end,
})

---------------------------------------------------------------------------
-- Table: header plus virtualized rows, sortable by column
---------------------------------------------------------------------------

local function valueOf(col, item)
  if col.sortValue then return col.sortValue(item) end
  if type(item) == "table" then return item[col.key] end
end

-- Stable sort; nil (and NaN) values last in either direction. A column
-- whose values are all numbers or all strings compares them as such
-- (strings case-insensitively); any other column compares every value as a
-- string, decided once for the whole column so the order is consistent.
local function sortItems(items, col, desc)
  local decorated, kind = {}, nil
  local asStrings = false
  for i, item in ipairs(items) do
    local v = valueOf(col, item)
    if v ~= v then v = nil end
    decorated[i] = { item = item, index = i, value = v }
    if v ~= nil then
      local t = type(v)
      if (t ~= "number" and t ~= "string") or (kind and kind ~= t) then asStrings = true end
      kind = t
    end
  end
  for _, d in ipairs(decorated) do
    local v = d.value
    if v ~= nil then
      if asStrings then v = tostring(v) end
      if type(v) == "string" then v = v:lower() end
      d.value = v
    end
  end
  table.sort(decorated, function(a, b)
    local va, vb = a.value, b.value
    if va == nil or vb == nil then
      if va == nil and vb == nil then return a.index < b.index end
      return vb == nil
    end
    if va == vb then return a.index < b.index end
    if desc then return va > vb end
    return va < vb
  end)
  local out = {}
  for i, d in ipairs(decorated) do out[i] = d.item end
  return out
end
UI.sortItems = sortItems

local function cellProps(col, child)
  return {
    width = col.width,
    flex = col.flex,
    minWidth = col.minWidth,
    justify = col.align == "RIGHT" and "end" or nil,
    align = "center",
    child,
  }
end

-- Props: columns = { { key, title, width | flex, align (LEFT|RIGHT),
-- sortable (default true), sortValue(item), render(item, i) -> element } },
-- items, key, rowHeight, striped, selected, onSelect(item, i, key),
-- defaultSort = { key, desc }, or controlled: sort = { key, desc } with
-- onSort(key, desc). Other props pass to the list (empty, highlight, ...).
UI.Table = I.defineComponent("Table", {
  init = function(ctx, props)
    local d = props.defaultSort
    ctx.state.sortKey = d and d.key
    ctx.state.sortDesc = d and d.desc or false
  end,
  render = function(props, ctx)
    local columns = props.columns or {}
    local sortKey, sortDesc = ctx.state.sortKey, ctx.state.sortDesc
    if props.sort then sortKey, sortDesc = props.sort.key, props.sort.desc end

    local sortCol
    for _, col in ipairs(columns) do
      if col.key == sortKey then sortCol = col end
    end

    -- Re-sort only when something the order depends on changes: the items
    -- (table and count), the sort key, the direction, or the sorted column's
    -- sortValue (a new function may order the same items differently).
    local items = props.items or {}
    local memo = ctx.sorted
    local by = sortCol and sortCol.sortValue
    if not sortCol then
      ctx.sorted = nil
    elseif not memo or memo.items ~= items or memo.key ~= sortKey or memo.desc ~= sortDesc
        or memo.n ~= #items or memo.by ~= by then
      ctx.sorted = { items = items, key = sortKey, desc = sortDesc, n = #items, by = by,
        list = sortItems(items, sortCol, sortDesc) }
    end
    local rows = ctx.sorted and ctx.sorted.list or items

    local gap = props.gap or 12
    local header = {}
    for i, col in ipairs(columns) do
      local sortable = col.sortable ~= false
      header[i] = UI.HStack(cellProps(col, UI.HeaderCell {
        flex = 1,
        text = col.title or "",
        align = col.align,
        sortable = sortable,
        sortDir = col.key == sortKey and (sortDesc and "desc" or "asc") or nil,
        onSort = function()
          local desc = false
          if col.key == sortKey then desc = not sortDesc end
          if props.onSort then
            props.onSort(col.key, desc)
          else
            ctx:setState({ sortKey = col.key, sortDesc = desc })
          end
        end,
      }))
    end

    local function renderRow(item, index)
      local cells = { gap = gap, align = "stretch" }
      for _, col in ipairs(columns) do
        local child
        if col.render then
          child = col.render(item, index)
        else
          local v = valueOf(col, item)
          child = UI.Text { text = v == nil and "" or tostring(v), justify = col.align or "LEFT", flex = 1 }
        end
        cells[#cells + 1] = UI.HStack(cellProps(col, child))
      end
      return UI.HStack(cells)
    end

    return UI.VStack {
      gap = 0,
      UI.HStack { gap = gap, padding = { 0, 12 + I.scrollGutter(), 0, 12 }, height = props.headerHeight or 34, align = "center", header },
      UI.Divider {},
      UI.List {
        flex = 1,
        items = rows,
        key = props.key,
        rowHeight = props.rowHeight,
        striped = props.striped,
        selected = props.selected,
        onSelect = props.onSelect,
        highlight = props.highlight,
        empty = props.empty,
        scrollbar = "always",
        render = renderRow,
      },
    }
  end,
})
