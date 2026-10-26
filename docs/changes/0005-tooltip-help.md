# 0005: Tooltip and help

## Summary

Adds FxUI's own tooltip, drawn in the active theme (`UI.showTooltip`, `UI.hideTooltip`, `UI.tooltipOwner`), and `UI.Help`, a small `?` icon that explains something in that tooltip, so screens can drop lines of explanatory text. Buttons and sliders show their `tooltip` in it; item cells keep the client's item tooltip.

**Spec:** [Components](../specs/components/#tooltip)
**Status:** in-progress
**Depends On:** 0001

## Motivation

- Explanations of marks and columns spelled out as muted text crowd a screen and are read once. A help icon keeps them one hover away.
- The client's tooltip did not follow FxUI's themes.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)): `mise run test` passes against the strict stub, coverage stays at or above 80 %, no test is skipped.

### Functional requirements

The [components spec](../specs/components/#tooltip) owns the tooltip and the help icon; its scenario is this change's acceptance criterion. The default theme and the Classic theme gain a `tooltip` surface role ([theme tokens](../specs/theme-tokens/), [theme addons](../specs/theme-addons/)); the skin contract gains `Help`.

## Design

### Decisions

- **One tooltip, a mounted tree** at `TOOLTIP` strata, like the toast stack: themed through a `tooltip` surface role, measured before it is laid out so it fits its content.
- **In `Controls.lua`**, not a new file, so the library's `.toc` is unchanged and an update needs no client restart.

### Non-Goals

- Rich tooltip content (icons, columns), Classic-theme art for the help icon.

## Tasks

- [x] Tooltip and `UI.Help` in `FxUI/Components/Controls.lua`; buttons and sliders use the tooltip
- [x] `tooltip` surface role in the default and Classic themes
- [x] Tests: content, sizing, placement, owners, release; the skin hook; button and slider tooltips
- [x] Component demo: a Help card
- [x] Specs: components, theme tokens, theme addons
- [ ] Acceptance: `mise run test` and the coverage gate pass; CI green; the privacy search finds nothing

## Open Questions

- None.

## References

- Spec: [Components](../specs/components/), [Theme tokens](../specs/theme-tokens/)
