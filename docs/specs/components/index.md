# Components

## Overview

This spec owns the behaviour of FxUI's general-purpose components: text primitives, buttons (including protected clicks), badges, toggles, tabs, windows and toasts. Data-oriented components (money, item cells, meters, lists, tables, charts, legends) are owned by [data components](../data-components/). How they are laid out is owned by [layout](../layout/); every color, font, metric and skin they draw with comes from the active theme ([theming](../theming/), [theme tokens](../theme-tokens/)).

## Background

- Components are host elements (`UI.Button`, ...) or components built from them (`UI.TabBar`), created through the [rendering](../rendering/) model and pooled.
- Visual defaults below describe the built-in default theme; a theme MAY replace a component's drawing through a skin ([theming](../theming/)) without changing the behaviour specified here.
- Delivered by [0001](../../changes/0001-fxui-core.md).

## Requirements

### Text primitives

- `UI.Text` MUST draw `text` with a font token `style` (default `body`), a `color` (token or `#RRGGBB[AA]`, default `text`), `justify` (`LEFT` · `CENTER` · `RIGHT`), optional `wrap` and `maxLines`, and `alpha`. A font token marked caps MUST draw its text upper-case.
- `UI.Divider` MUST draw a 1 px line in `color` (default `line`) that stretches across its stack; `vertical = true` makes it a column rule.
- `UI.Dot` MUST draw a filled circle of `size` (default 8) in `color` (default `muted`).

### Button

- `UI.Button` MUST accept `text`, `variant` (`primary` · `secondary` · `danger` · `ghost`; default `secondary`), `size` (`sm` · `md` · `lg`; default `md`), `onClick(frame, mouseButton)`, `disabled`, `busy` and `tooltip`, and react to left and right clicks.
- `busy = true` MUST disable the button; `busy = "<text>"` MUST also replace its label with that text.
- A disabled button MUST look disabled and MUST NOT call `onClick`.
- Hovering MUST show `tooltip` (when given) and a hover state; pressing MUST show a pressed state.
- A button's width MUST be its label's width plus the size's padding on both sides; its height is the size's height (default theme: `sm` 24, `md` 30, `lg` 40 px).

#### Scenario: Busy button

- **GIVEN** a button with `busy = "Loading…"`
- **WHEN** it is rendered and clicked
- **THEN** it reads "Loading…", looks disabled and `onClick` does not run

### Protected clicks

- A button marked `secure = true` MUST invoke `onClick` synchronously inside the player's real click, so the handler may make a protected API call; the call MUST NOT be deferred to a later frame, timer or callback.
- A secure button MUST be disabled while the player is in combat, and MUST re-enable when combat ends, without the consumer re-rendering.

#### Scenario: Secure button and combat

- **GIVEN** a mounted secure button
- **WHEN** the player clicks it out of combat, then enters combat and clicks again, then leaves combat
- **THEN** the handler ran once, the button showed disabled during combat, and it is enabled again afterwards

### Badge

- `UI.Badge` MUST draw short `text` in the caps `label` font with a `tone` (`neutral` · `gold` · `info` · `up` · `down` · `warn`, or any color token; default `neutral`): a tinted pill with tone-colored text, or with `solid = true` a pill filled with the tone.

### Toggle

- `UI.Toggle` MUST draw a labelled on/off control from `checked` and `label`, call `onChange(not checked)` when clicked, and do nothing when `disabled` (drawn faded).
- A Toggle MUST NOT change its own state; the consumer passes the new `checked`.

### Tabs

- `UI.TabBar` MUST draw a row of tabs from `tabs = { { id, text, count } }` with `selected` (an id) and call `onSelect(id)` when a tab is clicked; `padding` sets the row's padding.
- A tab's `count`, when given, MUST show after its text (default theme: mono, gold).
- A tab MUST keep the same width whether it is selected, hovered or neither.
- Under the tab row a rail (line) MUST run the full width. In the default theme the selected tab is marked on that rail, as wide as the tab, and the rail is continuous; a theme MAY instead open a gap in the rail under the selected tab so the tab opens into the panel below ([theming](../theming/)).
- `UI.Tab` MAY be used directly with `text`, `count`, `selected`, `id` and `onSelect(id)`.

#### Scenario: Tabs keep their width

- **GIVEN** a TabBar with tabs "Alpha" and "Beta" and "Alpha" selected
- **WHEN** the selection moves to "Beta"
- **THEN** "Alpha" keeps its width

### Window

`UI.Window` is a floating window parented to the screen; it positions itself rather than filling the frame it is mounted in.

