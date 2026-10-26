# FxUI built-in theme ("default", FxUI Dark)

Notes for working on the built-in theme. General FxUI development is in `README.md` and `AGENTS.md` at the repository root; theme addons keep their own notes next to their code (e.g. `FxUI_Theme_Classic/AGENTS.md`).

## Role

- Defined in `Default.lua`, loaded before the theme engine (`../Theme.lua`). It is the base every theme inherits from and must stay complete: every color token, font token, surface role and metric a component reads needs a value here.
- It stays in the core library so FxUI works with no theme addon installed. Other themes ship as `FxUI_Theme_*` addons.
- Its drawing is the components' own code; it defines no skins. Skins in other themes must leave a pooled frame in a state this theme's drawing can take over (and the default drawing paths clear skin leftovers).

## Look

- Dark, flat, gold accent. Rounded corners from the generated nine-slice textures (`../Media/Textures`, `tools/build-textures.py`): `r4` and `r8`, `pill` = `r8`.
- Text contrast: `text`, `muted` and every item-quality color reach 4.5:1 on `panel` (a test checks this). Rare and Epic are lifted from Blizzard's values to get there.
- Fonts: Inter, JetBrains Mono, Barlow Condensed as static instances (`../Media/Fonts`, `tools/build-fonts.py`); no shadows.
- Money as digits with coin-colored letters (`money = "letters"`).
- Window chrome: status and actions in the header (`metrics.Window.status/actions` default to `"header"`); no footer unless the addon asks for one.

## Components

- Tabs: plain text, `strong` font in every state so tabs keep their width; state shows in the text color (muted → text on hover and when selected). The selected tab's gold mark sits on the line under the row (`metrics.Tab.railHighlight`, `rail = 2`, `lineWidth = 1`), not on the tab.
- Buttons: primary (gold fill), secondary (raised fill, light border), danger (tinted fill and border), ghost (text only, raised on hover); sizes `sm` 24, `md` 30, `lg` 40.
- Cards: `surface = "card"` (ground fill, line border, `r8`); toasts use `surface = "toast"`.
