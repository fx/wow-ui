# 0001: FxUI core library

## Summary

Deliver the FxUI core library addon (`FxUI/`) with its built-in default theme, media and media generators, the headless test harness and library tests, the repository's instruction files and tooling, this documentation tree, and CI with an 80 % line-coverage gate. The behaviour delivered is owned by the [architecture](../specs/architecture/), [rendering](../specs/rendering/), [layout](../specs/layout/), [components](../specs/components/), [data components](../specs/data-components/), [theme tokens](../specs/theme-tokens/) and [theming](../specs/theming/) specs.

**Spec:** [Architecture](../specs/architecture/)
**Status:** complete
**Depends On:** —

## Motivation

- `main` holds only a placeholder README. The library already exists and was exercised in the client; this change delivers it as the first reviewable slice, with the specs describing it as built.
- Later slices (theme addons, [0002](./0002-theme-addons.md); dev tools, [0003](./0003-dev-tools.md)) depend on the library, the test harness and CI landing first.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)). CI enforces these as merge gates:

- `mise run test` (Lua 5.1, against the strict stub in `tests/wow.lua`) MUST pass with no test reporting an error through the error handler.
- Any client API the delivered code calls MUST exist in the stub; the stub MUST NOT be loosened to accept unknown methods.
- CI MUST run the tests on every pull request and on pushes to `main`.
- CI MUST fail when line coverage of the repository's own Lua code, excluding `tests/` and any `Libs/` folder, is below 80 %.
- No test may be skipped.

Skipping or weakening any of these rules to land the PR MUST be treated as a bug in the PR, not in the rule.

### Functional requirements

The specs listed in the Summary own every behaviour this change delivers, with their scenarios; those scenarios are this change's acceptance criteria and are not restated here. What delivering them requires of this change:

- The code MUST be delivered as built. Changes beyond the delivered files are limited to removing any personal identifier, the tests and test infrastructure needed for CI and the coverage gate, and fixes to defects a reviewer proves.
- The test suite in this change MUST load only the `FxUI` addon. Tests that load a theme addon or the dev tools addon land with that addon ([0002](./0002-theme-addons.md), [0003](./0003-dev-tools.md)); the library behaviour those tests also covered MUST be covered here by tests that need only FxUI.
- `AGENTS.md` MUST document the coverage policy: the 80 % line-coverage gate, what it measures and excludes, and how to run it locally.
- Files delivered here MUST describe only what exists on `main` once this change lands; README rows, instruction-file references and `mise` tasks for the theme addons and dev tools land with those changes.
- Nothing in the repository may name, describe or link a specific consumer project, a private repository, a private design document or a local path, nor carry any account or character name.

#### Scenario: Library-only test run

- **GIVEN** a checkout with only this change applied
- **WHEN** `mise run test` runs
- **THEN** every test passes without `FxUI_Theme_Classic`, `FxUI_Theme_Teal` or `FxUI_Dev` present

#### Scenario: Coverage gate in CI

- **GIVEN** the pull request for this change
- **WHEN** CI runs
- **THEN** the test job passes and the coverage job reports at least 80 % line coverage of `FxUI/` (excluding `FxUI/Libs/`)

### Acceptance criteria

- Every scenario in the specs listed in the Summary that concerns the core library is exercised by a headless test, except where the stub cannot represent the behaviour (rendered pixels).
- CI is green on the pull request, including the coverage gate.
- The repository contains no reference to a consumer project, a private repository, a private design document or a local filesystem path, and no account or character name.

## Design

### Approach

The files are taken from the working implementation as they are. The single test file is split by dependency: library tests stay in `tests/run.lua` (or files it loads); tests needing a theme addon or the dev tools move to the change that delivers that addon. Three existing tests mix library and addon behaviour and need a library-only counterpart here:

