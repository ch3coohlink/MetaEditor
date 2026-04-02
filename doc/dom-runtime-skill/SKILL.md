---
name: metaeditor-dom-runtime
description: Guide for working on MetaEditor's DOM runtime, bridge, host UI, DOM-owned reactive scopes, and DOM-related tests. Use when editing `src/dom.mbt`, `src/bridge.js`, `src/reactive.mbt`, host UI code, `h_map` / `Dyn` behavior, `ui-id` / `ui-name` / `ui-list` / `ui-react` semantics, bridge query/exec targeting, or browser/native host flow tests.
---

# MetaEditor DOM Runtime

Use this skill when the task touches:

- `src/dom.mbt`
- `src/bridge.js`
- DOM-owned reactive scope behavior in `src/reactive.mbt`
- host UI code that depends on stable runtime node identity
- `h_map` / `h_map_dyn`
- `Dyn`
- `ui-id` / `ui-name` / `ui-list` / `ui-react`
- DOM white-box tests
- browser bridge command tests
- host browser/native flow tests

## Workflow

1. Read `references/runtime-semantics.md` first.
2. If the task changes runtime behavior, inspect current tests in `src/dom.test.mbt`.
3. If the task changes DOM-owned reactive scope behavior, inspect `src/reactive.test.mbt` and the `ui-react` cases in `src/dom.test.mbt`.
4. If the task changes bridge command behavior, event routing, or bridge query/exec target resolution, inspect `scripts/browser-tests/bridge.test.js`.
5. If the task changes host continuous interactions or service/browser flow, inspect `scripts/browser-tests/host.test.js` and `service/host.test.mbt`.
6. Keep one main path. Do not add parallel runtime concepts unless the task explicitly requires it.

## Hard Rules

- Treat `VNode` as a real runtime DOM node with a stable unique `id`.
- Prefer stable root nodes plus `D(...)` for style/attr/text changes.
- Do not use outer `Dyn(fn() { h(...) })` for cases that only change style, text, or attrs.
- `h_map` is the stable list path. Prefer it when list item identity matters.
- `ui-id` is the stable naming source. Do not encode list position into `ui-id`.
- `ui-react` owns and stops its local reactive scope. `ui-name` and `ui-list` do not imply reactive ownership.
- Prefer CSS rules for most styling. Keep inline `style` / `style:*` small and local.
- Inline style should mainly carry CSS variables or narrow style switches. Do not fill DOM tree definitions with large style strings when a CSS rule can express the same thing.
- Production event dispatch should rely on runtime node `id`. Do not add `ui-id` fallback routing in the service bridge.
- If you change `DomCmd` protocol, bridge command handling, or bridge target resolution, update browser bridge tests in the same change.

## Current Behavior Boundaries

- Plain `Dyn` still rebuilds fresh children when it returns fresh child structures.
- `h_map/h_map_dyn` already preserve stable list item identity.
- `h_map` item roots that return `Dyn(...)` are also treated as stable runtime fragments.
- `ui-react` currently creates a local reactive scope that is stopped on node removal.
- `ui-name` / `ui-list` require a host `ui-id` and only affect query semantics.
- Bridge query/exec can target by runtime `id`, `ui_id`, or selector, but production event dispatch still depends on runtime `id`.
- Bridge command protocol currently includes `InsertAfter` and browser tests should cover it.

## Read Next When Needed

- Runtime and usage constraints: `references/runtime-semantics.md`
