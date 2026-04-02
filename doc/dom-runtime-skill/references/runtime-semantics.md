# MetaEditor DOM Runtime Semantics

This reference explains the current runtime model and the coding constraints that follow from it.

## 1. Core Mental Model

`VNode` should be treated as a real DOM node in the runtime.

- `VNode.id` is the unique runtime identity
- nodes may move and continue receiving updates
- a node should only be removed when it truly disappears
- removal means both `Remove(id)` and cleanup of callbacks, effects, and naming data

When deciding whether a write is correct, reduce it to one question:

- is this updating an existing node
- or replacing it with a fresh node

## 2. When Node Identity Should Be Preserved

Preserve node identity when only style, attrs, text, or listeners change.

Common cases:

- selected state changes
- focus state changes
- collapsed/expanded class changes
- button label changes
- input value changes

Prefer stable root nodes plus `D(...)` or local inner dynamic updates.

Avoid:

```moonbit
Dyn(fn() {
  h("button", [("ui-id", S("entry:x"))], ...)
})
```

if the logic only changes style, text, or attrs.

This matters most for continuous interactions:

- `click`
- `dblclick`
- `focus`
- keyboard events

If the root node changes identity after the first interaction, later events can hit stale ids.

## 3. Plain Dyn Boundary

Plain `Dyn` still has no general structural reuse logic.

That means:

- `Dyn(fn() { h(...) })`
- `Dyn(fn() { Str(...) })`

will produce fresh `VNode`s when they return fresh child structures.
The old ids disappear.
The old nodes are removed.

Current good uses of plain `Dyn`:

- clear structural switching
- conditional branches
- small subtrees where full replacement is acceptable

Current bad use:

- wrapping a whole root node when only style/text/attrs should change

## 4. h_map / h_map_dyn Boundary

`h_map` and `h_map_dyn` are the stable list path.

The key point is not "guess reuse after rerender".
The key point is that the list layer caches already-mounted runtime fragments.

### What currently holds

- kept items can reorder
- kept items do not remove and recreate
- kept item listeners stay attached to the same runtime roots
- removed items stop their inner dynamic updates
- item roots that return `Dyn(...)` still preserve stable runtime fragment identity

### What still does not hold

- general structural reuse for plain `Dyn`
- automatic reuse for arbitrary fresh children
- non-`h_map` dynamic lists automatically preserving prefix identities

Practical guidance:

- if list identity matters, use `h_map` / `h_map_dyn`
- if a list item root is itself dynamic, prefer that dynamic root to live under `h_map`
- do not expect plain `Dyn` to give full list reuse semantics

## 5. Query Model

`ui-id` is the stable naming source.

- `ui-id` names a stable node or host boundary
- `ui-name` exposes a local naming scope
- `ui-list` exposes a list scope

List item queries are aligned with the current `h_map` fragment model.
If an item root is dynamic, queries should follow that item's current visible nodes, not stale historical nodes.

Two practical rules:

- if a node needs stable direct targeting, give it its own `ui-id`
- do not push list position back into `ui-id`

Style and structural position should mostly stay in DOM structure and CSS selectors.

## 6. Host / App Coding Guidance

Host shells, windows, list items, and toolbar buttons are identity-sensitive.

Prefer:

- stable root + `D(...)` for style changes
- stable root + local text update for label changes
- `h_map` for stable list items
- `h_map` item roots that return `Dyn(...)` when the item itself needs dynamic inner switching

Do not model simple host style changes as whole-node replacement.

## 7. Bridge and Protocol

Bridge and runtime need to be kept in sync.

Current rules:

- `DomCmd` numbering should be centralized
- bridge message types should be centralized
- browser bridge tests should use the runtime-exposed command mapping

The current fragment model depends on `InsertAfter`.
If fragment order or block movement changes, inspect together:

- `src/dom.mbt`
- `src/bridge.js`
- `scripts/browser-tests/bridge.test.js`

## 8. Testing Guidance

### DOM white-box tests

When changing `src/dom.mbt`, prefer adding or updating `src/dom.test.mbt`.

Key regressions to lock:

- kept items are not recreated
- removal only affects missing items
- listener identity stays stable
- list queries follow the current visible item nodes
- removed items stop inner dynamic updates

### Bridge browser tests

When changing `src/bridge.js` or `DomCmd` protocol, update `scripts/browser-tests/bridge.test.js`.

That suite should directly validate real browser DOM effects:

- `Create`
- `Append`
- `InsertBefore`
- `InsertAfter`
- `UpdateText`
- `Attr / UpdateAttr / RemoveAttr`
- `SetStyle / RemoveStyle`
- `SetCss / RemoveCss`
- `HostCmd`
- event dispatch and `data-mbt-id` stability after node moves

White-box command tests only prove the command stream.
Browser bridge tests prove the bridge interprets commands correctly.
