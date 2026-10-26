# Architecture

## Overview

FxUI (`FxUI-1.0`) is a general-purpose declarative UI component library for World of Warcraft addons. Components are functions of props that return a tree of plain tables; a reconciler turns that tree into client frames, reusing pooled regions instead of creating new ones. This spec owns how the repository and its addons are laid out, how FxUI ships and versions, the library-wide services every component relies on (error reporting, combat state, the shared `/fx` command, FxUI scale), the media and their generators, and the testing and CI rules. Behaviour of individual subsystems is owned by the specs listed under Background.

## Background

- The repository is public. FxUI MUST NOT depend on, name or assume any particular consumer addon; it stays usable by any addon. AceGUI-3.0's widget pooling and release pattern was reference material only; it is not a dependency.
- FxUI targets the retail client (interface `120105`). Every addon's `.toc` declares that interface.
- Related specs:
  - [Rendering](../rendering/): elements, components, the reconciler, pooling, batching, roots.
  - [Layout](../layout/): measuring, stacks, flex, wrapping, scrolling.
  - [Components](../components/): window, tabs, buttons, controls, text primitives, toasts.
  - [Data components](../data-components/): money, item cells, meters, lists, tables, charts, legends.
  - [Theme tokens](../theme-tokens/): the token contract, the default theme's values, contrast and money formatting.
  - [Theming](../theming/): the theme engine, skins, surfaces and the theme setting.
  - [Theme addons](../theme-addons/): the Classic and Teal theme addons.
  - [Dev tools](../dev-tools/): the FxUI Dev addon, the snapshot reader and the agent skill.

## Requirements

### Repository layout

The repository MUST hold each addon in its own top-level folder named after the addon, so each folder can be linked or copied into the client's `Interface/AddOns/` as is.

| Folder | Addon | Depends on |
|--------|-------|------------|
| `FxUI/` | The library (`FxUI-1.0`), including the built-in default theme and its media | — |
| `FxUI_Theme_Classic/` | Classic theme addon | FxUI |
| `FxUI_Theme_Teal/` | Teal theme addon | FxUI |
| `FxUI_Dev/` | Developer tools: dev window, demo, snapshots | FxUI |

Supporting folders: `tests/` (headless tests and the client stub), `tools/` (snapshot reader, media generators), `docs/` (this documentation), `.agents/skills/fxui/` (the agent skill, see [dev tools](../dev-tools/)).

- Every addon other than FxUI MUST declare FxUI as a dependency in its `.toc`.
- FxUI MUST work with no other addon from this repository installed.

#### Scenario: Library alone

- **GIVEN** only `FxUI/` is installed
- **WHEN** the client loads and an addon mounts FxUI components
- **THEN** they render with the built-in default theme and nothing errors

### Distribution and versioning

- FxUI MUST register through LibStub as `FxUI-1.0` with an integer minor version, so that when several addons carry copies the copy with the highest minor is the one every addon uses.
- A copy whose minor is not newer than the registered one MUST load without side effects.
- A minor version bump MUST NOT break a consumer written against an earlier minor of `FxUI-1.0`.
- FxUI MUST resolve its media paths from the folder it was actually loaded from, so a copy embedded inside another addon finds its fonts and textures.
- Only the standalone `FxUI` addon MAY own saved settings and register an Options category; an embedded copy leaves that to its host addon.

#### Scenario: Two copies, two versions

- **GIVEN** addon A carries FxUI minor 1 and addon B carries a newer minor
- **WHEN** the client loads both
- **THEN** both addons get the newer copy from `LibStub("FxUI-1.0")` and both render

#### Scenario: Embedded copy finds its media

- **GIVEN** FxUI is loaded from `Interface/AddOns/SomeAddon/Libs/FxUI/`
- **WHEN** a component draws a rounded surface
- **THEN** the texture path points inside `SomeAddon/Libs/FxUI/Media/`

### Error reporting

- An error raised inside a consumer callback (a component's render, init, mount or unmount hook, a library event or combat listener, a component's delayed callback, a `/fx` command handler, an extra tooltip callback) MUST be reported through the client's error handler and MUST NOT unwind the code that called it.
- FxUI MUST keep the most recent 50 reported errors, each with its time and message (including a stack trace), for developer tools to show.

#### Scenario: Failing render

