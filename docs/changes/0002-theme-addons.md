# 0002: Theme addons

## Summary

Deliver the two theme addons, `FxUI_Theme_Classic` and `FxUI_Theme_Teal`, with their tests, and extend CI and the coverage gate to them. The behaviour delivered is owned by the [theme addons](../specs/theme-addons/) spec; the engine they plug into by [theming](../specs/theming/).

**Spec:** [Theme addons](../specs/theme-addons/)
**Status:** complete
**Depends On:** 0001

## Motivation

- The theme engine, skins and the theme setting land with the core library ([0001](./0001-fxui-core.md)); the shipped themes that use them are a separate, reviewable slice.
- The dev tools ([0003](./0003-dev-tools.md)) switch between these themes in their tests, so they land before it.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)). CI enforces these as merge gates:

- `mise run test` (Lua 5.1, against the strict stub in `tests/wow.lua`) MUST pass with no test reporting an error through the error handler.
- Any client API the theme addons call MUST exist in the stub; the stub MUST NOT be loosened to accept unknown methods.
- CI MUST fail when line coverage of the repository's own Lua code, now including both theme addons and still excluding `tests/` and any `Libs/` folder, is below 80 %.
- No test may be skipped.

Skipping or weakening any of these rules to land the PR MUST be treated as a bug in the PR, not in the rule.

### Functional requirements

The [theme addons](../specs/theme-addons/) spec owns how Classic and Teal look and behave, with its scenarios; those scenarios are this change's acceptance criteria and are not restated here. What delivering them requires of this change:

- The code MUST be delivered as built, with the same limits on further changes as [0001](./0001-fxui-core.md).
- The tests that need a theme addon MUST land here: Classic's skins and their clean-up when a pooled region returns to the default theme, Classic's window status and action placement, Classic's fallback when client art is missing, and the theme dropdown listing Classic and Teal. Teal MUST get a test of its own.
- The CI coverage measurement MUST include `FxUI_Theme_Classic/` and `FxUI_Theme_Teal/`.
- README rows and instruction-file references for the theme addons (for example the link from the built-in theme's notes to Classic's notes) MUST land here.

### Acceptance criteria

- Every scenario in the [theme addons](../specs/theme-addons/) spec is exercised by a headless test, except where the stub cannot represent the behaviour (rendered pixels, real client art).
- CI is green on the pull request, including the coverage gate over the library and both theme addons.
- The privacy grep from [0001](./0001-fxui-core.md) finds only genuine false positives.

## Design

### Approach

The theme addons are taken from the working implementation as they are. The test file loads them after FxUI (as the client does), and the theme-dependent tests move here from the working suite.

### Decisions

- **Classic keeps the client's quality colors** even though Rare and Epic fall below 4.5:1 on its panel.
  - **Why:** Classic reproduces the client's own look; the contrast rule binds the built-in default theme ([theme tokens](../specs/theme-tokens/#text-contrast)).
  - **Alternatives considered:** lifting Classic's quality colors like the default theme's (departs from the look the theme exists to reproduce).

### Non-Goals

- New themes, new skins or changes to the theme engine.
- Switching Classic to the client's own classic top-tab art (an open question in the spec).

## Tasks

- [x] Deliver the Classic and Teal theme addons with their tests and CI coverage (one PR)
  - [x] `FxUI_Theme_Classic/`: `FxUI_Theme_Classic.toc`, `Classic.lua`, `AGENTS.md`, `CLAUDE.md`
  - [x] `FxUI_Theme_Teal/`: `FxUI_Theme_Teal.toc`, `Teal.lua`
  - [x] Tests: the theme-dependent tests listed in Functional requirements, plus a Teal test and whatever the coverage gate needs
  - [x] CI: coverage measured over both theme addons as well
  - [x] README rows and instruction-file references for the theme addons
  - [x] Tracking: mark these tasks done and set this document, `docs/index.yml` and `docs/index.md` to `complete`

## Open Questions

None.

## References

- Spec: [Theme addons](../specs/theme-addons/), [Theming](../specs/theming/)
- Related changes: [0001-fxui-core](./0001-fxui-core.md), [0003-dev-tools](./0003-dev-tools.md)
