# Data Components

## Overview

This spec owns the behaviour of FxUI's data-oriented components: money, item cells, meters, virtualized lists, sortable tables, charts, sparklines and legends. General-purpose components are owned by [components](../components/); money formatting rules are owned by [theme tokens](../theme-tokens/); layout by [layout](../layout/).

## Background

- FxUI holds no game data of its own. Item names, icons and qualities come from the client; any extra lines in an item tooltip come from the consumer.
- Prices are integer copper throughout.
- Delivered by [0001](../../changes/0001-fxui-core.md).

## Requirements

### Money

- `UI.Money` MUST draw `value` (copper) formatted per [money formatting](../theme-tokens/#money-formatting), with `compact`, `short` and `signed` passed through and denominations marked in the theme's money style.
- It MUST draw in the `mono` font by default (`style` overrides), in `tone` (`up`, `down` or any color token; `color` is an alias; default `text`), justified by `justify`.

### Item cell

- `UI.ItemCell` MUST take `item` as an item ID or an item link and draw the item's icon and name, the name in its quality color ([theme tokens](../theme-tokens/)).
- While the client has not loaded the item, the cell MUST show a placeholder (`placeholder`, or `item:<id>` in the muted color), request the item, and update and re-lay out once it loads.
- After the name it MUST show `×<qty>` when `qty` is given, else `ilvl <n>` when `showLevel` is set, else `note`.
- Hovering MUST show the client's item tooltip, followed by lines the consumer adds through `tooltip(GameTooltip, itemID)`.
- A click with the chat-link modifier (Shift by default) MUST insert the item link into chat; any other click MUST call `onClick(frame, itemID, link, mouseButton)`.
- `iconSize` (default 24) sets the icon size; `style` the name's font token. When the cell is narrower than its content, the name MUST be truncated, not the icon or the extra text.

#### Scenario: Item loads later

- **GIVEN** an item cell for an item the client has not loaded
- **WHEN** the item data arrives
- **THEN** the cell shows the item's name in its quality color and its layout updates

### Meter

- `UI.Meter` MUST draw progress of `value` against `max` (clamped to 0–100 %) as a filled bar in `tone` (default `gold`), with an optional `label` and `valueText`.
- In the default drawing a non-zero value MUST show at least a bar-height-wide fill, so a small amount stays visible.
- A theme MAY draw `valueText` inside the bar instead of beside the label (`metrics.Meter.inlineValue`); the bar height comes from `metrics.Meter.barHeight` (default 8).

### List

`UI.List` is a virtualized, keyed list.

- A list MUST take `items`, `key` (a field name or `function(item, i)`; default the index), `rowHeight` (default 32) and `render(item, i)`, and MUST create rows only for the visible items plus `overscan` (default 2) on each side, so the number of row regions does not grow with the number of items.
- The wheel MUST scroll three rows per notch; a scrollbar MUST show only when the rows are taller than the list, and `scrollbar = "always"` reserves its width even when not needed. The thumb is draggable.
- Rows MUST be highlighted under the cursor unless `highlight = false`; `striped` shades every second row.
- With `onSelect`, a left press MUST show a pressed state and releasing on the same row MUST call `onSelect(item, i, key)`; controls inside a row keep their own clicks.
- The row whose key equals `selected` MUST stay highlighted as selected. Row state precedence: pressed, then selected, then hover, then stripe.
- `empty` (text) MUST show centred when there are no items.
- `rowPadding` sets each row's padding (default `{ 0, 12 }`); `visibleRows` (default 8) sets the natural height.
- `UI.scrollListTo(frame, i)` MUST scroll a mounted list (by its region) so row `i` is at the top, clamped.

#### Scenario: Large list

- **GIVEN** a list of 5,000 items with 36 px rows in a 540 px tall box
- **WHEN** it is scrolled from end to end with the wheel
- **THEN** it never holds more than 21 rows, and at the end the last row's key is the last item's

#### Scenario: Hover and select

- **GIVEN** a list with `onSelect` and the cursor over its third row
- **WHEN** the player presses and releases the left button there
- **THEN** the third row shows hover, then pressed, and `onSelect` receives its key; after the consumer passes that key as `selected`, the row stays highlighted when the cursor leaves

### Table

`UI.Table` is a header row over a virtualized list of rows, sortable by column.

- A table MUST take `columns = { { key, title, width | flex, minWidth, align (LEFT | RIGHT), sortable (default true), sortValue(item), render(item, i) } }` and `items`, and pass `key`, `rowHeight`, `striped`, `selected`, `onSelect`, `highlight` and `empty` to its list.
- A column without `render` MUST show its value (`sortValue(item)`, else `item[key]`) as text.
- The header MUST line up with the rows' columns.
- Clicking a sortable header MUST sort by that column ascending; clicking it again MUST reverse the direction; clicking another column MUST sort by it ascending. The sorted column's header MUST show a chevron for its direction.
- Sorting MUST be stable, place items with no value last in either direction, compare strings case-insensitively, and compare values of mixed types as strings.
- `defaultSort = { key, desc }` sets the initial sort. With `sort = { key, desc }` the sort is controlled: the table shows that order and header clicks call `onSort(key, desc)` with the requested sort instead of sorting.
- Sorting MUST NOT run again unless the items, the sort column or the direction change. `UI.sortItems(items, column, desc)` exposes the same sort.

#### Scenario: Header clicks

- **GIVEN** items with prices 30, 10, none, 10 (keys 1–4)
- **WHEN** the Price header is clicked once, then again
- **THEN** the rows read 2, 4, 1, 3, then 1, 2, 4, 3

#### Scenario: Controlled sort

- **GIVEN** a table with `sort = { key = "v", desc = true }` and `onSort`
- **WHEN** the V header is clicked
- **THEN** `onSort("v", false)` is called and the rows stay in the controlled order

### Chart

`UI.Chart` draws a price series with a price column and a crosshair.

- `mode` MUST be `line` (default, from `values`), `bars` (from `values`, standing on `baseline`, default 0) or `candles` (from `candles = { { o, h, l, c } }`; without candles it falls back to `line`).
- The vertical range MUST cover the data, the `reference` level and the bars' baseline, with a little headroom; bars stand on their baseline with no room below it.
- Candles MUST draw in the `up` color when they close at or above their open and in `down` otherwise; bars below the baseline MUST draw in `down`, others in `color` (default `gold`).
- `reference` MUST draw as a dashed horizontal level; `grid` (default on) draws three horizontal gridlines.
- Unless `axis = false`, a price column on the right MUST show the high and low of the range and a tag at the last value in the series' tone, and MUST be as wide as its widest label (at least 28 px, at most a third of the chart).
- While the cursor is over the plot (inside its margins), a crosshair MUST snap to the nearest point (line) or the slot under the cursor (bars, candles), show a readout at the top (the point's `labels[i]` and its value formatted by `format(value)`, default short colored money; for candles open, high, low, close and change in percent), and a price tag at the cursor's height. When the readout is wider than the plot it MUST fall back to a shorter form: for candles the label with close and change only, then, for any mode, the value without the label.
- `onHover(i)` MUST be called with the hovered index each time the hovered point changes, and with `nil` whenever the hover ends: the cursor leaves the plot (into any of its four margins or off the chart), the chart is hidden or released, or its data no longer has a point there. A re-layout alone does not end the hover, and neither a re-layout nor the cursor moving within the same point calls `onHover` again, so an `onHover` that re-renders the chart does not call itself every frame.
- An empty series MUST draw nothing.

#### Scenario: Line hover

- **GIVEN** a line chart of 11 values with labels `t1`…`t11`
- **WHEN** the cursor is just right of the sixth point
- **THEN** the crosshair shows on point 6 and the readout contains "t6" and its value; when the cursor leaves, the crosshair hides

#### Scenario: Narrow candles

- **GIVEN** a candle chart 130 px wide with labels
- **WHEN** the cursor hovers a candle
- **THEN** the readout fits inside the plot and shows no OHLC

#### Scenario: Hover that re-renders the consumer

- **GIVEN** a component whose chart's `onHover` sets the component's state
- **WHEN** the cursor rests on one point for many frames
- **THEN** `onHover` is called once, the component re-renders a bounded number of times, and the crosshair stays drawn

### Sparkline

- `UI.Sparkline` MUST draw `values` as a thin line in `color` (default `gold`, `thickness` default 1.5) with a dot on the last value and an optional dashed `reference` level, for tiny inline trends (natural size 120 × 32).

### Legend

- `UI.Legend` MUST draw `items = { { label, value, color, shape } }` as compact chips (a dot, a line or a dash swatch; a label; a value given as text, a number or an element) that wrap onto new lines inside their width (`gap`, `rowGap`).

#### Scenario: Narrow legend

- **GIVEN** five legend items in a 140 px wide box
- **WHEN** it is laid out
- **THEN** the chips wrap onto several lines and each lies inside 140 px

## Design

### Skin contracts

| Component | Skin entry | Receives |
|-----------|------------|----------|
| ItemCell | `paintIcon(frame, color, size)` | `frame.icon`, `.iconBg`, `.mask` |
| Meter | `paint(frame, props)` | `frame.track`, `.fill`; a skin may set `track.fxFillInset` |
| List | `paintRow(rowFrame, state)` | `state` = `pressed` · `selected` · `hover` · `stripe` · nil |
| HeaderCell | `paint(button, props, state)` | `state = { hover, active }`; `button.label`, `.up`, `.down` |
| Chart | `tag(frame, kind, bgColor)` | `kind` = `readout` · `hover` · `last`; `frame.text` set |

Metrics: `Meter.barHeight`, `Meter.inlineValue`; `HeaderCell.height`, `HeaderCell.pad`; `Scroll.width`, `Scroll.thumb` for the list's scrollbar.

### Table composition

A Table renders a header `HStack` of `UI.HeaderCell`s (its right padding includes the scrollbar gutter), a `Divider`, and a `List` with `scrollbar = "always"`, so the header and rows line up whether or not the list scrolls. The sorted list is memoised on the component instance.

## Constraints

- Item data is asynchronous in the client; cells must tolerate missing data at any time.

## Open Questions

- **Money input.** A gold/silver/copper input producing copper was planned and is not built.

## References

- [Components](../components/), [Theme tokens](../theme-tokens/), [Layout](../layout/), [Theming](../theming/)

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-26 | Initial spec created from the implementation | [0001-fxui-core](../../changes/0001-fxui-core.md) |
