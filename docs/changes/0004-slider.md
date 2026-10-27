# 0004: Slider

## Summary

Adds `UI.Slider`: a controlled horizontal slider over a numeric range or a list of stops, with press, drag and wheel input, a value label with stable room, a skin hook, and an entry in the component demo.

**Spec:** [Components](../specs/components/#slider)
**Status:** complete
**Depends On:** 0001

## Motivation

- Addons need to let the player pick a threshold (a minimum price, a level) without typing; FxUI had no input for a number.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)): `mise run test` passes against the strict stub, coverage stays at or above 80 %, no test is skipped.

### Functional requirements

The [components spec](../specs/components/#slider) owns the slider; its scenario is this change's acceptance criterion. The skin contract gains a `Slider` entry, and the skinned-theme test covers it.

## Design

### Decisions

- **Stops, not a free value.** A list of stops covers both an even range and one that grows faster than linearly (money thresholds), with the same evenly spaced track.
- **Controlled, like Toggle.** The slider reports the stop it moved to and draws the `value` it is given.

### Non-Goals

- A vertical slider, keyboard input, or Classic-theme art for the slider (it draws with the theme's colours).

## Tasks

- [x] `UI.Slider` in `FxUI/Components/Controls.lua`
- [x] Tests: stops, press, drag, wheel, value room, disabled; the skin hook
- [x] Component demo: a Sliders card
- [x] Components spec: Slider requirements and skin contract
- [x] Acceptance: `mise run test` and the coverage gate pass; CI green; the privacy search finds nothing

## Open Questions

- None.

## References

- Spec: [Components](../specs/components/)
