# FxUI

A declarative UI component library for World of Warcraft addons. Components are functions of props that return plain tables; a reconciler turns them into frames, reusing pooled frames, font strings and textures instead of creating new ones.

```lua
local UI = LibStub("FxUI-1.0")

local Row = UI.component("Row", function(props)
  return UI.HStack { gap = 8, align = "center",
    UI.ItemCell { item = props.item, qty = props.qty, flex = 1 },
    UI.Money { value = props.price },
    UI.Button { text = "Details", size = "sm", onClick = props.onDetails },
  }
end)

UI.mount(UIParent, UI.Window { title = "Items", width = 640, height = 480,
  UI.List { items = rows, key = "id", rowHeight = 36,
    render = function(r) return Row(r) end },
})
```

Status: early. Developed against the retail client.

## Repository

| Path | What |
|------|------|
| `FxUI/` | The library addon (`FxUI-1.0` via LibStub) |
| `FxUI_Theme_Classic/` | Theme: vanilla-era frames, buttons, checkboxes, tabs, fonts and coin icons from the client's own art |
| `FxUI_Theme_Teal/` | Theme: the default dark theme with a teal accent (a minimal theme addon) |
| `FxUI_Dev/` | Developer tools: a dev window (`/fx dev`), a gallery of every component (`/fx demo`), an element picker and snapshots of the live UI for offline inspection |
| `tests/` | Headless tests against a strict stand-in for the client API, and the coverage gate |
| `tools/` | Snapshot reader (`inspect.lua`), font and texture generators |
| `.agents/skills/fxui/` | Agent skill for developing and inspecting FxUI in the client (linked from `.claude/skills/`) |
| `docs/` | Specs and change documents |

## Development workflow

1. **Link the addons** into the client so edits apply on `/reload`:

   ```sh
   ln -s "$PWD/FxUI" "<WoW>/_retail_/Interface/AddOns/FxUI"
   ln -s "$PWD/FxUI_Theme_Classic" "<WoW>/_retail_/Interface/AddOns/FxUI_Theme_Classic"
   ln -s "$PWD/FxUI_Theme_Teal" "<WoW>/_retail_/Interface/AddOns/FxUI_Theme_Teal"
   ln -s "$PWD/FxUI_Dev" "<WoW>/_retail_/Interface/AddOns/FxUI_Dev"
   ```

   The client finds new addons, new `.toc` entries and key bindings only at startup; restart it after linking.

2. **Run the headless tests** after every change: `mise run test` (or `lua tests/run.lua`). `mise install` sets up the tools from `mise.toml`: Lua 5.1, the client's Lua, and Python with fontTools for the media generators. The stand-in in `tests/wow.lua` rejects client API methods it does not know, so a misspelt call fails here rather than in game. Add new APIs to it as FxUI starts using them.

3. **Check coverage** before opening a pull request: `mise run coverage` runs the tests under luacov and fails below 80 % line coverage (install luacov once with `luarocks install luacov`). CI runs both.

4. **Look at it in game.** `/reload`, then `/fx dev` for the dev window: capture buttons, the demo, theme switching, the FxUI scale, library and client facts, recent FxUI errors. `/fx demo` opens the demo directly; `/fx` lists every registered command. Options → AddOns → FxUI Dev has the settings, including reopening the dev window and demo after each reload. Lua errors from FxUI go through the client's error handler, so an error addon such as BugSack shows them.

5. **Inspect what the client actually did** instead of guessing from screenshots:
   - **Pick element** (dev window, `/fx dev pick` or a key binding): hover an element (a box shows the selection, its path and size), wheel to its parent or child, click. The UI reloads and the snapshot is written to `<WoW>/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/FxUI_Dev.lua`.
   - **Snapshot all** (dev window, `/fx dev all` or a key binding): every mounted FxUI tree, from every addon using FxUI. `/fx dev all FrameName` adds any named frame; `-n` skips the reload.
   - Read it: `mise run inspect <that file>` (or `lua tools/inspect.lua <that file>`). It prints each tree with the client's own sizes, positions, fonts, colors and truncation, flags problems (truncated text, overflow, content in the padding, size different from layout, missing anchors, non-finite geometry) and gives screen-pixel rects for cropping screenshots. `--node ID`, `--parts`, `--props`, `--frames`, `--snapshot -1`, `--list`.

6. **Screenshots** only for what a snapshot cannot show: texture quality, slicing artifacts, how colors read against the game world, overlap with frames FxUI does not own.

Agents: the `fxui` skill (`.agents/skills/fxui/SKILL.md`) walks through this loop.

## Slash commands

FxUI owns one `/fx` command shared by every addon that uses it. Register a subcommand instead of claiming a slash command of your own:

```lua
UI.registerCommand("myaddon", function(args) MyAddon:Toggle(args) end, "open My Addon")
```

`/fx` lists every registered subcommand with its help text. FxUI Dev registers `/fx dev` (the dev window; `/fx dev pick` and `/fx dev all [FrameName ...] [-n]` for snapshots) and `/fx demo` (the component demo).

## Themes

Every color, font, surface, size and most component drawing comes from a theme. Themes are addons that register themselves; the default dark theme is built in, because every theme inherits from it and FxUI must work with no theme installed. Two theme addons ship here: Classic (`classic`) and FxUI Teal (`teal`).

Which theme applies, from most to least specific:

- `theme = "classic"` (or a theme table) on any element: that element and everything under it.
- `UI.mount(frame, el, { theme = ... })`: a whole tree.
- The global theme: Options → AddOns → FxUI → Theme, or `UI.setTheme(name)`.

So an addon can follow the user's global theme, ship its own theme table without registering it, or name a theme another addon registers.

A theme addon depends on FxUI and calls `UI.registerTheme`:

```lua
UI.registerTheme({
  name = "mytheme", title = "My Theme", base = "default",
  colors = { gold = "#3FC1B0", onGold = "#06201C" },
  -- fonts = { body = { path = "Fonts\\FRIZQT__.TTF", size = 12, shadow = true } },
  -- surfaces = { card = { backdrop = {...}, bgColor = "#000000B3", borderColor = "#B0B0B0" } },
  -- money = "icons",
  -- metrics = { Button = { sizes = { md = { height = 22, pad = 14 } } } },
  -- skins = { Button = { paint = function(button, props, state) ... end } },
})
```

Anything not given is inherited from `base`. Skins take over a component's drawing; the contracts are documented next to each component (`Button`, `Toggle`, `Tab`, `Window`, `Meter`, `Scroll`), and `UI.skinKit` has the helpers they draw with (skin-owned textures that are cleaned up when the theme changes, classic backdrops, colors, `textureExists`). Stacks take `surface = "card"` (or another role) so themes can restyle panels.

## Scale

FxUI windows follow their own scale on top of the game's UI scale, so they can be made smaller than the game's minimum UI scale allows (or larger). Options → AddOns → FxUI has the slider; `UI.setScale(0.8)` sets it from code; the dev window has quick −/+ buttons.

## Media

Fonts are static instances of Inter, JetBrains Mono and Barlow Condensed (SIL Open Font License, see `FxUI/Media/Fonts/OFL-*.txt`), generated by `tools/build-fonts.py`. Rounded-rectangle textures are generated by `tools/build-textures.py`.