- **GIVEN** a component whose render raises an error
- **WHEN** it is mounted beside other components
- **THEN** the error reaches the client's error handler, the failing component renders nothing, and the components beside it render normally

### Combat state

- FxUI MUST expose whether the player is in combat (`UI.inCombat()`), updated before any FxUI combat listener runs.
- FxUI MUST NOT itself make any protected call.

### Shared `/fx` command

FxUI owns a single `/fx` slash command shared by every addon that uses it.

- An addon MUST be able to register a one-word subcommand with a handler and optional help text (`UI.registerCommand(name, handler, help)`) and remove it again (`UI.unregisterCommand(name)`).
- Subcommand names MUST be case-insensitive; a name that is not a single word MUST be rejected.
- The handler MUST receive the rest of the line with surrounding whitespace trimmed.
- `/fx` alone or `/fx help` MUST list every registered subcommand with its help text, sorted by name.
- An unknown subcommand MUST print that it does not exist, followed by the list.
- Registrations MUST survive a library upgrade to a newer minor.

#### Scenario: Register and run

- **GIVEN** an addon registers `Echo` with a handler
- **WHEN** the player types `/fx ECHO  hello world `
- **THEN** the handler receives `hello world`

#### Scenario: Unknown command

- **GIVEN** no `nope` subcommand is registered
- **WHEN** the player types `/fx nope`
- **THEN** the chat shows "no command 'nope'" and the list of registered subcommands

### FxUI scale

FxUI applies its own scale on top of the game's UI scale, so FxUI windows can be made smaller than the game's minimum UI scale allows, or larger.

- Every top-level FxUI frame that follows the scale (windows and the toast stack) MUST be drawn at `UI.scale`; its on-screen size is the game UI scale times the FxUI scale.
- `UI.setScale(s)` MUST clamp `s` to 0.4–2.0 (`UI.SCALE_MIN`, `UI.SCALE_MAX`), round it to whole percent, apply it to every following frame and re-render every mounted tree.
- A free (undocked) window MUST keep its on-screen top-left corner when the scale changes.
- The standalone addon MUST save the scale across sessions and offer it as a slider in Options → AddOns → FxUI (40 %–200 %, 5 % steps, labelled as a percentage). `UI.openSettings()` opens that page.

#### Scenario: Scale a window

- **GIVEN** a window at 100 % with its top-left at a known screen position
- **WHEN** `UI.setScale(0.8)` runs
- **THEN** the window is drawn at 0.8, its top-left stays at the same screen position, and the saved scale is 0.8

#### Scenario: Clamp

- **GIVEN** any scale
- **WHEN** `UI.setScale(9)` runs
- **THEN** the scale is 2.0

### Media

- FxUI MUST ship the fonts and textures it draws with inside `FxUI/Media/`, so it renders the same with no other font or texture addon installed.
- Shipped fonts are static instances generated from OFL-licensed sources, and their licence texts MUST ship beside them.
- Every generated media file MUST be reproducible from a generator in `tools/`.

| File | Generated by | What |
|------|--------------|------|
| `Fonts/Inter-Regular.ttf`, `Fonts/Inter-SemiBold.ttf` | `tools/build-fonts.py` | Inter at weight 400 / 600, optical size 14 |
| `Fonts/JetBrainsMono-Regular.ttf` | `tools/build-fonts.py` | JetBrains Mono at weight 400 |
| `Fonts/BarlowCondensed-SemiBold.ttf` | `tools/build-fonts.py` (copied) | Barlow Condensed SemiBold |
| `Fonts/OFL-*.txt` | — | Licence texts |
| `Textures/Round4.tga`, `Textures/Round8.tga` | `tools/build-textures.py` | Filled rounded rectangles, radius 4 / 8, on a square of 4 × radius, white with anti-aliased alpha |
| `Textures/Round4Ring.tga`, `Textures/Round8Ring.tga` | `tools/build-textures.py` | 1 px rings of the same shapes |
| `Textures/Circle.tga` | `tools/build-textures.py` | Filled 32 × 32 circle |

Textures are uncompressed 32-bit TGA, white so the client can tint them, and nine-sliced in game with margins equal to the radius.

### Testing and CI

