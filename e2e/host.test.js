import { beforeAll, describe, expect, it } from '../scripts/test-browser.js'

const demoEntry = 'root/workspace/desktop/entries/items/0/entry'
const demoEntryName = 'root/workspace/desktop/entries/items/0/entry/name'
const firstWindow = 'root/workspace/windows/items/0/window'
const firstWindowTitlebar = 'root/workspace/windows/items/0/window/titlebar'
const firstTopbarWindow = 'root/topbar/left/windows/items/0/topbar-window'

describe('entry host', () => {
  beforeAll(async t => {
    await t.mount(['host'], ['root'])
  })

  it('mounts desktop entry nodes through bridge path query', async t => {
    const [entry, desktop, entryName] = await t.query([
      { kind: 'node', path: demoEntry },
      { kind: 'node', path: 'root/workspace/desktop' },
      { kind: 'text', path: demoEntryName },
    ])
    expect(entry?.id > 0).toBeTruthy()
    expect(desktop?.id > 0).toBeTruthy()
    expect(entryName?.text).toContain('Demo Todo')
  })

  it('keeps state across host dblclick and window spawn flow', async t => {
    // 这类连续交互要保留前一步状态，不按每条用例都重置页面来写
    const [entryBefore] = await t.query([{ kind: 'node', path: demoEntry }])
    await t.trigger({ path: demoEntry, kind: 'dblclick' })
    expect(entryBefore?.id > 0).toBeTruthy()
    await t.wait([
      { kind: 'exists', path: firstWindow },
      { kind: 'exists', path: firstTopbarWindow },
      { kind: 'text_includes', path: firstWindowTitlebar, value: 'Demo Todo' },
    ], 'host spawn demo window wait')
    const [windowNode, topbarNode, titleText] = await t.query([
      { kind: 'node', path: firstWindow },
      { kind: 'node', path: firstTopbarWindow },
      { kind: 'text', path: firstWindowTitlebar },
    ])
    expect(windowNode?.id > 0).toBeTruthy()
    expect(topbarNode?.id > 0).toBeTruthy()
    expect(titleText?.text).toContain('Demo Todo')
  })

  it('keeps desktop selection style independent from window focus and clears on desktop click', async t => {
    await t.trigger({ path: demoEntry, kind: 'click' })
    await t.wait([
      { kind: 'exists', path: firstWindow },
      { kind: 'exists', path: firstTopbarWindow },
      { kind: 'style_eq', path: demoEntry, name: 'background-color', value: 'rgb(215, 235, 255)' },
    ], 'host existing window wait')
    await t.trigger({ path: firstTopbarWindow, kind: 'click' })
    const [selectedWithWindowFocus] = await t.query([
      { kind: 'style', path: demoEntry, value: 'background-color' },
    ])
    expect(selectedWithWindowFocus?.value).toBe('rgb(215, 235, 255)')
    await t.trigger({ path: 'root/workspace/desktop/background', kind: 'click' })
    await t.wait([
      { kind: 'style_eq', path: demoEntry, name: 'background-color', value: 'rgba(255, 255, 255, 0.2)' },
    ], 'host clear desktop selection wait')
  })
})
