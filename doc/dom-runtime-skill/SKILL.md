---
name: metaeditor-dom-runtime
description: Guide for working on MetaEditor's DOM runtime, bridge, host UI, and DOM-related tests. Use when editing `src/dom.mbt`, `src/bridge.js`, host UI code, `h_map` / `Dyn` behavior, `ui-id` / `ui-name` / `ui-list` query semantics, or browser bridge command tests.
---

# MetaEditor DOM Runtime

Use this skill when the task touches:

- `src/dom.mbt`
- `src/bridge.js`
- host UI code that depends on stable runtime node identity
- `h_map` / `h_map_dyn`
- `Dyn`
- `ui-id` / `ui-name` / `ui-list`
- DOM white-box tests
- browser bridge command tests

## Workflow

1. Read `references/runtime-semantics.md` first.
2. If the task changes runtime behavior, inspect current tests in `src/dom.test.mbt`.
3. If the task changes bridge command behavior or command protocol, inspect `scripts/browser-tests/bridge.test.js`.
4. Keep one main path. Do not add parallel runtime concepts unless the task explicitly requires it.

## Hard Rules

- Treat `VNode` as a real runtime DOM node with a stable unique `id`.
- Prefer stable root nodes plus `D(...)` for style/attr/text changes.
- Do not use outer `Dyn(fn() { h(...) })` for cases that only change style, text, or attrs.
- `h_map` is the stable list path. Prefer it when list item identity matters.
- `ui-id` is the stable naming source. Do not encode list position into `ui-id`.
- If you change `DomCmd` protocol or bridge command handling, update browser bridge tests in the same change.

## Current Behavior Boundaries

- Plain `Dyn` still rebuilds fresh children when it returns fresh child structures.
- `h_map/h_map_dyn` already preserve stable list item identity.
- `h_map` item roots that return `Dyn(...)` are also treated as stable runtime fragments.
- Bridge command protocol currently includes `InsertAfter` and browser tests should cover it.

## Read Next When Needed

- Runtime and usage constraints: `references/runtime-semantics.md`

