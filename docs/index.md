# Documentation

## Specs

| Spec | Description | Status |
|------|-------------|--------|
| [Architecture](specs/architecture/) | Repository layout, distribution and versioning, library services (errors, combat, /fx command, scale), media, testing and CI | active |
| [Components](specs/components/) | Text primitives, buttons and protected clicks, badges, toggles, tabs, windows and toasts | active |
| [Data Components](specs/data-components/) | Money, item cells, meters, virtualized lists, sortable tables, charts, sparklines and legends | active |
| [Dev Tools](specs/dev-tools/) | FxUI Dev addon (dev window, demo, snapshots, picker, settings), the snapshot reader and the agent skill | active |
| [Layout](specs/layout/) | Layout props, stacks, flex, wrapping, spacers, text measuring and scroll areas | active |
| [Rendering](specs/rendering/) | Elements, components, the reconciler, region pooling, batched re-renders and mounted roots | active |
| [Theme Addons](specs/theme-addons/) | The Classic and Teal theme addons | active |
| [Theme Tokens](specs/theme-tokens/) | Token contract, default theme values, text contrast and money formatting | active |
| [Theming](specs/theming/) | Theme definitions, inheritance, registration, per-tree and per-element themes, skins, surfaces and the theme setting | active |

## Changes

| # | Change | Spec | Status | Depends On |
|---|--------|------|--------|------------|
| 0001 | [FxUI Core Library](changes/0001-fxui-core.md) | [Architecture](specs/architecture/) | complete | — |
| 0002 | [Theme Addons](changes/0002-theme-addons.md) | [Theme Addons](specs/theme-addons/) | complete | 0001 |
| 0003 | [Dev Tools](changes/0003-dev-tools.md) | [Dev Tools](specs/dev-tools/) | complete | 0001, 0002 |
| 0004 | [Slider](changes/0004-slider.md) | [Components](specs/components/) | complete | 0001 |
| 0005 | [Tooltip and help](changes/0005-tooltip-help.md) | [Components](specs/components/) | complete | 0001 |
| 0006 | [Pressable](changes/0006-pressable.md) | [Components](specs/components/) | in-progress | 0005 |
