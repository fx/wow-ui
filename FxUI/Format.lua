local _, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

local MINUS = "\226\136\146" -- U+2212

local function groupDigits(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
UI.groupDigits = groupDigits

local COIN_ICONS = {
  g = "Interface\\MoneyFrame\\UI-GoldIcon",
  s = "Interface\\MoneyFrame\\UI-SilverIcon",
  c = "Interface\\MoneyFrame\\UI-CopperIcon",
}

-- The denomination marker: a coin icon, a colored letter or a plain letter.
local function marker(letter, token, colored, icons)
  if icons then return "|T" .. COIN_ICONS[letter] .. ":0:0:2:0|t" end
  if colored then return "|cff" .. I.hexOf(token) .. letter .. "|r" end
  return letter
end

local function unit(n, letter, token, colored, icons)
  local digits = letter == "g" and groupDigits(n) or tostring(n)
  return digits .. marker(letter, token, colored, icons)
end

-- One decimal at most, without a trailing ".0".
local function oneDecimal(x)
  local s = string.format("%.1f", math.floor(x * 10) / 10)
  return (s:gsub("%.0$", ""))
end

-- The largest denomination only, for tight spaces: 7.4g, 124g, 12.3kg,
-- 45s, 4.5s, 56c. Rounds down, so it never overstates.
local function shortMoney(v, colored, icons)
  local letter, token, digits
  local g = v / 10000
  if g >= 1000 then
    letter, token, digits = "g", "coinGold", oneDecimal(g / 1000) .. "k"
  elseif g >= 100 then
    letter, token, digits = "g", "coinGold", groupDigits(math.floor(g))
  elseif g >= 1 then
    letter, token, digits = "g", "coinGold", oneDecimal(g)
  elseif v >= 1000 then
    letter, token, digits = "s", "coinSilver", tostring(math.floor(v / 100))
  elseif v >= 100 then
    letter, token, digits = "s", "coinSilver", oneDecimal(v / 100)
  else
    letter, token, digits = "c", "coinCopper", tostring(v)
  end
  return digits .. marker(letter, token, colored, icons)
end

-- Copper to "12g 34s 56c". Zero denominations are left out; zero reads "0c".
-- opts.compact: only gold at 100g and above. opts.short: the largest
-- denomination with one decimal (7.4g, 45s), for charts and legends.
-- opts.signed: "+" on positives. opts.colored: denomination letters in
-- their coin colors. opts.icons: coin icons instead of letters (default:
-- the active theme's money style).
function UI.formatMoney(copper, opts)
  opts = opts or {}
  copper = tonumber(copper) or 0
  local neg = copper < 0
  local v = math.floor(math.abs(copper) + 0.5)
  local icons = opts.icons
  if icons == nil then icons = I.theme().money == "icons" end
  if opts.short then
    local out = shortMoney(v, opts.colored, icons)
    if neg and v > 0 then return MINUS .. out end
    if opts.signed and v > 0 then return "+" .. out end
    return out
  end
  local g = math.floor(v / 10000)
  local s = math.floor(v / 100) % 100
  local c = v % 100
  local colored = opts.colored

  local parts = {}
  if g > 0 then parts[#parts + 1] = unit(g, "g", "coinGold", colored, icons) end
  if not (opts.compact and g >= 100) then
    if s > 0 then parts[#parts + 1] = unit(s, "s", "coinSilver", colored, icons) end
    if c > 0 or #parts == 0 then parts[#parts + 1] = unit(c, "c", "coinCopper", colored, icons) end
  end

  local out = table.concat(parts, " ")
  if neg and v > 0 then
    out = MINUS .. out
  elseif opts.signed and v > 0 then
    out = "+" .. out
  end
  return out
end
