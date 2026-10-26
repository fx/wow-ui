# Rendering

## Overview

FxUI renders declaratively: a consumer describes UI as a tree of elements (plain tables), and a reconciler creates, updates and releases client regions to match it. This spec owns elements, components and their context, the reconciler, region pooling, render batching and mounted roots. Size and position are owned by [layout](../layout/); what each built-in element draws is owned by [components](../components/) and [data components](../data-components/).

## Background

- Frames cannot be destroyed in the client and creating them is costly, so every region FxUI creates for an element is pooled and reused.
- Delivered by [0001](../../changes/0001-fxui-core.md). Project-level rules: [architecture](../architecture/).

## Requirements

### Elements

- Calling an element constructor (`UI.HStack { ... }`, a component, ...) MUST return an element: a plain table describing the type, its props and its children, and MUST NOT create any client region.
- Named fields of the constructor's table MUST become props; its array part MUST become the children, in order, skipping `nil` and `false` and flattening nested plain arrays (so `UI.map(list, fn)` results and conditional `x and UI.Text {...} or nil` entries can be passed directly).
- Children MUST be taken from the table when the constructor runs; entries added to the table afterwards are not children.
- `UI.isElement(v)` MUST tell an element from any other value; `UI.map(list, fn)` MUST return `fn(item, i)` for each item in order.

#### Scenario: Conditional and mapped children

- **GIVEN** `UI.VStack { UI.Text { text = "a" }, false, UI.map({ 1, 2 }, function(n) return UI.Text { text = tostring(n) } end) }`
- **WHEN** it is mounted
- **THEN** the stack has three Text children: "a", "1", "2"

### Components

- `UI.component(name, render)` MUST define a component from a render function `render(props, ctx)` that returns one element (or nothing).
- `UI.component(name, { init, render, mounted, unmounted })` MUST additionally call `init(ctx, props)` once before the first render, `mounted(ctx)` after the first render, and `unmounted(ctx)` when the component is released.
- A component's context MUST offer:
  - `ctx.props` and `ctx.state` (a table owned by the instance, starting empty);
  - `ctx:setState(patch)` (a table merged into state, or a function `(state, props) -> patch`) and `ctx:forceUpdate()`, both scheduling a re-render;
  - `ctx:onUnmount(fn)` to run cleanup on release;
  - `ctx:after(seconds, fn)` that runs `fn` later only if the component is still mounted;
  - `ctx:isMounted()`;
  - `ctx.theme`, the resolved theme the instance renders with ([theming](../theming/)).
- Calling `setState` or `forceUpdate` on a released component MUST NOT schedule a render.

#### Scenario: Delayed callback after unmount

- **GIVEN** a component that calls `ctx:after(2, fn)`
- **WHEN** it is unmounted before two seconds pass
- **THEN** `fn` never runs

### Reconciliation

- Re-rendering MUST update existing nodes in place when the new element has the same type and key as the old one at that position, and MUST create a new node otherwise, releasing the old one.
- A child's key is its `key` prop when given, otherwise its index; children with a `key` keep their node when they move.
- Re-rendering MUST NOT create regions for nodes it updates in place.
- An element's `ref` prop, a function, MUST be called with the element's client region when the node is created.

#### Scenario: Re-render keeps frames

- **GIVEN** a mounted list of 20 keyed rows
- **WHEN** one row's text changes and the order does not
- **THEN** no new regions are created and only that row's text changes

### Pooling

- Every host element type that owns a client region MUST take it from a per-type pool when one is free and create a new one only when the pool is empty.
- A released region MUST be hidden, detached from its anchors and parent, and returned to its type's pool.
- `UI.stats()` MUST report, per host type and in total, how many regions were created, are active (mounted) and are pooled (free).

#### Scenario: Remount reuses regions

- **GIVEN** a tree of a Button, a Badge and a Text was mounted and unmounted
- **WHEN** the same tree is mounted again
- **THEN** no new regions are created

### Batched re-renders

- State changes MUST NOT re-render synchronously; every component invalidated within one client frame MUST re-render once, on the next frame update, parents before children.
- After those renders, every affected root MUST be laid out once.
- `UI.flush()` MUST run pending renders immediately.

#### Scenario: Batched state

- **GIVEN** a mounted component
- **WHEN** its state is set three times in the same frame
- **THEN** it renders once on the next frame and shows the last value

### Roots

- `UI.mount(frame, element, opts)` MUST render the element into `frame` and return a root; the element fills the frame, except a floating element (a Window), which positions itself.
- `opts.theme` (a registered theme name or a theme table) MUST apply to the whole tree ([theming](../theming/)).
- A root MUST re-lay itself out when its frame changes size.
- `root:update(element)` MUST reconcile the tree against a new element (or re-render the current one when given none); `root:unmount()` MUST release every node and return its regions to the pools; `root:layout()` MUST lay the tree out again.
- Changing the global theme or the FxUI scale MUST re-render every mounted root.

#### Scenario: Unmount releases everything

- **GIVEN** a mounted tree
- **WHEN** `root:unmount()` runs
- **THEN** `UI.stats()` reports none of its regions active and all of them pooled

## Design

### Nodes

The reconciler keeps a node per mounted element: `el`, `key`, `parent`, `root`, `depth`, `alive`, `theme`, and either `def` + `ctx` + `child` (component) or `host` + `region` + `children` (host). Hosts are defined internally with `I.defineHost(name, def)`, which also publishes the constructor as `UI[name]`. A host definition may provide `create(holder)`, `init(node)`, `update(node, props, oldProps)`, `measure(node, maxW, maxH)`, `layout(node, w, h)`, `release(node)`, `content(node)` (the frame children attach to), `container` (reconciles children), `floating` (positions itself), `defaultFlex` and `alignSelf`. A Window reconciles two extra child lists, `headerChildren` and `footerChildren`, next to `children`.

Pooled regions wait parented to a hidden holder frame. Region event scripts find their node through `region.fxNode`, which is cleared on release, so a pooled region ignores input.

### Rendering a component

A component's render runs with its theme active, wrapped so a raised error is reported and the component renders nothing. The child keeps its node when its type and key are unchanged.

## Constraints

- Everything runs on the client's single Lua thread; batching relies on the next `OnUpdate` of an internal driver frame.

## Open Questions

None.

## References

- [Layout](../layout/), [Components](../components/), [Data components](../data-components/), [Theming](../theming/)

## Changelog

| Date | Change | Document |
|------|--------|----------|
| 2026-10-26 | Initial spec created from the implementation (previously part of the architecture spec) | [0001-fxui-core](../../changes/0001-fxui-core.md) |
