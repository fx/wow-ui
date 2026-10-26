---
name: fxui
description: "Develop, inspect and debug FxUI interfaces running in the World of Warcraft client. Use when the user reports how an FxUI window, panel or component looks or behaves in game — \"check this window\", \"alignment is off\", \"text is cut off\", \"check the snapshot\", \"see if you see the problem\", \"this button looks wrong\", \"the list doesn't scroll\", a Lua error from an FxUI addon — when they ask to verify a UI change in game, or when building FxUI components and developer tools. Reads FxUI Dev snapshots exported from the client (geometry, fonts, colors, truncation as the client computed them), the saved error log, and screenshots when pixels matter."
---

# FxUI: developing against the live client

FxUI renders inside the WoW client, and only the client knows the real result. Addons cannot write files or open sockets, so everything leaves through SavedVariables, which the client writes on `/reload` or logout. The `FxUI_Dev` addon in this repository uses that channel: in game it snapshots every mounted FxUI tree with the client's own numbers, then reloads. `tools/inspect.lua` turns the snapshot into a readable tree with problems flagged.

**Prefer the snapshot to screenshots.** It holds exact sizes, positions, fonts, colors, truncation and the layout FxUI intended, all of which a screenshot can only approximate. Use screenshots only for what a snapshot cannot show ([Screenshots](#screenshots)).

Keep this skill current: see [Keeping this skill current](#keeping-this-skill-current).

## 1. Find the WoW directory

1. Look for a recorded location first: your persistent memory, then the project's instruction files (`AGENTS.md`, `CLAUDE.md` and any local or parent-directory variants). The useful facts are the client directory (the one holding `Interface/` and `WTF/`, e.g. `.../World of Warcraft/_retail_`) and the account folder name under `WTF/Account/`.
2. If nothing is recorded, search the usual places and confirm with the user before relying on a guess:
   - Windows: `C:\Program Files (x86)\World of Warcraft\_retail_`, `C:\Program Files\World of Warcraft\_retail_`
   - macOS: `/Applications/World of Warcraft/_retail_`
   - Linux: under the home directory, inside Wine, Lutris, Bottles or Steam prefixes, or a plain `~/Games/...` folder. `find ~ -maxdepth 8 -type d -name _retail_ 2>/dev/null` finds most of them.
   - Other flavours sit beside `_retail_` (`_classic_`, `_classic_era_`, `_anniversary_`, `_beta_`, `_ptr_`); ask which one is in use when several exist.
3. If you still cannot find it, ask the user for the path.
4. Once confirmed, record the client directory and account folder where you keep durable notes (memory or a local, uncommitted instruction file) so the next session does not ask again. Never write a user's paths into this repository.

The account folder: when several exist under `WTF/Account/`, the one whose `SavedVariables/` changed most recently is almost always the one in use. The client build is in `<WoW>/.build.info`; the interface number is the version without dots, zero-padded (12.1.5 → `120105`).

## 2. Install for development

The client loads addons from `<client>/Interface/AddOns/<AddonName>/`. Link the repository's addon folders there so edits apply on `/reload`:

```sh
ln -s "$PWD/FxUI" "<client>/Interface/AddOns/FxUI"
ln -s "$PWD/FxUI_Dev" "<client>/Interface/AddOns/FxUI_Dev"
```

Link the theme addons (`FxUI_Theme_*`) the same way when working on themes.

On Windows use a junction (`mklink /J`). Copies work too but go stale.

**Restart versus reload.** The client discovers new addon folders, new `.toc` entries and `Bindings.xml` only at startup. Renaming or adding an addon, adding a file to a `.toc`, or changing key bindings needs a full game restart; `/reload` is enough for edits to existing files. Tell the user which one a change needs.

## 3. The in-game tools

FxUI owns one shared `/fx` command; addons add subcommands with `UI.registerCommand(name, handler, help)`. `/fx` lists them.

- **`/fx dev`** toggles the dev window (compact, built with FxUI):
  - **Pick element** toggles the picker: a gold box follows the FxUI element under the cursor with its path and size; the mouse wheel moves to the parent or child; left-click exports with that element marked as selected. Esc, right-click, clicking the Pick button again, or entering combat cancels. The picker only picks FxUI elements.
  - **Snapshot all** exports every mounted FxUI tree, from every addon using FxUI.
  - **Demo** opens the component gallery; theme buttons switch the active theme.
  - **Reload** reloads the UI; **Settings** opens Options → AddOns → FxUI Dev.
  - Facts: last snapshot, client build, UI size and scale, region counts, mounted trees, `/fx` commands, recent FxUI errors.
  - **FxUI scale** row: −/+ in 5% steps, back to 100%, and a link to Options → AddOns → FxUI.
- **`/fx dev pick`**, **`/fx dev all [FrameName ...] [-n]`**: the same without the window. Named frames (Blizzard's or other addons') are dumped too; `-n` skips the reload.
- **`/fx demo`**: the component gallery.
- **Scale**: FxUI windows (and toasts) follow `UI.scale` on top of the game's UI scale, so their on-screen size is game UI scale × FxUI scale. The standalone FxUI addon saves it (`FxUIDB.scale`) and offers a slider in Options → AddOns → FxUI (40%–200%); `UI.setScale(s)` sets it from code. Windows keep their on-screen top-left when it changes and save their geometry with the scale they had.
- **FxUI Dev settings** (per character): *Reopen after reload* (the dev window and demo come back after every reload, so a snapshot does not cost the user their workspace) and *Reload after a snapshot* (off: the snapshot waits in memory until the next reload or logout).
- **Key bindings** under Key Bindings → AddOns → FxUI Dev: pick, and snapshot all. A binding lets the user hover the problem and press a key, which also records what was under the mouse.
- Snapshots refuse in combat; a reload mid-fight is never wanted.

## 4. Get a snapshot

The snapshot lives at `<client>/WTF/Account/<ACCOUNT>/SavedVariables/FxUI_Dev.lua`. It keeps the last five.

1. Check freshness first: `lua tools/inspect.lua <file> --list`, and compare the newest snapshot's time with the current time (`date`), the user's report, and your last code change. A snapshot from before your change shows the old code.
2. If there is none, or it is stale, ask the user to take one: **Pick element** on the problem when they can point at it, **Snapshot all** otherwise. Say whether it needs a `/reload` first to load your change (or a restart, see above). Then wait for them.
3. "Check the snapshot" or "see if you see the problem" means: read the newest snapshot and find the problem yourself, without being told what it is.

## 5. Read and diagnose

```sh
lua tools/inspect.lua <file>                 # newest snapshot: header, errors, selection, every tree, issues
lua tools/inspect.lua <file> --node 21       # one subtree with full props and sub-regions, plus its screen pixels
lua tools/inspect.lua <file> --parts         # every node's sub-regions (labels, backgrounds, borders)
lua tools/inspect.lua <file> --props         # every node's full props
lua tools/inspect.lua <file> --frames        # frames dumped by name
lua tools/inspect.lua <file> --snapshot -1   # the one before the newest (compare before/after a change)
```

What the output means:

- Each line is a node: `#id`, the host (`Button`, `HStack`, ...) or `<Component>`, key props, then `@x,y WxH` — the client's actual rect relative to the parent element (roots relative to the top-left of the UI).
- `[...]` lists region facts: font file, size and color for text; `clips`; `disabled`; `invisible`; `alpha`; `scrolls y a/b x c/d` (a scrolling container and its offsets out of each range). Overflow is not flagged for content inside a scrolling container or a List, since scrolled-away rows and the List's overscan rows sit outside it by design.
- `<== SELECTED` is the element picked with Pick element. `<== HOVER` is what was under the mouse when the snapshot was taken: with a key binding that is where the user is pointing; with a button it is usually just the button they clicked (Snapshot all), not the problem.
- Sub-regions (`--parts`, `--node`) are named by the field the component keeps them in (`label`, `fxBg`, `fxRing`, `headerFoot`, ...). Textures show FxUI's media file (`Round8.tga`) and slice margins.
- `!!` flags, also collected under **Issues** at the end:
  - `TRUNCATED` / `TRUNCATED(label)`: the client cut the text with an ellipsis. The element is narrower than its text.
  - `OVERFLOW n`: the element extends `n` units outside its parent. Unless the parent clips, it draws over whatever is next to it.
  - `OVERFLOW(field) n`: a label, tag or sub-frame drawn inside a component (a chart's `axisHi`, `lastTag`, a readout's `text`) sticks out of the component by `n`. Components that size their own parts must measure them.
  - `PADDING n`: the element stays inside its parent but runs `n` units into the parent's padding, so it sits on (or near) the edge and the spacing is no longer uniform. Usually the parent was sized from a measurement that disagreed with the final layout.
  - `SIZE a!=layout b`: the client's size differs from what FxUI's layout pass set. Points at anchoring bugs or something resizing the region behind FxUI's back.
  - `NO-RECT`: the region has no resolvable position (missing or circular anchors).
  - `NONFINITE`: a position or size is `nan` or `inf`, usually a parent sized from an endless measurement (wrapped text measured at zero width, a flexible child measured without a bound).
  - `ZERO`: visible but zero width or height.
- **Errors** lists what FxUI reported (render errors, handler errors) with stacks. Lua errors from any addon are in `<client>/WTF/Account/<ACCOUNT>/SavedVariables/!BugGrabber.lua` when BugGrabber is installed (written on reload or logout); read that instead of asking the user to paste errors.
- The header gives the client build, the game's UI scale and FxUI's scale, the UI size in units and the physical screen size.
- **Units and scale.** Every rect is in its region's own units. Inside an FxUI window those are scaled by the FxUI scale, so compare rects within one window freely, but convert before comparing across windows or with the screen: pixels per unit = effective scale × screenHeight / 768 (each node records its effective scale; `screen pixels:` lines already account for it). At FxUI scale 1, one unit is `screenHeight / uiHeight` pixels.

Checklist when looking for "the problem":

1. **Issues** at the end, and **Errors**.
2. Children whose rect extends past their parent's, even without a flag: content running off the bottom of a window body (which clips) is cut rather than flagged on the child.
3. Natural size versus given size: a row whose children add up to more than its width (sum the child widths and gaps), a column taller than its window, a child sitting on its parent's edge (compare its offset plus size with the parent's size minus padding).
4. Text: truncation, a font or size that is not the intended token, wrapped text with the wrong height. A `wrap = true` text that is `TRUNCATED` at one line's height means its height was measured wrong, not that it is too long.
5. State: `disabled`, `invisible`, `alpha`, selected tabs, toggles, the theme in the header.
6. What the snapshot cannot tell you (below), and whether a screenshot is needed for it.

Layout lesson: anything sized from a measurement (a row's height, a window deciding whether to scroll) is only right if the measurement matches the final layout. Flexible children are measured at the share they will actually get; a wrapping row measured at the wrong width reports the wrong height and pushes content into padding. Deciding whether something fits (and must scroll) counts flexible children at their natural size, not their minimum; otherwise a flex page never triggers scrolling and gets squeezed instead.

Client behaviours the stub now models (keep it that way when touching them):

- `FontString:SetText` before a font is set errors.
- Frames fire `OnShow`/`OnHide` when their shown state changes.
- A wrapped font string reports its height only within its current height: measure with the height cleared (`SetSize(w, 0)`), never trust a single line.
- Addon texture files come back as temporary file IDs.

Known blind spots:

- Solid color textures (`SetColorTexture`: dividers, underlines, square fills) report as `solid color` with a white tint: the client has no getter for their color.
- Textures FxUI did not set through its helpers can show a bare file ID (addon files get temporary IDs, reported negative or as large unsigned numbers).
- Rendering quality (anti-aliasing, nine-slice corners, how colors read over the game world) and overlap with frames FxUI does not own.

Report flagged problems first, with node ids, the numbers that show the problem and what the user would see; say plainly when nothing is wrong.

## 6. Fix and verify

1. Change the code (in this repository; the linked folders pick it up). Prefer fixing the cause in the library (a missing layout feature, a component default) over working around it in one screen.
2. Run the headless tests: `mise run test` (`mise install` once sets up Lua 5.1 and the Python tools from `mise.toml`; `lua` below is mise's Lua 5.1). `tests/wow.lua` is a strict stand-in for the client API that rejects unknown methods, so a misspelt call fails there first. When FxUI starts using a new client API, add it to the stub; when the client behaves in a way the stub does not (an error, an event), make the stub behave that way too, then confirm the test fails without your fix.
3. Check the layout headlessly before asking the user (the dev test snapshots every demo tab at the default and at the minimum window size and fails on any flag except an item name's ellipsis; add new tabs and screens to it, and always include the smallest size the window allows: users resize, and real windows are often narrower than the default): the tests can drive the dev addon, take a snapshot with `/fx dev all`, write it with `W.writeSavedVariables` and run the reader on it. Assert on the reader's output (no `OVERFLOW`, no `TRUNCATED`) to keep a fixed layout fixed; a regression test like that belongs next to every layout fix.
   Addons built on FxUI can run the same pass in their own harness: load FxUI, a theme addon and FxUI_Dev from an FxUI checkout with FxUI's stub, then snapshot their windows the same way. Assert that the reader actually printed the tree (look for the root component's name) before trusting an empty issue list: a reader that failed to load the file prints no issues at all.
   Client Lua differs from stock Lua 5.1 in places the stub copies: `string.format("%d")` is 32-bit and raises "integer overflow attempting to store" at 2^31, which copper amounts pass (214,748g). Format money and other large numbers with `tostring(math.floor(v))` or `%.0f`.
4. The stub's text metrics are approximate (about 0.55 × font size per character) and tend to run narrower than the real fonts. Never dismiss a stub `OVERFLOW` or `TRUNCATED` as metric noise: the client usually makes it worse. Leave margin, and treat the real snapshot as the authority.
5. Layouts must survive the default window size, not just the size the user happens to have saved: saved geometry can be lost (a renamed SavedVariable, a new character), and then the defaults decide what fits.
6. Ask the user to `/reload` (or restart), take a new snapshot of the same element, and compare with `--snapshot -1`. Report what the snapshot verified and what it did not.

## Screenshots

A snapshot cannot show pixels: texture quality and nine-slice artifacts, anti-aliasing, how colors read against the game world, overlap with frames FxUI does not own, animation. Use a screenshot for those, alongside a snapshot.

- **Always ask before capturing the user's screen.** It may show more than the game.
- **The game's own screenshots** need no extra tools and capture only the game: the user presses the Screenshot key (Print Screen by default) and the file lands in `<client>/Screenshots/`, newest by modification time.
- **Desktop capture** when the game runs windowed and the user agrees: Linux Wayland `grim -g "x,y wxh"` (window geometry from the compositor, e.g. `hyprctl clients -j` on Hyprland, `swaymsg -t get_tree` on Sway; the game must be on a visible workspace), X11 `import -window <id>`, macOS `screencapture -l <windowid>`, Windows the Snipping Tool or a PowerShell capture. Desktop captures include window decorations and other windows; the game's own screenshots do not.
- **Crop to the element.** `--node ID` and the selection print `screen pixels: x,y WxH (crop WxH+X+Y)`, measured from the top-left of the game's client area. Crop a game screenshot with ImageMagick: `magick shot.jpg -crop WxH+X+Y +repage crop.png`. For a desktop capture, add the window's client-area offset first.
- Look at crops at full resolution. Downscaled captures hide one-pixel problems.

## Themes

- Theme resolution: an element's `theme` prop, else its parent's, else the mount's `theme` option, else the global theme (Options → AddOns → FxUI, `UI.setTheme`). Snapshots tag elements whose theme differs from their parent's with `theme <name>`.
- Themes are addons (`FxUI_Theme_*`) calling `UI.registerTheme({ name, base, colors, fonts, surfaces, money, metrics, skins })`; the built-in `default` is the base everything inherits. Notes specific to one theme live in that theme's own `AGENTS.md` (`FxUI/Themes/AGENTS.md` for the built-in theme, `FxUI_Theme_*/AGENTS.md` for theme addons), not here.
- Skins replace a component's drawing; they draw with `UI.skinKit` so their textures and backdrops are cleaned up when a pooled frame is reused under another theme. Every default drawing path must clear skin leftovers (`I.clearSkin`) and every skin must clear FxUI's own surface; a test switches a pooled frame between themes to check both directions.
- Client art: check with `UI.textureExists(path)` and fall back to flat drawing; report missing files once through the error handler. An asset referenced by a current retail addon still ships, so grep the installed addons for its path. Blizzard's own UI source (FrameXML) is mirrored at github.com/Gethe/wow-ui-source (branches per client flavour, including `forever`), files under `Interface/AddOns/Blizzard_*`; `Interface/ui-code-list.txt` lists them. Use it for original sizes, anchors and texture coordinates.
- Where one element must meet another's art, position it from the art's on-screen rect at layout time (`GetLeft`/`GetRight` of the textures) rather than from computed offsets.
- Snapshots record each texture's coordinates (`uv l-r t-b`, `flipped`) and non-default blend mode, so wrong slices or flips show without a screenshot. Pixel alignment of art still needs one: after two rounds of geometry fixes the user still sees as wrong, ask to look. Capture, crop to the element at full resolution, upscale 2x with point sampling, and measure edges from ImageMagick's raw RGB output rather than eyeballing.
- Test layouts in every theme that changes metrics: the dev test runs every tab in the default theme and in Classic, at both window sizes.

## Conventions for FxUI developer tools and UI

What has worked, and what to keep doing:

- **Build tools with FxUI itself** (the dev window and the demo are FxUI trees), so they exercise the library and show up in snapshots.
- **Compact developer panels**: small components (`size = "sm"` buttons, `Window { size = "sm" }`), tight spacing, dividers instead of cards. Compact component variants are planned; until then use the small sizes.
- **Options belong in the client's Settings panel** (Options → AddOns), registered with the `Settings` API, not as toggles inside a panel. A panel can link to its settings page.
- **One `/fx` command**: register a subcommand instead of claiming a new slash command.
- **Persist what was open** and restore it after a reload when the user opts in, since the inspect loop reloads often.
- **Window chrome belongs to the Window**: status text (versions, counts, the active theme) goes in `status`, window-level buttons (reload, settings) in `actions`; the theme places both (default: header, Classic: a footer status bar, as AceGUI frames do). A footer exists only when something lands in it, so header-placing themes never get a forced footer; `footer` is for content the addon always wants at the bottom, `header` for content that really belongs in the title bar. The footer spans the full width under the resize grip.
- **Toggles for modes**: a button that starts a mode (picking) also ends it, shows its state, and Esc cancels.
- **Shorten values to fit, don't shrink fonts**: in charts, legends and other tight spots use `formatMoney(v, { short = true })` / `UI.Money { short = true }` (the largest denomination with one decimal: `7.4g`, `1.2kg`, `45s`), and give text that can grow a fallback (the chart readout drops OHLC when the plot is narrow). Components size their own columns from what they show (the chart's price column fits its widest label).
- **Charts use `UI.Chart`** (`mode = "line" | "candles" | "bars"`): price column with high/low and a last-price tag, gridlines, a dashed reference level, and a crosshair hover that snaps to the point, candle or bar with a readout (label plus value, or OHLC and change) and a price tag at the cursor. Pair it with `UI.Legend` (compact chips that wrap) rather than a row of label/value pairs. `UI.Sparkline` is for tiny inline trends only. Hover is drawn only while the mouse is over the chart, so take a snapshot with a key binding while hovering to inspect it.
- **Column data goes in `UI.Table`**: sortable headers (click toggles direction, chevron shows it), hover highlight, a selected row (`selected` + `onSelect`), header aligned with the rows. Use a bare `UI.List` only for single-cell rows.
- **Scroll instead of clipping**: window bodies scroll automatically when their content is taller than the window (flex children still fill when it fits); `UI.ScrollView { direction = "vertical" | "horizontal" | "both" }` does the same anywhere. The wheel scrolls vertically, Shift+wheel (or a plain wheel when there is nothing to scroll vertically) sideways. Fixed-size panels are fine as long as their content can scroll. The demo's Scroll tab shows all three.
- **Build children before the element**: `UI.HStack(t)` and the other constructors copy the children out of `t` when called, so children appended to the returned element afterwards are silently dropped (the row shows as `ZERO`). Fill a plain table first, then call the constructor with it.
- **Size table columns for the minimum window**: fixed column widths plus gaps must leave the flexible column room at the smallest width the window allows; use `gap = 8`, `Money` widths around 76 and short money where precision does not matter.
- **Wrap or reflow instead of overflowing**: `HStack { wrap = true, rowGap = ... }` for chip and swatch rows; check the result fits its container with a snapshot.

## Keeping this skill current

This file is the one place to learn how to develop and debug FxUI in the client. Whenever a session teaches something about that — a new tool or command, a reader option or flag, a blind spot, a better way to read a snapshot, a convention the user asked for, a client behaviour the stub had to learn — update this file in the same change. Keep it generic: no user names, paths, accounts or private project details (record those in memory or local notes instead).
