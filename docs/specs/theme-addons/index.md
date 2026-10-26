# Theme Addons

## Overview

FxUI ships two theme addons beside the core library: **Classic** (`FxUI_Theme_Classic`), which draws FxUI with the vanilla-era art the client still ships, and **Teal** (`FxUI_Theme_Teal`), the default dark theme with a teal accent and the smallest example of a theme addon. This spec owns what each theme looks like and how it behaves. The theme engine, skins and the theme setting are owned by [theming](../theming/); token names and the default theme's values by [theme tokens](../theme-tokens/).

## Background

- Each theme addon depends on FxUI and registers its theme with `UI.registerTheme` when it loads; once registered it appears in the theme dropdown and can be named by any element, mount or `UI.setTheme` ([theming](../theming/)).
- Classic's art and layouts follow the client's own UI source (FrameXML) and, as a second reference, AceGUI's containers. Maintainer notes with the measured texture coordinates live in `FxUI_Theme_Classic/AGENTS.md`.
- Delivered by [0002](../../changes/0002-theme-addons.md).

## Requirements

### Teal

- Teal MUST register as `teal` (title "FxUI Teal") with base `default`, overriding only `gold` (`#3FC1B0`) and `onGold` (`#06201C`); everything else is the default theme's.

#### Scenario: Teal accent

- **GIVEN** Teal is the global theme
- **WHEN** a primary button renders
- **THEN** it is filled `#3FC1B0`, and every other color, font and metric is the default theme's

### Classic: registration and tokens

