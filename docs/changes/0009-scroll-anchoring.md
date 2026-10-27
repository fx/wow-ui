# 0009: Scroll anchoring

## Summary

A scrolled list keeps what is being read in place while its items change: a table with a row-key function no longer remounts (and jumps to the top) on every render, and rows added above the view no longer push it down when the list is given a new items table.

**Spec:** [Data components](../specs/data-components/#list), [Rendering](../specs/rendering/)
**Status:** complete
**Depends On:** 0008

## Motivation

- A table given `key = function(row) ... end` got a new closure every render; the reconciler took it as the element's identity key, so the list remounted and its scroll offset went back to 0 whenever its screen re-rendered.
- A newest-first list that gains rows while scrolled moved its content down by one row per new item.

## Requirements

### Testing Requirements

This change MUST satisfy the project's standing testing rules (see [Architecture § Testing and CI](../specs/architecture/#testing-and-ci)): `mise run test` passes against the strict stub, coverage stays at or above 80 %, no test is skipped.

### Functional requirements

The [rendering spec](../specs/rendering/) owns element identity; the [data components spec](../specs/data-components/#list) scroll anchoring.

## Design

### Decisions

- **Only strings and numbers are identity keys**: anything else under `key` is a prop for the component to use.
- **Anchor on the top row by key**, with its partial offset, and only when the list is given a new items table and is scrolled: at the top, new rows show, as in a log or feed. Edits made in place to the same table are not anchored (the list cannot tell them from a re-render); a caller that wants its place kept gives the list a new table.

## Tasks

- [x] Render: function keys are props, not identities
- [x] List: scroll anchoring
