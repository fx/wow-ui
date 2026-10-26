# Theme Tokens

## Overview

Theme tokens are the named colors, font styles, surface roles, spacing steps and radii that FxUI components read. They are the public styling contract between FxUI and its consumers: consumers MAY reference tokens by name and MUST NOT depend on their raw values. This spec owns the token names, the built-in default theme's values, the text-contrast rule and money formatting. How themes define, inherit and apply tokens is owned by [theming](../theming/); component behaviour by [components](../components/) and [data components](../data-components/).

## Background

- The built-in default theme ("FxUI Dark": dark, flat, gold accent) lives in the core library; every other theme inherits from it ([theming](../theming/), [theme addons](../theme-addons/)).
- Item quality colors start from the client's values; in the default theme the darker ones are lifted so small text stays legible on a panel.
- Delivered by [0001](../../changes/0001-fxui-core.md).

## Requirements

### Token names are a stable contract

- Every resolved theme MUST provide every color token, font token and surface role listed under Design, inheriting any it does not define from the default theme.
- Renaming or removing a token MUST be treated as a breaking change to `FxUI-1.0`; adding a token MAY happen in a minor version.
- Wherever a component takes a color, it MUST accept a color token name, a `#RRGGBB` or `#RRGGBBAA` literal, or a color table; an unknown token name MUST raise an error naming it.

#### Scenario: Consumer uses a token

- **GIVEN** a consumer draws a label in the `muted` color
- **WHEN** another theme becomes active
- **THEN** the label takes that theme's `muted` value and nothing errors

### Item quality colors

- `UI.qualityColor(quality)` MUST return the active theme's token for qualities 0–5 (`poor`, `common`, `uncommon`, `rare`, `epic`, `legendary`; `UI.QUALITY_TOKENS`) and the client's own color for any other quality.

### Text contrast

- In the default theme, `text`, `muted` and every item-quality color MUST reach a contrast ratio of at least 4.5:1 against `panel`. `UI.contrast(a, b)` computes the WCAG ratio between two colors.
- A theme that reproduces the client's own look MAY use the client's quality colors even where they fall below that ratio ([theme addons](../theme-addons/)).

#### Scenario: Quality text on panel

- **GIVEN** the default theme
- **WHEN** an Epic item name is drawn in its quality color on `panel`
- **THEN** its contrast against `panel` is at least 4.5:1

### Money formatting

`UI.formatMoney(copper, opts)` turns copper into display text; `UI.Money` draws it ([data components](../data-components/)).

- Input MUST be copper, rounded to a whole copper; a non-number reads as 0.
- The full form MUST read gold, silver and copper with their markers (`12g 34s 56c`), leave out zero denominations, read zero as `0c`, and group gold digits in thousands with commas.
- `compact = true` MUST show only gold at 100 g and above.
- `short = true` MUST show only the largest denomination with at most one decimal and no trailing `.0`, rounding down so it never overstates: thousands of gold as `k` gold (`1.2kg`, `12.3kg`), 100 g and above as whole grouped gold (`124g`), 1 g and above with one decimal (`7.4g`), then silver (`45s`, `4.5s`), then copper (`56c`).
- Negative values MUST start with the minus sign U+2212 (`−3s 20c`); `signed = true` MUST put `+` before positive values; zero carries no sign.
- `colored = true` MUST draw the markers in the coin colors (`coinGold`, `coinSilver`, `coinCopper`); `icons` MUST draw coin icons instead of letters, and defaults to the active theme's money style (`letters` or `icons`).
- Money digits are drawn in the `mono` font.

#### Scenario: Copper in

- **GIVEN** 123456 copper
- **WHEN** it is formatted
- **THEN** it reads `12g 34s 56c`

#### Scenario: Compact

- **GIVEN** 12403456 copper and `compact = true`
- **WHEN** it is formatted
- **THEN** it reads `1,240g`; 123456 copper with `compact` still reads `12g 34s 56c`

#### Scenario: Short

- **GIVEN** `short = true`
- **WHEN** 74000, 70000, 12403456, 4523, 450 and 74999 copper are formatted
- **THEN** they read `7.4g`, `7g`, `1.2kg`, `45s`, `4.5s` and `7.4g`