- A Window MUST accept `title`, `width` and `height` (default 640 × 480), `minWidth` and `minHeight` (resize limits, default 320 × 200), `strata` (default `HIGH`), `shown` (default true), `closable` (default true), `onClose`, `size` (`md` · `sm`: header height and title font), `padding` and `gap` (for its body), `point`/`x`/`y` (initial position, default centred), and children for its body.
- A free window MUST be movable by dragging its header, resizable from a grip in its bottom-right corner, kept on screen, and raised when clicked.
- The close button MUST call `onClose` when given, and otherwise hide the window.
- `saved` (a table the consumer persists, e.g. in its SavedVariables) MUST receive the window's position, size and scale whenever the player moves or resizes it and whenever the FxUI scale changes, and MUST be used to restore position and size the next time the window is created; a position saved at another scale MUST restore to the same spot on screen.
- `dock` (a frame) MUST attach the window to that frame's right edge, or its left with `dockSide = "left"`, `dockGap` apart (default 8); a docked window MUST NOT be movable or resizable, MUST move with its dock and MUST NOT write `saved`.
- The body MUST be a vertical scroll area ([layout](../layout/)) unless `scroll = false`, so content taller than the window scrolls while flexible children still fill when it fits. With `scroll = false` the body MUST lay its children out as a plain stack with no scroll range and no scrollbar, also when an update turns scrolling off.
- `header` (elements) MUST be placed in the header after the title; `footer` (elements) MUST be placed in a bar along the bottom, spanning the window's full inner width.
- `status` (text, an element, or a list of them; text is drawn small and muted) and `actions` (`{ { text, onClick, tooltip, variant, disabled } }`, drawn as small buttons after a spacer) MUST be placed where the active theme puts them: in the header (the default theme) or in the footer ([theming](../theming/)).
- The footer bar MUST exist only when something is placed in it; a theme that places status and actions in the header MUST NOT get a footer unless the window has `footer` content.
- The resize grip MUST sit above the footer; the footer's content keeps clear of it.

#### Scenario: Status and actions in the default theme

- **GIVEN** a window with `status = "status"` and one action "Do"
- **WHEN** it renders in the default theme
- **THEN** the header holds "status" and a "Do" button, the footer is hidden, and clicking "Do" runs its handler

#### Scenario: Explicit footer

- **GIVEN** a window with `footer = { UI.Text { text = "own footer" } }`
- **WHEN** it renders in any theme
- **THEN** the footer bar shows

#### Scenario: Body scrolls

- **GIVEN** a 300 × 248 window (body 200 px tall) holding ten 40 px rows
- **WHEN** it renders
- **THEN** the body scrolls vertically with a range of 200 and no horizontal range

#### Scenario: Flexible page that overflows

- **GIVEN** a window whose body holds a 40 px row and a page with `flex = 1` whose content is 480 px tall, in a 300 px body
- **WHEN** it renders
- **THEN** the body scrolls with a range of 220; in a body taller than the content, the page fills the remaining height instead

#### Scenario: Docked window

- **GIVEN** a window with `dock = mainFrame`
- **WHEN** it renders
- **THEN** it sits 8 px to the right of `mainFrame`, has no resize grip, and its header does not drag

### Toast

- `UI.toast(text, opts)` MUST show a transient one-line notice near the top of the screen with a tone dot (`opts.tone`, as for Badge; default gold), removed after `opts.duration` seconds (default 4).
- At most five toasts MUST show at once; a new toast beyond that drops the oldest.
- Toasts MUST follow the FxUI scale ([architecture](../architecture/)) and draw on the theme's `toast` surface.

#### Scenario: Toast expires

- **GIVEN** `UI.toast("Saved", { tone = "up" })`
- **WHEN** four seconds pass
- **THEN** the notice is gone

## Design

### Component contracts with skins

Each component publishes what a skin receives ([theming](../theming/) owns the skin mechanism):

| Component | Skin entry | Receives |
|-----------|------------|----------|
| Button | `paint(button, props, state)` | `state = { hover, pressed, enabled, size }`; `button.label` |
| Badge | `paint(frame, props, toneToken)` | `frame.label` with text set |
| Toggle | `paint(button, props, state)` | `state = { hover, checked, enabled }`; `button.track`, `.knob`, `.label` |
| Tab | `paint(button, props, state)`, `paintRail(segment)`, `railGap(tabButton)` | `state = { hover, selected }`; `button.label`, `.count`, `.underline` |
| Window | `paint(frame, props, size)`, `paintClose(button, hover)`, `paintFooter(footer)` | `frame.header`, `.title`, `.headerFoot`, `.headerLine`, `.grip` |
| Scroll | `paintThumb(thumb, hot)` | `thumb.tex`, `.track`, `.axis` |

Metrics the components read (all optional, with the defaults in parentheses): `Button.sizes` (`sm` 24/10, `md` 30/14, `lg` 40/20 height/padding) and `Button.font` (`strong`); `Badge.height` (18), `.pad` (7); `Toggle.width` (30), `.height` (20), `.gap` (10); `Tab.height` (34), `.pad` (14), `.gap` (4), `.rail` (1), `.lineWidth` (1), `.railColor` (`line`), `.markColor` (`gold`), `.railHighlight`, `.openSelected`, `.railAbove`, `.railOffset`; `Window.md`/`.sm` (`header`, `title`, `pad`, `close`, `closeInset`, `inset`, `titleColor`, `gripColor`, `banner`, `compactHeader`, `footer`, `footerPad`), `Window.status` and `Window.actions` (`"header"` or `"footer"`). A Window size with `banner` draws its title above the frame; with nothing else in the header, the header collapses to `compactHeader` (default 14) and the close button moves to the top-right corner.

### Toast host

The toast stack is an FxUI tree mounted once, on first use, in a `DIALOG`-strata frame 140 px below the top of the screen.

## Constraints

- Protected calls work only inside a hardware event; that is why secure handlers are never deferred and why secure buttons are disabled in combat.

## Open Questions

- **Compact variants.** Developer panels use the small sizes (`size = "sm"`) for now; dedicated compact component variants are not built.

## References

- [Layout](../layout/), [Theming](../theming/), [Theme tokens](../theme-tokens/), [Data components](../data-components/)

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-26 | Initial spec created from the implementation (the planned component table previously in the architecture spec) | [0001-fxui-core](../../changes/0001-fxui-core.md) |
