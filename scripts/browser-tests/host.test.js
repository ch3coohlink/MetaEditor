import { beforeAll, describe, expect, it } from '../test-browser.js'

describe('entry host', () => {
  beforeAll(async t => {
    await t.mount(['host'], ['entry:demo'])
  })

  it('mounts desktop entry nodes through bridge path query', async t => {
    const [entry, desktop, entryName] = await t.query([
      { kind: 'node', path: 'entry:demo' },
      { kind: 'node', path: 'desktop-root' },
      { kind: 'text', path: 'entry:demo/entry-name' },
    ])
    expect(entry?.id > 0).toBeTruthy()
    expect(desktop?.id > 0).toBeTruthy()
    expect(entryName?.text).toContain('Demo Todo')
  })

  it('keeps state across host dblclick and window spawn flow', async t => {
    // 这类连续交互要保留前一步状态，不按每条用例都重置页面来写
    const [entryBefore] = await t.query([{ kind: 'node', path: 'entry:demo' }])
    await t.trigger({ path: 'entry:demo', kind: 'dblclick' })
    expect(entryBefore?.id > 0).toBeTruthy()
    await t.wait([
      { kind: 'exists', path: 'window:1' },
      { kind: 'exists', path: 'topbar-window:1' },
      { kind: 'text_includes', path: 'window:1/titlebar', value: 'Demo Todo' },
    ], 'host spawn demo window wait')
    const [windowNode, topbarNode, titleText] = await t.query([
      { kind: 'node', path: 'window:1' },
      { kind: 'node', path: 'topbar-window:1' },
      { kind: 'text', path: 'window:1/titlebar' },
    ])
    expect(windowNode?.id > 0).toBeTruthy()
    expect(topbarNode?.id > 0).toBeTruthy()
    expect(titleText?.text).toContain('Demo Todo')
  })

  it('keeps desktop selection style independent from window focus and clears on desktop click', async t => {
    await t.trigger({ path: 'entry:demo', kind: 'click' })
    await t.wait([
      { kind: 'exists', path: 'window:1' },
      { kind: 'exists', path: 'topbar-window:1' },
      { kind: 'style_eq', path: 'entry:demo', name: 'background-color', value: 'rgb(215, 235, 255)' },
    ], 'host existing window wait')
    await t.trigger({ path: 'topbar-window:1', kind: 'click' })
    const [selectedWithWindowFocus] = await t.query([
      { kind: 'style', path: 'entry:demo', value: 'background-color' },
    ])
    expect(selectedWithWindowFocus?.value).toBe('rgb(215, 235, 255)')
    await t.trigger({ path: 'desktop-root', kind: 'click' })
    await t.wait([
      { kind: 'style_eq', path: 'entry:demo', name: 'background-color', value: 'rgba(255, 255, 255, 0.2)' },
    ], 'host clear desktop selection wait')
  })
})
