# FxUI Theme: Classic

Notes for working on this theme. General FxUI development (tests, coverage, linking the addons) is in `README.md` and `AGENTS.md` at the repository root.

## Where the art and layouts come from

- Only client art that still ships in retail. Before using a texture, check that a current retail addon references it (grep the installed addons) and keep the `has(path)` fallback to flat drawing; missing files are reported once.
  - Probe every file on its own, secondary art included: a checkbox whose box ships but whose check does not draws a flat check inside the box art; highlights go through `highlight()`, which probes the file and hides the highlight when it is missing.
  - Backdrops go through `backdrop()`, which probes both of their files and removes any earlier backdrop when it falls back; the card, toast and inset surfaces are registered only when the tooltip art ships.
  - A decoration drawn only under a condition (title banner, sortable-header highlight, inactive-tab highlight) is hidden whenever the condition is false: the core keeps skin textures on the skinned path, so a pooled or updated region still carries them.
- Original layouts: Blizzard's FrameXML, mirrored at github.com/Gethe/wow-ui-source (`classic_era` branch). `Interface/ui-code-list.txt` lists the files. Key files:
  - `Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml` / `.lua`: `TabButtonTemplate` (classic top tabs), `PanelTemplates_SelectTab` / `DeselectTab` / `TabResize`.
  - `Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.xml`: a classic frame with top tabs over an inset panel.
- AceGUI (shipped inside many addons) uses the same art in retail and is a second reference: `AceGUIContainer-TabGroup.lua` (Options-window tabs, pane border), `AceGUIContainer-Frame.lua` (dialog title banner, status bar). Read for numbers; don't copy code.

## Component notes

- Windows: dialog backdrop; gold title banner (`UI-DialogBox-Header`: centre `0.31–0.67`, caps `0.21–0.31` / `0.67–0.77`, 40 tall, 12 above the frame). With only the banner in the header, the header collapses to a thin strip (`compactHeader`). Status and actions go in a tooltip-framed footer.
- Buttons: `UI-Panel-Button-*` three-slice (art in the left 80x22 of 128x32: caps `0–0.09375`, `0.53125–0.625`, v `0–0.6875`), gold text, white on hover.
- Tabs (the hard one):
  - Classic's own top tabs (`TabButtonTemplate`) use `Interface\HelpFrame\HelpFrameTab-Active` / `-Inactive`: 32 tall, 16 px caps (`0–0.25`, `0.25–0.75`, `0.75–1`), bottom-anchored, active 3 px lower, text centred +2 (inactive) / −3 (selected), width = text + 32, adjacent tabs at x 0. Not yet confirmed to ship in retail; the theme currently uses the Options-window art instead.
  - Current implementation: `UI-OptionsFrame-ActiveTab` for every tab (inactive darkened), drawn 30 tall (the art is designed at 24; `TAB_H` / `TAB_SCALE` scale every vertical measure) so the text has room above it. All tabs hang 5 art units below the row so their flared feet land on the rail; text 2 art units above the art's centre in every tab. The art has transparent space at its bottom, which is why the inactive art floated above the rail and why a lowered active tab looked off.
  - The rail draws above the tab row (`railAbove`): inactive tabs tuck behind the panel border, the selected tab opens through its gap.
  - The rail under the tabs is the top edge of a tooltip border, clipped (`paintRail`). It opens under the selected tab from the art's on-screen rect (`railGap`): the feet are 10.4 units inside the art's edges (measured at FxUI scale 100%: feet at x 30/153 px, rail stopping at 24/159 with the old 7-unit inset), so the gap starts 9.5 in.
- Badges: thin tooltip frame in the tone colour; solid badges use a darkened tone with white text (black on dark tones was unreadable).
- Meters: 16 px status bar in a thin tooltip frame, value centred in the bar.
- Rows: quest-log highlight on hover, gold when selected. Table headers: `WhoFrame-ColumnTabs` (caps 5 and 4 px, v `0–0.59375`, 19 tall).
- Scrollbars: 18 px gutter, the fixed 16x24 knob (`UI-ScrollBar-Knob`, `0.2–0.8`, `0.125–0.875`), never stretched.
- Secondary text is gold, values white; Friz Quadrata with shadows, Morpheus for display, Arial Narrow for numbers; coin icons for money.

## Verifying

The headless tests (`tests/run.lua`, the `classic:` tests) draw every skinned component in Classic in each state, check that pooled regions are clean under the default theme afterwards, run the layout invariants under Classic, and draw everything with every client file missing. They cannot show pixels: for art alignment, measure a screenshot crop in pixels and record the numbers here.
