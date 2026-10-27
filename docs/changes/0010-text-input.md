# 0010: Text input

## Summary

Adds `UI.TextInput`: a one-line text field with a placeholder, a controlled `value`, Enter and Escape, links the player shift-clicks while it has the focus, and an optional suggestion list under it to pick from with the keyboard or the mouse; plus a demo card.

**Spec:** [Components](../specs/components/#text-input), [Data components](../specs/data-components/#item-cell)
**Status:** complete
**Depends On:** 0007

## Motivation

- FxUI had no way to type anything: an addon could not offer a search, or let the player name an item other than through a slash command.
- In the client, shift-clicking an item puts its link where the player is typing; an addon's own input should take it like the chat line does.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)): `mise run test` passes against the strict stub, coverage stays at or above 80 %, no test is skipped.

### Functional requirements

The [components spec](../specs/components/#text-input) owns the text input; its scenario is this change's acceptance criterion. The [data components spec](../specs/data-components/#item-cell) owns the item cell's shift-click.

## Design

### Decisions

- **Post-hooks for links.** `hooksecurefunc` on both of the client's insert functions leaves the client's code untouched (no taint) and catches a link whichever one the client calls; a link seen twice in one frame (one calling the other) goes in once. The hook is installed once, by the first input, for every copy of the library.
- **Controlled when `value` is given**, like Toggle and Slider; uncontrolled without it, so a plain search box needs no state.
- **Suggestions are the consumer's**: `suggest(text)` returns what to show, so any source (items, names, commands) works; FxUI only lists, moves and picks.
- **No skin entry**: the input draws with the theme's `inset` surface, so a theme styles it through its surfaces.
- **The item cell looks the insert up at each click**, so a hook installed after it loaded sees its links.

### Non-Goals

- Multi-line input, a search icon, or a clear button.
- Filtering or ranking suggestions inside FxUI.

## Tasks

- [x] `UI.TextInput` in `FxUI/Components/Controls.lua`: focus, typing, value, placeholder, Enter, Escape, disabled; link hook; suggestions
- [x] Item cell: the client's insert looked up at each click
- [x] Strict stub: EditBox, `hooksecurefunc`, `GetTime`, `ChatFrameUtil.InsertLink`
- [x] Tests: typing and value, surface in both themes, suggestions (keys, click, item cells, focus), links (once, both inserts, `onLink`, inputs without links), the item cell's shift-click
- [x] Component demo: a Text input card
- [x] Components and data components specs
- [x] Acceptance: `mise run test` and the coverage gate pass; CI green; the privacy search finds nothing

## Open Questions

- None.

## References

- Spec: [Components](../specs/components/)
