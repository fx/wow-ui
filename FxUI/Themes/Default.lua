local _, ns = ...
local UI = ns.FxUI
if not UI then return end

-- The built-in theme every other theme inherits from. It stays in the core
-- library so FxUI works with no theme addon installed. Notes: AGENTS.md.
UI.themes = UI.themes or {}

UI.themes.default = {
  name = "default",
  title = "FxUI Dark",
  base = false,
  colors = {
    ground = "#0F1114",
    panel = "#171A1F",
    raised = "#1F232A",
    line = "#2A2F37",
    text = "#E7E3D6",
    muted = "#9AA0A8",
    gold = "#E2B04A",
    onGold = "#1A1406",
    info = "#5AA9E6",
    up = "#4CC38A",
    down = "#F07167",
    warn = "#F2B66B",

    poor = "#9D9D9D",
    common = "#FFFFFF",
    uncommon = "#1EFF00",
    rare = "#4FA3FF",
    epic = "#B86BFF",
    legendary = "#FF8000",

    coinGold = "#FFD100",
    coinSilver = "#C7C7CF",
    coinCopper = "#EDA55F",
  },
  fonts = {
    display = { file = "BarlowCondensed-SemiBold.ttf", size = 28 },
    title = { file = "Inter-SemiBold.ttf", size = 18 },
    body = { file = "Inter-Regular.ttf", size = 13 },
    strong = { file = "Inter-SemiBold.ttf", size = 13 },
    label = { file = "Inter-SemiBold.ttf", size = 11, caps = true },
    mono = { file = "JetBrainsMono-Regular.ttf", size = 13 },
    small = { file = "Inter-Regular.ttf", size = 11 },
    monoSmall = { file = "JetBrainsMono-Regular.ttf", size = 11 },
  },
  surfaces = {
    card = { bg = "ground", border = "line", radius = "r8" },
    toast = { bg = "raised", border = "#3B4047", radius = "r8" },
    tooltip = { bg = "raised", border = "#3B4047", radius = "r4" },
    inset = { bg = "panel", border = "line", radius = "r4" },
    plain = {},
  },
  money = "letters",
  metrics = {
    Tab = { rail = 2, lineWidth = 1, railHighlight = true },
    Help = { size = 14 },
  },
  skins = {},
  space = { 4, 8, 12, 16, 24 },
  radius = { r4 = 4, r8 = 8, pill = 8 },
}
