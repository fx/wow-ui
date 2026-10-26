# Dev Tools

## Overview

FxUI renders inside the game client, and only the client knows the real result. The developer tools make that result inspectable from outside: the **FxUI Dev** addon (`FxUI_Dev`) adds a dev window, a gallery of every component, an element picker and snapshots of every mounted FxUI tree; the **snapshot reader** (`tools/inspect.lua`) prints a snapshot as a readable tree with layout problems flagged; and the **`fxui` agent skill** (`.agents/skills/fxui/SKILL.md`) documents the develop–inspect loop. This spec owns all three. The library's own behaviour is owned by the other specs ([architecture](../architecture/)).

## Background

- Addons cannot write files; snapshots leave the client through SavedVariables, which the client writes on reload or logout. That is why taking a snapshot reloads the UI by default, and why the tools reopen what was open after a reload.
- The tools are built with FxUI itself, so they exercise the library and appear in their own snapshots.
- Delivered by [0003](../../changes/0003-dev-tools.md).

## Requirements

### Commands and key bindings

FxUI Dev MUST register these `/fx` subcommands ([architecture](../architecture/#shared-fx-command)):

| Command | Does |
|---------|------|
| `/fx dev` | Opens or closes the dev window |
| `/fx dev pick` | Starts the element picker (or stops it if running) |
| `/fx dev all [FrameName ...] [-n]` | Snapshots every mounted FxUI tree, plus each named global frame, then reloads; `-n` skips the reload |
| `/fx dev <anything else>` | Prints the `/fx dev` usage |
| `/fx demo` | Opens or closes the component demo |

- FxUI Dev MUST offer two key bindings under Key Bindings → AddOns → FxUI Dev: "Pick an FxUI element to export" and "Snapshot all FxUI and reload".
- At login FxUI Dev MUST print a one-line notice naming `/fx demo` and `/fx dev`.

### Snapshots

- A snapshot MUST record every mounted FxUI tree from every addon: for each node its id, key, component or host name, props and component state (functions, elements, regions and large tables summarised), render count, theme where it differs from its parent's, effective scale, scroll offsets and ranges, the layout box FxUI computed, and what the client reports about its region and every sub-region (type, rect, shown and visible state, alpha, text, font, text color, string widths and truncation for font strings; texture file, vertex color, slice margins, texture coordinates, blend mode and draw layer for textures; strata, level, mouse, clipping and enabled state for frames).
- A snapshot MUST also record its time, the FxUI version, the global theme, the UI scale, the FxUI scale, the UI size and the physical screen size, the client version, build and interface, region statistics, what is under the mouse (with FxUI node ids), any requested named frames (or that they were not found), the node selected with the picker, and FxUI's recent errors.
- FxUI Dev MUST keep the five most recent snapshots, dropping the oldest.
- Taking a snapshot MUST be refused in combat, with a chat message.
- After storing a snapshot FxUI Dev MUST reload the UI, unless the "Reload after a snapshot" setting is off or `-n` was given, in which case it says the snapshot reaches disk on the next reload or logout.
- A failure while taking a snapshot MUST be reported in chat and MUST NOT reload.

#### Scenario: Snapshot all

- **GIVEN** the demo is open
- **WHEN** the player runs `/fx dev all`
- **THEN** a snapshot holding the demo's tree is stored and the UI reloads

#### Scenario: Snapshot without reload

- **GIVEN** any mounted trees
- **WHEN** the player runs `/fx dev all -n`
- **THEN** a snapshot is stored, nothing reloads, and chat says it reaches disk on the next reload or logout

#### Scenario: Combat

- **GIVEN** the player is in combat
- **WHEN** a snapshot is requested
- **THEN** none is taken and chat says "not in combat"

### Element picker

- While picking, a box MUST follow the innermost FxUI element under the cursor in any mounted tree (only FxUI elements, never the picker itself), with a label giving its type, its text or title, its size and its path from the root.
- The mouse wheel MUST move the selection to the parent (up) or back toward the innermost element (down).
- A left click MUST take a snapshot with that element marked as selected (and reload as for any snapshot); a right click, Esc, entering combat, or clicking the dev window's Pick button MUST stop picking without a snapshot. While picking, keys other than Esc MUST still reach the game.
- Picking MUST be refused in combat.
- Hit testing MUST account for the FxUI scale, so elements in scaled windows are picked where they are drawn.

#### Scenario: Pick a parent

- **GIVEN** the picker is running over a button inside a row inside a window
- **WHEN** the player scrolls the wheel up once and left-clicks
- **THEN** a snapshot is stored with the row marked as selected

### Dev window

- The dev window (an FxUI `sm` window, refreshed every second) MUST offer: Pick element (a toggle that shows when picking is active), Snapshot all, Demo (open or close), buttons that set the global theme for every registered theme, FxUI scale −/+ in 5 % steps with a button showing the current percentage that resets to 100 %, a link to Options → AddOns → FxUI, and Reload (disabled in combat) and Settings actions.
- It MUST show the last snapshot's time and how many are stored, the client version, build and interface, the UI size and scale, region statistics, the mounted trees, the registered `/fx` commands, and the count and three most recent of FxUI's errors with a Clear button.
- It MUST remember its position and size per character.

### Settings

FxUI Dev MUST register Options → AddOns → FxUI Dev with, per character:

- **Reopen after reload** (default on): after a reload, the dev window and the demo reopen if they were open before.
- **Reload after a snapshot** (default on).
- Buttons to open the dev window and to toggle the demo.

#### Scenario: Reopen after reload

- **GIVEN** the dev window and the demo are open and Reopen after reload is on
- **WHEN** the UI reloads
- **THEN** both are open again after login

### Component demo

- The demo MUST be an FxUI window (980 × 660, minimum 760 × 520) with tabs that exercise every component: Controls (buttons in every variant, size and state including busy and secure, badges, toggles, meter, toasts), Items (a sortable, selectable table of 5,000 generated item rows with item cells, money, badges and an Inspect button, plus live region statistics), Charts (line, candles and bars with legends and a randomise button), Theme (color swatches, type samples, global theme and this-window theme choices) and Scroll (vertical, horizontal and two-way scroll views).
- Inspect MUST open a second window docked to the demo's right edge.
- The demo MUST remember, per character, its position and size, the selected tab and its own theme choice; its status shows the FxUI version and the theme in use.
- Demo data MUST be generated deterministically and use only generic item data, so it looks the same every time.

### Snapshot reader

`lua tools/inspect.lua <SavedVariables/FxUI_Dev.lua> [options]` (also `mise run inspect ...`):

| Option | Effect |
|--------|--------|
| `--snapshot N` | Which snapshot: 1 is the oldest; default the newest; `-1` the one before the newest, and so on |
| `--node ID` | Only that node's subtree, with full props, sub-regions and its screen-pixel rect |
| `--parts` | Every node's sub-regions |
| `--props` | Every node's full props |
| `--frames` | Include frames requested by name |
| `--list` | List stored snapshots (date, roots, errors) and exit |

- The reader MUST print a header (snapshot number and date, client version, build and interface, FxUI version, UI size and scale, FxUI scale, screen size, theme, region statistics), the snapshot's errors, what was under the mouse, the picked selection (with its screen-pixel rect) when there is one, then every root's tree with each node's position relative to its parent and size, and finally a list of every flagged issue (or "No layout issues flagged.").
- It MUST mark hovered nodes `<== HOVER` and the picked node `<== SELECTED`.
- It MUST flag: `TRUNCATED` text (in the node or one of its parts); `ZERO` size for a visible region; `NO-RECT` for a visible region without a rect; `NONFINITE` geometry; `SIZE` when the client's size differs from FxUI's layout; `OVERFLOW` when a node sticks out of its parent (not counting content inside scroll areas and lists); `PADDING` when a child of a padded stack reaches into the padding; and `OVERFLOW(<part>)` when a label or sub-frame sticks out of its node.
- Screen-pixel rects MUST be given as `x,y wxh` from the top-left of the client area together with an ImageMagick crop geometry, so a screenshot can be cropped to the element.
- The reader MUST read non-finite numbers the client writes (`nan`, `inf`) without failing.
- It MUST exit with status 2 and a usage line when no file is given, and 1 when the file holds no snapshots.

#### Scenario: Non-finite geometry

- **GIVEN** a snapshot in which a region's rect contains `nan`
- **WHEN** the reader prints it
- **THEN** it does not fail and flags that node `NONFINITE`

### Agent skill

- The repository MUST ship the `fxui` agent skill at `.agents/skills/fxui/SKILL.md`, describing how to find the client, link the addons, use the in-game tools, take and read snapshots, and when screenshots are still needed.
- The skill MUST stay generic: no user names, account names, character names or local paths.

## Design

### Saved data

| Variable | Scope | Holds |
|----------|-------|-------|
| `FxUIDevDB.snapshots` | Account | The five most recent snapshots |
| `FxUIDevCharDB` | Character | `restore`, `snapshotReload`, `devOpen`, `devWindow` (geometry), `demoOpen`, `window` (demo geometry), `tab`, `demoTheme` |

The reader also accepts snapshots stored under the earlier `FxUIInspectDB` name.

### Snapshot node shape

```lua
{ id = 12, key = "k:3", host = "Button", props = { text = "Go", onClick = "<fn>" },
  layout = { x, y, w, h }, scale = 1, scroll = { offsetX, maxX, offsetY, maxY },
  region = { type = "Button", rect = { left, bottom, w, h }, shown = true, visible = true, ... },
  parts = { { field = "label", type = "FontString", text = "Go", font = { file, size }, ... } },
  children = { ... } }
```

Component nodes carry `component`, `props`, `state`, `renders` and a single child. Sub-regions are named by the field the host keeps them under (`label`, `fxBg`, `skin:<key>`, `scrollContent`, ...).

### Picker

The picker is a full-screen frame at `TOOLTIP` strata that hit-tests every mounted tree's host nodes in UI-parent units, keeps one chain of nested hits, and indexes into it by wheel depth.

## Constraints

- Snapshots carry only what the client reports about the UI; they hold no account data beyond what the UI shows.
- Reloads are disruptive, so snapshots never happen in combat and the tools restore what was open.

## Open Questions

None.

## References

- [Architecture](../architecture/), [Rendering](../rendering/), [Layout](../layout/)
- ImageMagick crop geometry: <https://imagemagick.org/script/command-line-processing.php#geometry>

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-26 | Initial spec created from the implementation | [0003-dev-tools](../../changes/0003-dev-tools.md) |
