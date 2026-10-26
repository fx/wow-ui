## Task Tracking

**You MUST load the `/project-management` skill before creating, modifying, or completing any task.** It owns all task-tracking rules and knows where tasks belong. Do not manage tasks without it.

## Code Review Rules

Read `REVIEW.md` at the repository root and apply it in full as the review rules for this repo. It is the canonical review-conventions file.

## Public Repository

This repository is public. FxUI is a general-purpose personal WoW UI component library. Never name, describe or link a specific consumer project, private repository, private design document or local path outside this repository — not in code, comments, docs, specs, commit messages or PR text. Examples use generic addon and item data.

## Tests and Coverage

- Run `mise run test` after every change: headless tests (`tests/run.lua`) under Lua 5.1 against the strict client stub (`tests/wow.lua`). Extend the stub when code starts using a new client API; never loosen it to accept unknown methods. No test may be skipped.
- Coverage policy: CI fails when line coverage of the repository's own Lua code is below **80 %**. It is measured with luacov over every Lua file the tests load, excluding `tests/` and vendored third-party code in any `Libs/` folder (`.luacov`). New code comes with the tests that keep the total at or above 80 %; do not lower the threshold or widen the exclusions to get a change through.
- Run it locally: `luarocks install luacov` once (into the Lua that `mise install` set up), then `mise run coverage`. It runs the tests under luacov and `tests/coverage.lua`, which prints each file's coverage, lowest first, and exits non-zero below 80 %.
- CI (`.github/workflows/ci.yml`) runs the tests and the coverage gate on every pull request and every push to `main`.
