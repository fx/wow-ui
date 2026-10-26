local ADDON, ns = ...
local UI = ns.FxUI
if not UI then return end
local I = UI._internal

-- FxUI's own scale, on top of the game's UI scale: FxUI windows (and the
-- toast stack) are scaled by it, so their size on screen is
-- game UI scale x UI.scale.
UI.SCALE_MIN, UI.SCALE_MAX = 0.4, 2
UI.scale = UI.scale or 1

-- Top-level frames that follow UI.scale: frame -> true to keep its
-- on-screen top-left when the scale changes, false to just rescale.
I.scaled = I.scaled or setmetatable({}, { __mode = "k" })

function I.applyScale(frame, keepPosition)
  local s, old = UI.scale, frame:GetScale()
  if math.abs(old - s) < 0.0001 then return end
  local left, top = frame:GetLeft(), frame:GetTop()
  frame:SetScale(s)
  if keepPosition and left then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / s, top * old / s)
    if frame.fxAfterScale then frame.fxAfterScale(frame) end
  end
end

function I.followScale(frame, keepPosition)
  I.scaled[frame] = keepPosition and true or false
  I.applyScale(frame, keepPosition)
end

function I.unfollowScale(frame)
  I.scaled[frame] = nil
  frame:SetScale(1)
end

function UI.setScale(s)
  s = I.clamp(tonumber(s) or 1, UI.SCALE_MIN, UI.SCALE_MAX)
  s = math.floor(s * 100 + 0.5) / 100
  if s == UI.scale then return end
  UI.scale = s
  if I.db then I.db.scale = s end
  for frame, keep in pairs(I.scaled) do
    I.applyScale(frame, keep)
  end
  I.rerenderAll()
end

-- The standalone FxUI addon saves the scale and offers it in
-- Options > AddOns > FxUI. Embedded copies leave that to their host addon.
local function registerSettings()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.CreateSlider) then return end
  local category = Settings.RegisterVerticalLayoutCategory("FxUI")
  local setting = Settings.RegisterAddOnSetting(category, "FXUI_SCALE", "scale", I.db, "number", "Scale", 1)
  local options = Settings.CreateSliderOptions(UI.SCALE_MIN, UI.SCALE_MAX, 0.05)
  if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
      return string.format("%d%%", math.floor(value * 100 + 0.5))
    end)
  end
  Settings.CreateSlider(category, setting, options,
    "Size of every FxUI window, on top of the game's UI scale. Below 100% makes FxUI smaller than the game's minimum UI scale allows.")
  if setting.SetValueChangedCallback then
    setting:SetValueChangedCallback(function(_, value) UI.setScale(value) end)
  end

  -- Global theme: every FxUI window that does not choose its own.
  if Settings.CreateDropdown and Settings.CreateControlTextContainer then
    local themeSetting = Settings.RegisterAddOnSetting(category, "FXUI_THEME", "theme", I.db, "string", "Theme", "default")
    local function themeOptions()
      local container = Settings.CreateControlTextContainer()
      for _, t in ipairs(UI.listThemes()) do container:Add(t.name, t.title) end
      return container:GetData()
    end
    Settings.CreateDropdown(category, themeSetting, themeOptions,
      "The theme for every FxUI window that does not choose its own. Themes come from addons (FxUI_Theme_*).")
    if themeSetting.SetValueChangedCallback then
      themeSetting:SetValueChangedCallback(function(_, value)
        if UI.themes[value] then UI.setTheme(value) end
      end)
    end
  end
  Settings.RegisterAddOnCategory(category)
  I.settingsCategory = category
end

if ADDON == "FxUI" then
  I.on("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    FxUIDB = FxUIDB or {}
    I.db = FxUIDB
    UI.setScale(FxUIDB.scale or 1)
    registerSettings()
  end)
  -- Theme addons load after FxUI, so apply the saved theme once everything
  -- is loaded, or as soon as a late theme addon registers it.
  I.on("PLAYER_LOGIN", function()
    local saved = I.db and I.db.theme
    if saved and UI.themes[saved] and UI.themeName ~= saved then UI.setTheme(saved) end
  end)
  I.onThemesChanged = function()
    local saved = I.db and I.db.theme
    if saved and UI.themes[saved] and UI.themeName ~= saved and IsLoggedIn and IsLoggedIn() then
      UI.setTheme(saved)
    end
  end
end

function UI.openSettings()
  if I.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(I.settingsCategory:GetID())
  end
end