- Headless tests MUST run under Lua 5.1, the client's Lua, with `mise run test` (equivalently `lua tests/run.lua` from the repository root), against the strict client stub in `tests/wow.lua`.
- The stub MUST raise an error when code calls a client API method it does not define, so a misspelt or unsupported call fails in the tests rather than in game; code that starts using a new client API MUST extend the stub with it.
- The stub MUST reproduce client behaviour FxUI depends on where plain Lua differs (for example, the client's `string.format` raises on integer conversions of 2^31 or more).
- A test MUST fail when anything is reported through the error handler while it runs, even if its own assertions pass.
- The test run MUST exit non-zero when any test fails.
- Tests MUST NOT be skipped; a test that cannot pass is fixed, replaced or removed.
- CI (GitHub Actions) MUST run the headless tests on every pull request and on every push to `main`.
- CI MUST fail when line coverage of the repository's own Lua code, excluding `tests/` and vendored third-party code under any `Libs/` folder, is below 80 %.

#### Scenario: Unknown client API

- **GIVEN** code calls a frame method the stub does not define
- **WHEN** the tests run
- **THEN** the test fails with "stub: unknown client API method <name>"

#### Scenario: Coverage gate

- **GIVEN** a pull request whose changes leave line coverage of the repository's own Lua code at 79 %
- **WHEN** CI runs
- **THEN** the coverage check fails

## Design

### Load order

`FxUI/FxUI.toc` loads, in order: `Libs/LibStub/LibStub.lua`, `Core.lua`, `Themes/Default.lua`, `Theme.lua`, `Format.lua`, `Render.lua`, `Surface.lua`, `Commands.lua`, `Scale.lua`, then `Components/Layout.lua`, `Controls.lua`, `Data.lua`, `List.lua`, `Table.lua`, `Window.lua`, `Toast.lua`. Each file after `Core.lua` returns early when the namespace holds no library (an older copy). Shared internals live on `UI._internal`, which is not public API.

The standalone addon saves `FxUIDB` (account-wide): `scale` and `theme`.

### Development tools

`mise.toml` pins Lua 5.1.5, Python 3.13 and uv, creates `.venv` and installs `tools/requirements.txt` (fontTools). Tasks:

| Task | Runs |
|------|------|
| `mise run test` | `lua tests/run.lua` |
| `mise run inspect <FxUI_Dev.lua> [options]` | `lua tools/inspect.lua` (see [dev tools](../dev-tools/)) |
| `mise run fonts <google-fonts-download-dir>` | `python tools/build-fonts.py <dir> FxUI/Media/Fonts` |
| `mise run textures` | `python tools/build-textures.py FxUI/Media/Textures` |

The media generators run by hand and their outputs are committed; they are Python and outside the Lua coverage gate.

### Test harness

`tests/wow.lua` is a minimal stand-in for the client: frames, buttons, textures, lines, mask textures, font strings and fonts with anchor resolution (`GetRect` resolves any set of anchors), sizes, scale, shown and visible state, scripts and hooks, events, timers (`C_Timer.After` driven by `W.advance`), cursor position, item data that loads on demand (`W.loadItems`), the Settings panel API (records what addons register), backdrops, tooltips and SavedVariables writing. Client methods are looked up through a metatable that raises for any capitalised name the stub's classes do not define. `W.loadAddon(dir, name)` loads an addon by reading its `.toc`, so file order in tests matches the client.

## Constraints

- Protected-call and combat-lockdown rules are client rules; FxUI only arranges for consumer handlers to run inside the player's click (see [components](../components/)).
- Frames cannot be destroyed and creating them is costly, which is why pooling is mandatory rather than an optimisation ([rendering](../rendering/)).
- Addons cannot write files; everything that leaves the client goes through SavedVariables, written on reload or logout.
- Public repository: nothing in it names, describes or links a specific consumer project, private repository, private design document or local path. Examples use generic addon names and generic item data.

## Open Questions

- **Addon licence and packaging.** No licence file or release packaging exists yet. Undecided.
- **WoW: Forever.** Not released; FxUI is developed against retail, on which it is based. Whether a separate interface number or flavour `.toc` is needed is undecided.

## References

- LibStub (vendored in `FxUI/Libs/LibStub/`)
- AceGUI-3.0: reference for widget pooling and release; not a dependency
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119)

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-25 | Initial spec created | — |
| 2026-10-25 | Repository name settled as `fx/wow-ui`; component set detail | — |
| 2026-10-26 | Rewritten as built: retail target, repository layout, library services, scale, media, testing and CI; subsystem behaviour moved to its own specs | [0001-fxui-core](../../changes/0001-fxui-core.md) |
