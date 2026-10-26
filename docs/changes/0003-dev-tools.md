# 0003: Dev tools

## Summary

Deliver the developer tools: the `FxUI_Dev` addon (dev window, component demo, snapshots, element picker, settings, key bindings), the snapshot reader `tools/inspect.lua`, and the `fxui` agent skill, with their tests, and extend CI and the coverage gate to them. The behaviour delivered is owned by the [dev tools](../specs/dev-tools/) spec.

**Spec:** [Dev tools](../specs/dev-tools/)
**Status:** draft
**Depends On:** 0001, 0002

## Motivation

- The tools are how FxUI is inspected in the client; they are a separate slice on top of the library ([0001](./0001-fxui-core.md)).
- Their tests switch the demo between the default, Teal and Classic themes and snapshot every demo tab in Classic, so they need the theme addons ([0002](./0002-theme-addons.md)).

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)). CI enforces these as merge gates:

- `mise run test` (Lua 5.1, against the strict stub in `tests/wow.lua`) MUST pass with no test reporting an error through the error handler.
- Any client API the dev tools call MUST exist in the stub; the stub MUST NOT be loosened to accept unknown methods.
- CI MUST fail when line coverage of the repository's own Lua code, now including `FxUI_Dev/` and `tools/inspect.lua` and still excluding `tests/` and any `Libs/` folder, is below 80 %.
- No test may be skipped.

Skipping or weakening any of these rules to land the PR MUST be treated as a bug in the PR, not in the rule.

### Functional requirements

The [dev tools](../specs/dev-tools/) spec owns the commands, snapshots, picker, dev window, settings, demo, reader and skill, with their scenarios; those scenarios are this change's acceptance criteria and are not restated here. What delivering them requires of this change:

- The code MUST be delivered as built, with the same limits on further changes as [0001](./0001-fxui-core.md).
- The tests that need the dev tools MUST land here: the demo (every tab renders, items load, theme switching), the reader on a snapshot with non-finite geometry, `/fx dev all` with the reader's output (every demo tab at both window sizes, in the default theme and in Classic), the picker, the dev window, reopening after a reload, the settings, and the demo-driven part of the FxUI scale test.
- Coverage MUST count `tools/inspect.lua`, which the tests run as a separate Lua process; that process must load the coverage tool too.
- The `mise` `inspect` task and the README sections on the development workflow, slash commands and the dev tools MUST land here.
- The agent-skill link that tools expecting `.claude/skills/` read (`.claude/skills/fxui`, a relative symbolic link to `../../.agents/skills/fxui`) MUST land here with the skill.
- The skill and demo data MUST stay generic: no user names, account or character names, or local paths.

### Acceptance criteria

- Every scenario in the [dev tools](../specs/dev-tools/) spec is exercised by a headless test, except where the stub cannot represent the behaviour (a real reload writing SavedVariables, real key bindings).
- CI is green on the pull request, including the coverage gate over the library, the theme addons, `FxUI_Dev/` and `tools/inspect.lua`.
- The privacy grep from [0001](./0001-fxui-core.md) finds only genuine false positives.

## Design

### Approach

The addon, reader and skill are taken from the working implementation as they are. The snapshot tests write the stub's SavedVariables to a temporary file and run the reader on it with the interpreter running the tests.

### Decisions

- **Run the reader under coverage in a subprocess** (for example by passing `-lluacov` to the interpreter the tests start).
  - **Why:** the reader is a command-line program and is tested the way it is used.
  - **Alternatives considered:** loading the reader in-process (changes how it is exercised; it calls `os.exit`).

### Non-Goals

- New dev-tool features, compact component variants, or changes to the snapshot format.

## Tasks

- [ ] Deliver the dev tools, reader and agent skill with their tests and CI coverage (one PR)
  - [ ] `FxUI_Dev/`: `FxUI_Dev.toc`, `Bindings.xml`, `Demo.lua`, `Dev.lua`
  - [ ] Snapshot reader: `tools/inspect.lua`, and the `inspect` task in `mise.toml`
  - [ ] Agent skill: `.agents/skills/fxui/SKILL.md` and the `.claude/skills/fxui` link
  - [ ] Tests: the dev-tool tests listed in Functional requirements, plus whatever the coverage gate needs
  - [ ] CI: coverage measured over `FxUI_Dev/` and `tools/inspect.lua` as well
  - [ ] README development-workflow, slash-command and dev-tool sections
  - [ ] Tracking: mark these tasks done and set this document, `docs/index.yml` and `docs/index.md` to `complete`

## Open Questions

None.

## References

- Spec: [Dev tools](../specs/dev-tools/)
- Related changes: [0001-fxui-core](./0001-fxui-core.md), [0002-theme-addons](./0002-theme-addons.md)
