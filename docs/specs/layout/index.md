# Layout

## Overview

FxUI lays a mounted tree out in two passes: a bottom-up measure that asks each element for its natural size within the space offered, and a top-down place that gives each element its final box. This spec owns the layout props every element takes, stacks (flex, alignment, justification, wrapping), spacers, text measuring and scroll areas. Element rendering and the reconciler are owned by [rendering](../rendering/); what each element draws is owned by [components](../components/) and [data components](../data-components/).

## Background

- Layout runs after every render batch and whenever a root's frame changes size ([rendering](../rendering/)).
- A Window positions itself and lays out its own header, body and footer ([components](../components/)); everything else is placed by its parent.
- Delivered by [0001](../../changes/0001-fxui-core.md).

## Requirements

### Layout props

Every element MUST accept these props:

| Prop | Meaning |
|------|---------|
| `width`, `height` | Fixed size; when both are set the element is not measured |
| `minWidth`, `minHeight` | Lower bounds on the measured size (and on a flexible child's share) |
| `maxWidth` | Upper bound on the measured width |
| `flex` | Share of a stack's free space along its main axis (0 or absent: natural size) |
| `alignSelf` | Overrides the parent stack's `align` for this child |

- Layout props given on a component element MUST win over the same props on the element its render returns.

#### Scenario: Component element carries flex

- **GIVEN** a component whose render returns a VStack with no `flex`
- **WHEN** it is used as `Page { flex = 1 }` in a VStack
- **THEN** the page takes the stack's free space

### Stacks

`UI.HStack` lays children out in a row, `UI.VStack` in a column.

- Stacks MUST accept `gap` (space between children), `padding` (a number, `{ vertical, horizontal }`, `{ top, horizontal, bottom }` or `{ top, right, bottom, left }`), `align` (`start` · `center` · `end` · `stretch`, across the main axis; default `center` for HStack and `stretch` for VStack) and `justify` (`start` · `center` · `end` · `between`, along the main axis; default `start`).
- Children without `flex` MUST get their natural size along the main axis, each measured within the space left by the children before it.
- Children with `flex` MUST share the remaining space in proportion to their `flex`, never below their `minWidth` (HStack) or `minHeight` (VStack), and MUST be measured at the share they get, so a flexible child's cross size (for example a wrapping row's height) matches its final width.
- `justify` MUST apply only when no child is flexible and there is free space; `between` spreads the free space evenly between children.
- With `align = "stretch"` (or a child's `alignSelf = "stretch"`) a child MUST fill the stack's inner cross size; otherwise its cross size is its natural size, at most the inner cross size, placed at the start, centre or end.
- Stacks MUST also accept surface props (a theme `surface` role, or `bg`, `border`, `radius`; see [theming](../theming/)), `clip` (clip children to the stack's box) and `alpha`.

#### Scenario: Flex fills

- **GIVEN** a 600 px tall VStack holding a 40 px row and a child with `flex = 1`
- **WHEN** it is laid out
- **THEN** the flexible child is 560 px tall

#### Scenario: Justify between

- **GIVEN** an HStack 300 px wide with `justify = "between"` and three 50 px children
- **WHEN** it is laid out
- **THEN** the first child starts at 0, the last ends at 300, and the gaps between them are equal

### Wrapping rows

- An HStack with `wrap = true` MUST flow its children onto new lines so that no line is wider than its inner width, with `gap` between children in a line and `rowGap` (default: `gap`) between lines; `flex` is ignored inside a wrapping row.
- Each line MUST honour `justify`, and each child is aligned within its line's height by `align` (default `center`).
- A wrapping row's measured height MUST be the sum of its lines' heights and row gaps.

#### Scenario: Seven chips in a narrow row

- **GIVEN** a 300 px wide wrapping row with `gap = 12`, `rowGap = 8` and seven 96 × 40 children
- **WHEN** it is laid out
- **THEN** it has four lines of at most two children, is 184 px tall, and every child lies inside 300 px

### Spacer

- `UI.Spacer {}` MUST take the free space in a stack (it is flexible by default).
- `UI.Spacer { size = n }` MUST be a fixed gap of `n` along the stack's main axis only.

### Text measuring

- A text element's natural width MUST be its unbounded single-line width; a wrapping text element offered less than that MUST wrap within the offered width and report the height its lines need.
- A wrapping text element offered zero or near-zero width MUST still report a finite height.

#### Scenario: Squeezed wrapping text

- **GIVEN** a wrapping text with a long sentence
- **WHEN** it is measured at width 0
- **THEN** the reported height is finite

### Scroll areas

A scroll area is a clipping box whose content scrolls when it is larger than the box. `UI.ScrollView` is one; a Window's body is another ([components](../components/)).

- `UI.ScrollView` MUST accept `direction` (`vertical`, the default; `horizontal`, which lays children out in a row; or `both`), `gap`, `padding`, `align` (default `stretch` for vertical, `start` otherwise) and surface props.
- When the content fits, a scroll area MUST lay its children out like a stack of its size (flexible children fill) and show no scrollbar.
- When the content is larger along a scrolling axis, a scroll area MUST lay its children out at their natural size along that axis (a flexible child does not shrink below what its content needs), set the scroll range to content size minus view size, and show a scrollbar on that axis.
- A scrollbar MUST take its gutter from the other axis; when that makes the content overflow the other axis too, that axis MUST scroll as well (for `both`).
- The mouse wheel MUST scroll vertically, or horizontally when Shift is held or when there is nothing to scroll vertically, by 48 px per notch, clamped to the range; scrolling MUST move the content without laying it out again.
- A scrollbar's thumb MUST be proportional to the visible fraction (at least 24 px), follow the offset, and scroll the content when dragged.
- A re-layout MUST keep the current offset, clamped to the new range; a released scroll area MUST start at offset 0 when reused.
- The gutter and thumb thickness come from the theme's `Scroll` metrics (default 10 and 6; [theming](../theming/)).

#### Scenario: Vertical scroll

- **GIVEN** a 200 × 100 ScrollView with six 30 px rows
- **WHEN** it is laid out
- **THEN** its vertical range is 80, it has no horizontal range, and only the vertical scrollbar shows

#### Scenario: Horizontal by plain wheel

- **GIVEN** a horizontal ScrollView 200 px wide with eight 50 px chips and `gap = 10`
- **WHEN** the wheel turns one notch down
- **THEN** the content moves 48 px left

#### Scenario: Both axes

- **GIVEN** a 200 × 100 ScrollView with `direction = "both"` and a 360 × 180 grid
- **WHEN** it is laid out
- **THEN** the horizontal range is 170 and the vertical range is 90, each leaving room for the other axis's scrollbar; the wheel scrolls vertically and Shift+wheel horizontally

## Design

### Passes

`measure(node, maxW, maxH)` returns a natural size: fixed `width`/`height` win, a component measures its child, a host uses its own `measure`; the result is clamped by `minWidth`, `minHeight`, `maxWidth`. `place(node, x, y, w, h)` anchors a host's region at `x, -y` from the top-left of its parent frame, sizes it, and calls the host's `layout` to place its children. Floating hosts skip placement and lay themselves out.

### Scroll areas

A scroll area keeps a scroller record (`offsetX/Y`, `maxX/Y`, `viewW/H`, `contentW/H`) on its clip frame; children attach to the scroller's content frame, which is anchored at the negative offset. Developer snapshots report the record as `scroll` ([dev tools](../dev-tools/)).

## Constraints

- Sizes are in UI units of the frame's own scale; FxUI scale is applied to top-level frames only ([architecture](../architecture/)).

## Open Questions

None.

## References

- [Rendering](../rendering/), [Components](../components/), [Theming](../theming/)

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-26 | Initial spec created from the implementation | [0001-fxui-core](../../changes/0001-fxui-core.md) |
