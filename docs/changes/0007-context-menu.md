# 0007: Context menu

## Summary

Adds `UI.showMenu`, one themed context menu at the cursor whose items are [Pressables](0006-pressable.md), closed by choosing an item or clicking anywhere else, and `onContextMenu(item, i, key)` on lists and tables for a right-clicked row.

**Spec:** [Components](../specs/components/#context-menu), [Data components](../specs/data-components/#list)
**Status:** complete
**Depends On:** 0005, 0006

## Motivation

- Secondary actions on a row (open it elsewhere, refresh it) had no place but more buttons in the row.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)): `mise run test` passes against the strict stub, coverage stays at or above 80 %, no test is skipped.

### Functional requirements

The [components spec](../specs/components/#context-menu) owns the menu; the [data components spec](../specs/data-components/#list) the row right-click. Their scenarios are this change's acceptance criteria.

## Design

### Decisions

- **One menu, a mounted tree**, like the tooltip: kept across library upgrades in `I.menu`, drawn in the `tooltip` surface so themes style both alike.
- **A full-screen catcher** under the menu at `FULLSCREEN_DIALOG` strata takes the pointer: the click that closes the menu does nothing else, and nothing under it shows a tooltip. Opening the menu hides any tooltip already up, and polled hover (list rows, chart crosshairs) pauses while it is open.
- **Right clicks inside rows reach the row's menu**: a button, item cell or Pressable in a list row leaves a right click to the row (`I.rowContextMenu`), since the client delivers it to the control, not the list; a right click therefore never runs a button in such a row.
- **No client menu** (`MenuUtil`): it does not follow FxUI's themes.
- **In `Controls.lua`**, so the library's `.toc` is unchanged.

### Non-Goals

- Submenus, check and radio items, keyboard navigation.

## Tasks

- [x] `UI.showMenu`, `UI.hideMenu`, `UI.menuOwner` in `FxUI/Components/Controls.lua`
- [x] `onContextMenu` on `UI.List`, passed through by `UI.Table`
- [x] Tests; demo; components and data components specs
- [x] Acceptance: `mise run test` passes; CI green

## Open Questions

- None.

## References

- Specs: [Components](../specs/components/), [Data components](../specs/data-components/)