- Classic MUST register as `classic` (title "Classic") with base `default`.
- Classic MUST use the client's fonts with shadows: Friz Quadrata for text, Morpheus for `display`, Arial Narrow for `mono` and `monoSmall`.
- Classic MUST draw money with coin icons.
- Classic MUST use the client's own item-quality colors, including Rare `#0070DD` and Epic `#A335EE`, which reach about 4.1:1 and 4.0:1 on its panel color (the default theme's 4.5:1 rule does not bind it; [theme tokens](../theme-tokens/#text-contrast)).
- Secondary text (`muted`) MUST be the client's gold (`#FFD100`), values and body text white.

#### Scenario: Coin icons only inside Classic

- **GIVEN** a tree mounted with `{ theme = "classic" }` and the global theme left at default
- **WHEN** money is formatted outside that tree, then with Classic as the global theme
- **THEN** it uses letters outside, and coin icons once Classic is global

### Classic: component look

Classic MUST draw each component with client art as follows, keeping the behaviour [components](../components/) and [data components](../data-components/) specify:

| Component | Classic drawing |
|-----------|-----------------|
| Window | Dialog-box backdrop; gold title banner across the top border; a thin header strip when only the title is in the header (close button in the top-right corner); the red close button |
| Window status and actions | In a footer status bar framed like a tooltip, spanning the full inner width; actions as secondary buttons |
| Button | Red panel-button art in three slices, gold text that turns white on hover, gray when disabled, pressed art and a 1 px text offset when pressed; `ghost` buttons are text only |
| Toggle | The checkbox (box, check, highlight) instead of a switch |
| Tabs | The Options-window tab art for every tab, inactive tabs darkened (lighter on hover), all tabs hanging alike so their feet land on the rail, text at the same height in every tab |
| Tab rail | The top edge of a tooltip border, drawn over the tabs' bottoms, with a gap under the selected tab measured from where its art is on screen, so the selected tab opens into the panel |
| Badge | A thin tooltip frame bordered in the tone with tone text; `solid` badges a darkened tone fill with white text |
| Meter | A 16 px status bar in a thin tooltip frame, the value text centred in the bar |
| List rows | The quest-log highlight on hover, gold when selected or pressed |
| Table headers | The Who-list column tabs; the sorted column's title in gold |
| Item cell | A square icon in the quality-tinted icon frame |
| Scrollbar | An 18 px gutter with the fixed 16 × 24 scroll knob, never stretched, on a faint dark track |
| Chart tags | Tooltip frames; the last-price tag bordered and lettered in its tone on black |
| Cards, toasts, insets | Tooltip-style backdrops |

#### Scenario: Classic window and table

- **GIVEN** a Classic window with a TabBar (first tab selected) and a Table with row 2 selected
- **WHEN** it renders
- **THEN** every tab uses the tab art with the inactive one darkened, the rail draws above the tabs with a gap under the first tab's art, the title banner shows, the header is a thin strip, the column header uses the column-tab art, and row 2 is highlighted

#### Scenario: Status and actions move to the footer

- **GIVEN** a window with a status text and one action
- **WHEN** it renders in Classic
- **THEN** the header holds only the title and close button, and the footer holds the status followed by the action, drawn as a status bar

#### Scenario: Back to the default theme

- **GIVEN** a Classic window was rendered
- **WHEN** the same tree re-renders under the default theme
- **THEN** the tab art, banner and row highlights are hidden, tabs carry no underline, and the default rail is continuous with the selected tab marked on it

### Classic: missing art

- Before drawing with a client file, Classic MUST check that the client ships it; for a missing file it MUST draw that part with FxUI's own or flat drawing and report the file once through the error handler ("FxUI Classic: the client has no <path>; using FxUI's own drawing for it").
- Classic MUST check each file on its own, secondary art (check marks, highlights) included: a missing secondary file MUST NOT take the primary art with it, and the part it draws MUST fall back or be left out on its own.
- Classic MUST only use client art that still ships in the retail client.

#### Scenario: Missing button art

- **GIVEN** the client lacks the panel-button texture
- **WHEN** a Classic button renders
- **THEN** it draws a flat background and the missing path is reported once

#### Scenario: Missing check mark

- **GIVEN** the client ships the checkbox but not its check-mark or highlight textures
- **WHEN** a checked Classic toggle renders
- **THEN** it keeps the checkbox art with a flat check inside it (gold, gray when disabled), shows no highlight, and each missing path is reported once

## Design

### Classic metrics

| Component | Metrics |
|-----------|---------|
| Button | `sizes`: `sm` 20 / pad 10, `md` 22 / 14, `lg` 26 / 18 |
| Toggle | width 24, height 24, gap 4 |
| Tab | height 30, pad 22, gap −10 (tabs overlap), `openSelected`, rail 5 in `#666666`, `railAbove`, no `railHighlight` |
| Badge | height 18, pad 7 |
| Meter | `barHeight` 16, `inlineValue` |
| HeaderCell | height 19, pad 8 |
| Scroll | width 18, thumb 16 |
| Window | `status` and `actions` = `footer`; `md`: header 34, `title` font, pad 18, close 32, inset 10, gold title, `banner`, footer 28; `sm`: header 30, `strong` font, pad 14, close 28, inset 8, `banner`, footer 26 |

### Classic tab geometry

The Options-window tab art is designed 24 tall; Classic draws it 30 tall and scales every vertical measure by 30/24. Every tab's art hangs 5 art units below the tab row (6.25 px), with the label 2 units above the art's centre (−3.75 px). The rail opens 9.5 px inside the selected tab art's left and right edges, just inside its flared feet (measured at 10.4 units in). The texture coordinates for every slice are recorded in the theme's maintainer notes.

### Classic colors

`ground` `#000000`, `panel` `#0B0B0B`, `raised` `#1E1E1E`, `line` `#5A4A2A`, `text` `#FFFFFF`, `muted` and `gold` `#FFD100`, `onGold` `#000000`, `info` `#69CCF0`, `up` `#1EFF00`, `down` `#FF3030`, `warn` `#FF8000`; quality colors are the client's (`#9D9D9D`, `#FFFFFF`, `#1EFF00`, `#0070DD`, `#A335EE`, `#FF8000`).

## Constraints

- Classic depends on files the retail client ships; a client update can remove one, which is why every file is probed and has a fallback.

## Open Questions

- **Classic top tabs.** The client's own classic top-tab art (`TabButtonTemplate`) is not confirmed to ship in retail, so Classic uses the Options-window tab art instead. Switching is open.

## References

- [Theming](../theming/), [Theme tokens](../theme-tokens/), [Components](../components/)
- Client UI source mirror: <https://github.com/Gethe/wow-ui-source>

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-26 | Initial spec created from the implementation | [0002-theme-addons](../../changes/0002-theme-addons.md) |