| Existing test | Library-only coverage needed here |
|---------------|-----------------------------------|
| Window status and actions placement (also checks Classic) | Default-theme placement, no forced footer, explicit footer |
| Options theme dropdown (lists Classic and Teal) | Dropdown lists registered themes (register one in the test), sets and saves the global theme, saved theme applied at login and on late registration |
| FxUI scale (drives the demo window) | Scale slider and label, clamping, a free window keeps its top-left and saves its geometry with the scale, toasts follow the scale |

Further tests are added where needed to reach the coverage gate (for example item cells, meters, sparklines, toasts, docking, Ctx helpers, error reporting).

### Decisions

- **Coverage with luacov, gated in CI.**
  - **Why:** the project's code is Lua 5.1 and luacov is the standard line-coverage tool for it; a gate inside CI needs no third-party service.
  - **Alternatives considered:** a hosted coverage service (not configured, and out of scope).
- **CI installs tools the way developers do** (recommended: through `mise`, so Lua 5.1.5 matches `mise.toml`), plus luarocks for luacov.
  - **Why:** one tool definition for local runs and CI.
  - **Alternatives considered:** a separate Lua setup action pinned independently.
- **The threshold is 80 % lines over the repository's own Lua code**, measured on the code present on `main` after each change; vendored `Libs/` and `tests/` are excluded.
  - **Why:** no threshold was documented before; 80 % is a safe default that the existing suite can reach with modest additions.
  - **Alternatives considered:** per-file thresholds (stricter, noisy for thin glue files).

### Non-Goals

- New components, behaviour changes or refactors beyond what the Functional requirements allow.
- Theme addons and dev tools ([0002](./0002-theme-addons.md), [0003](./0003-dev-tools.md)).
- Releases, packaging, a licence file, repository settings and branch protection.
- WoW: Forever support.

## Tasks

- [x] Deliver the FxUI core library, its tests, tooling, docs and CI (one PR)
  - [x] `FxUI/`: `FxUI.toc`, `Core.lua`, `Theme.lua`, `Themes/Default.lua`, `Format.lua`, `Render.lua`, `Surface.lua`, `Commands.lua`, `Scale.lua`, `Components/` (`Layout.lua`, `Controls.lua`, `Data.lua`, `List.lua`, `Table.lua`, `Window.lua`, `Toast.lua`), `Libs/LibStub/LibStub.lua`, `Media/Fonts/` (four TTFs and three `OFL-*.txt`), `Media/Textures/` (`Round4`, `Round4Ring`, `Round8`, `Round8Ring`, `Circle` `.tga`)
  - [x] `FxUI/Themes/AGENTS.md` and `FxUI/Themes/CLAUDE.md` (built-in theme notes; references to later slices land with them)
  - [x] Media generators: `tools/build-fonts.py`, `tools/build-textures.py`, `tools/requirements.txt`
  - [x] Test harness: `tests/wow.lua` and the library tests in `tests/run.lua`, split as in Design, with the library-only counterparts and the tests needed for the coverage gate
  - [x] Repository files: `mise.toml` (tools; `test`, `coverage`, `fonts`, `textures` tasks), `README.md` (library sections only), `AGENTS.md` (with the coverage policy), `CLAUDE.md`, `REVIEW.md`, `.coderabbit.yaml`, `.gitignore`
  - [x] Documentation: the `docs/` tree (specs, change documents `0001`–`0003`, indexes, `tasks.md`)
  - [x] CI: a GitHub Actions workflow under `.github/workflows/` running the tests on pull requests and pushes to `main`, measuring line coverage with luacov (excluding `tests/` and `Libs/`) and failing below 80 %
  - [x] Tracking: mark these tasks done and set this document, `docs/index.yml` and `docs/index.md` to `complete`

## Open Questions

None.

## References

- Specs: [Architecture](../specs/architecture/), [Rendering](../specs/rendering/), [Layout](../specs/layout/), [Components](../specs/components/), [Data components](../specs/data-components/), [Theme tokens](../specs/theme-tokens/), [Theming](../specs/theming/)
- Related changes: [0002-theme-addons](./0002-theme-addons.md), [0003-dev-tools](./0003-dev-tools.md)
- luacov: <https://lunarmodules.github.io/luacov/>
