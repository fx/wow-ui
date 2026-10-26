# Theming

## Overview

Every color, font, surface, size and most of the drawing in FxUI comes from a theme. This spec owns the theme engine: theme definitions and inheritance, registration, which theme applies where (global, per tree, per element), skins and the toolkit they draw with, surface roles, client-art probing, and the theme setting. Token names and the default theme's values are owned by [theme tokens](../theme-tokens/); the shipped theme addons by [theme addons](../theme-addons/).

## Background

- Themes ship as addons that register themselves; the built-in default theme stays in the core library because every theme inherits from it and FxUI must work with no theme installed.
- An addon can follow the user's global theme, name a theme another addon registers, or pass its own theme table without registering it.
- Delivered by [0001](../../changes/0001-fxui-core.md).

## Requirements

### Theme definitions

A theme definition is a table with:

| Field | Meaning |
|-------|---------|
| `name`, `title` | Registry key and display name |
| `base` | Theme it inherits from (default `"default"`; `false` for none) |
| `colors` | token → `"#RRGGBB"` or `"#RRGGBBAA"` |
| `fonts` | token → `{ file = <FxUI media font> | path = <client font path>, size, flags, caps, shadow }` |
| `surfaces` | role → `{ bg, border, radius }` or `{ backdrop = <client backdrop>, bgColor, borderColor }` |
| `money` | `"letters"` or `"icons"` |
| `metrics` | component → table of numbers and flags (heights, paddings, placements) |
| `skins` | component → functions that draw it |
| `space`, `radius` | Spacing steps and named radii |

- Anything a definition does not give MUST be inherited from its `base`, recursively, ending at the default theme.
- `metrics` and `skins` MUST merge per component: a theme that overrides one entry of a component inherits that component's other entries.
- A font whose file cannot be set MUST fall back to the client's standard font at the same size; `shadow = true` draws a 1 px drop shadow, otherwise none; `caps = true` draws text upper-case.

#### Scenario: Inheritance

- **GIVEN** theme `t-base` (base `default`) sets `gold` and `metrics.Tab = { height = 40, pad = 9 }`, and theme `t-child` (base `t-base`) sets `info` and `metrics.Tab = { pad = 5 }`
- **WHEN** `t-child` is resolved
- **THEN** it has `t-base`'s `gold`, its own `info`, the default theme's `text`, and `Tab` metrics `height = 40`, `pad = 5`

### Registration

- `UI.registerTheme(def)` MUST register a theme under `def.name` and re-resolve every registered theme, so themes inheriting from it pick up the change, and a mounted tree or element using that theme (by name, or as a table inheriting from it) MUST use the re-resolved theme from its next update; a definition without a name MUST be rejected. The older form `UI.registerTheme(name, base, overrides)` MUST keep working.
- `UI.listThemes()` MUST return `{ name, title }` for every registered theme, sorted by title.

### Which theme applies

- An element's theme MUST be, from most to least specific: its own `theme` prop (a registered name or a definition table), else its parent's theme, else the mount's `opts.theme`, else the global theme. Everything inside an element — colors, fonts, metrics, skins, money style, and the drawing done later on hover or in response to events — uses that theme.
- A theme table that is not registered MUST work as a `theme` value and resolve once per table (again after a theme is registered).
- An unknown theme name MUST be reported once through the error handler and fall back to the global theme.
- `UI.setTheme(name)` MUST make a registered theme the global theme, save it as the user's choice in the standalone addon, and re-render every mounted tree; an unregistered name MUST raise an error.
- Swapping the global theme MUST restyle every mounted tree of every addon without any addon changing code.

#### Scenario: Theme swap restyles every tree

- **GIVEN** two trees mounted by different addons, each drawing text in `gold`
- **WHEN** `UI.setTheme` activates a theme with another `gold`
- **THEN** both trees draw the new `gold`

#### Scenario: Per-tree and per-element themes

