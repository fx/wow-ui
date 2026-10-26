# 0008: Toggle group and item cells in rows

## Summary

Adds `UI.ToggleGroup`, a few mutually exclusive choices side by side (a chart's period, a view), and makes an item cell without its own click select the list row it sits in, so a click on an item's name behaves like a click on its row.

**Spec:** [Components](../specs/components/#toggle-group), [Data components](../specs/data-components/#item-cell)
**Status:** in-progress
**Depends On:** 0007

## Motivation

- Screens built rows of buttons by hand for a choice of a few; the look and the "nothing on re-click" rule were repeated each time.
- In a selectable table, clicking the item's name did nothing: the item cell took the click and the row never saw it.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)): `mise run test` passes against the strict stub, coverage stays at or above 80 %, no test is skipped.

### Functional requirements

The [components spec](../specs/components/#toggle-group) owns the toggle group; the [data components spec](../specs/data-components/#item-cell) the item cell's click.

## Design

### Decisions

- **Composed of buttons** (secondary for the chosen one, ghost for the rest) on the `inset` surface: every theme already styles both, so the group needs no skin entry of its own.
- **Row selection through the list** (`I.rowSelect`), sharing the row lookup with the right-click menu: an item cell with its own `onClick` keeps its clicks.

## Tasks

- [x] `UI.ToggleGroup` in `FxUI/Components/Controls.lua`; demo card
- [x] Item cells select their row (`I.rowSelect`)
- [x] Tests; components and data components specs
- [ ] Acceptance: `mise run test` passes; CI green

## Open Questions

- None.

## References

- Specs: [Components](../specs/components/), [Data components](../specs/data-components/)
