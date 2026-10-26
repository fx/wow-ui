# 0006: Pressable

## Summary

Adds `UI.Pressable`, a container that makes any content a click target: a price over its change, an icon with a label. It stacks its children like `VStack` (or `HStack`), shades on hover and press, shows a tooltip and calls `onClick`.

**Spec:** [Components](../specs/components/#pressable)
**Status:** in-progress
**Depends On:** 0005

## Motivation

- `UI.Button` takes only text. A cell that shows formatted content (money, a two-line value) had no way to be clicked.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)): `mise run test` passes against the strict stub, coverage stays at or above 80 %, no test is skipped.

### Functional requirements

The [components spec](../specs/components/#pressable) owns it; its scenario is this change's acceptance criterion. The skin contract gains `Pressable`.

## Design

### Decisions

- **A container host on a client `Button`**, laid out with the stack helpers, so it takes the stack props and needs no layout of its own.
- **Shade, not a border**: it sits inside tables and rows, where a resting border would add noise; at rest it draws nothing.
- **In `Controls.lua`**, so the library's `.toc` is unchanged.

### Non-Goals

- Keyboard focus, secure (protected) clicks: a Pressable is for plain UI actions; protected calls stay on `UI.Button` with `secure`.

## Tasks

- [x] `UI.Pressable` in `FxUI/Components/Controls.lua`
- [x] Test; demo card; components spec
- [ ] Acceptance: `mise run test` passes; CI green

## Open Questions

- None.

## References

- Spec: [Components](../specs/components/)