- **GIVEN** a tree mounted with `{ theme = "t-base" }` holding a Text, and a second Text with `theme = { name = "inline", colors = { gold = "#00FF00" } }`
- **WHEN** both draw in `gold`
- **THEN** the first uses `t-base`'s gold, the second `#00FF00`, and trees mounted without a theme keep the global theme's gold

#### Scenario: Unknown theme

- **GIVEN** no theme named `no-such-theme`
- **WHEN** two elements ask for it
- **THEN** one error is reported and both draw with the global theme

### Skins

A skin replaces a component's drawing in a theme; each component publishes its skin contract ([components](../components/#component-contracts-with-skins), [data components](../data-components/#skin-contracts)).

- A component MUST draw with the active theme's skin when it has one for that component, and with FxUI's own drawing otherwise.
- Because regions are pooled across themes, FxUI's own drawing MUST hide anything a skin left on a region, and a skinned path MUST hide FxUI's own surface, so a region drawn by one theme is clean when another theme draws it.
- `UI.skinKit` MUST give skins: `texture(frame, key, layer, sublayer)` (a texture owned by the skin, hidden again by `clear`), `clear(frame)`, `backdrop(frame, def, bg, border)` (a client backdrop on any frame), `surface(frame, bg, border, radius)` (FxUI's rounded surface), `color(spec, alpha)`, `mix(a, b, t)`, `setText(fontString, text, font, color)` and `textureExists(path)`.

#### Scenario: Pooled region changes theme

- **GIVEN** a Button drawn by a skinned theme was unmounted
- **WHEN** a Button is mounted again under the default theme and reuses that region
- **THEN** the skin's textures are hidden and the default background shows

### Surfaces

- A stack or scroll area with an explicit `bg` or `border` prop MUST draw that surface (with `radius` and `bgAlpha` when given); otherwise one with `surface = <role>` MUST draw the active theme's role: a colored rounded surface, or a client backdrop with its colors (falling back to a flat colored surface when backdrops are unavailable); otherwise it draws none.
- Rounded surfaces MUST use the shipped nine-slice textures for radius 4 and 8 and fall back to square fills and 1 px edges where nine-slicing is unavailable or the radius is smaller.

### Client art

- `UI.textureExists(path)` MUST report whether the client ships a texture file, caching the answer per path.
- A theme that draws with client art MUST check each file before relying on it, fall back to FxUI's own drawing for a missing file, and report each missing file once.

### Theme setting

- The standalone addon MUST offer the global theme as a dropdown in Options → AddOns → FxUI listing every registered theme by title; choosing one MUST apply and save it.
- Because theme addons load after FxUI, the saved theme MUST be applied once the player has logged in, or as soon as a theme addon that registers it loads later.

#### Scenario: Saved theme

- **GIVEN** the user chose a theme from a theme addon in the dropdown
- **WHEN** the UI reloads
- **THEN** that theme is the global theme once login completes

## Design

### Resolution

A theme definition resolves to a flat table: color tokens as color tables at the top level (`theme.gold.r/g/b/a/hex`), `fonts` (one client font object per theme and token, named `FxUIFont_<theme>_<token>`), `fontSpecs`, `surfaces`, `skins`, `metrics`, `money`, `space`, `radius`. Registered themes are cached by name and rebuilt on every registration; unregistered tables are cached weakly per table and rebuilt, keeping their font object names, the first time they are used after a registration. A mount keeps its `opts.theme` reference and resolves it again on every update. `UI.theme` is the resolved global theme and `UI.themeName` its name. While a subtree with its own theme renders, lays out or handles an event, that theme is the active one, and token lookups go through it.

`UI.font(token)` and `UI.fontSpec(token)` return the active theme's font object and spec.

## Constraints

- Client backdrops come from the client's backdrop mixin; where it is missing, backdrop surfaces fall back to flat ones.

## Open Questions

None.

## References

- [Theme tokens](../theme-tokens/), [Theme addons](../theme-addons/), [Components](../components/), [Data components](../data-components/)

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-26 | Initial spec created from the implementation | [0001-fxui-core](../../changes/0001-fxui-core.md) |