#### Scenario: Signed tone

- **GIVEN** `UI.Money { value = -320, tone = "down" }`
- **WHEN** it is drawn
- **THEN** it reads `−3s 20c` in the `down` color; `UI.formatMoney(1840, { signed = true })` reads `+18s 40c`

## Design

### Default theme: colors

| Token | Value | Use |
|-------|-------|-----|
| `ground` | `#0F1114` | Window background, cards |
| `panel` | `#171A1F` | Panels, window body, list background |
| `raised` | `#1F232A` | Headers, secondary buttons |
| `line` | `#2A2F37` | Borders, dividers |
| `text` | `#E7E3D6` | Body text |
| `muted` | `#9AA0A8` | Secondary text, labels |
| `gold` | `#E2B04A` | Primary action, accent, selection |
| `onGold` | `#1A1406` | Text on `gold` |
| `info` | `#5AA9E6` | Informational content |
| `up` | `#4CC38A` | Gains, favourable moves |
| `down` | `#F07167` | Losses, danger |
| `warn` | `#F2B66B` | Warnings |
| `coinGold` | `#FFD100` | Gold marker |
| `coinSilver` | `#C7C7CF` | Silver marker |
| `coinCopper` | `#EDA55F` | Copper marker |

### Default theme: item quality

| Token | Value | Contrast on `panel` | Source |
|-------|-------|---------------------|--------|
| `poor` | `#9D9D9D` | 6.43:1 | Client |
| `common` | `#FFFFFF` | 17.44:1 | Client |
| `uncommon` | `#1EFF00` | 12.76:1 | Client |
| `rare` | `#4FA3FF` | 6.66:1 | Lifted from the client's `#0070DD` (3.62:1) |
| `epic` | `#B86BFF` | 5.47:1 | Lifted from the client's `#A335EE` (3.57:1) |
| `legendary` | `#FF8000` | 6.93:1 | Client |

`text` reaches 13.59:1 and `muted` 6.62:1 on `panel`.

### Default theme: fonts

| Token | Face (shipped file) | Size | Notes |
|-------|---------------------|------|-------|
| `display` | Barlow Condensed SemiBold | 28 | Window titles (`md`) |
| `title` | Inter SemiBold | 18 | |
| `body` | Inter Regular | 13 | Default text |
| `strong` | Inter SemiBold | 13 | Buttons, tabs, `sm` window titles |
| `label` | Inter SemiBold | 11 | Caps: text is drawn upper-case |
| `mono` | JetBrains Mono Regular | 13 | Money, numbers |
| `small` | Inter Regular | 11 | Status text, legend labels |
| `monoSmall` | JetBrains Mono Regular | 11 | Chart labels and tags |

Default-theme fonts have no shadow.

### Default theme: surfaces, space, radius, money

| Surface role | Fill | Border | Radius |
|--------------|------|--------|--------|
| `card` | `ground` | `line` | `r8` |
| `toast` | `raised` | `#3B4047` | `r8` |
| `inset` | `panel` | `line` | `r4` |
| `plain` | — | — | — |

Spacing steps: 4, 8, 12, 16, 24. Radii: `r4` = 4 px, `r8` = 8 px, `pill` = 8 px. Money style: `letters`.

Resolved color tokens are also readable from code as fields of `UI.theme` (the global theme), e.g. `UI.theme.gold.hex`. `UI.groupDigits(n)` groups digits with commas.

## Constraints

- Fonts available in game are the files FxUI ships and the client's own fonts (which themes may reference by client path).

## Open Questions

- **Light theme.** Not built. Default: dark only.

## References

- [Theming](../theming/), [Theme addons](../theme-addons/), [Data components](../data-components/)
- [WCAG 2 contrast ratio](https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio)

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-25 | Initial spec created | — |
| 2026-10-25 | Quality color values settled; compact and signed money | — |
| 2026-10-26 | Rewritten as built: added `onGold`, `warn`, coin colors and the `strong`, `small`, `monoSmall` fonts; surface roles; short money and coin icons; contrast rule scoped to the default theme; fonts are shipped files, not LibSharedMedia | [0001-fxui-core](../../changes/0001-fxui-core.md) |
