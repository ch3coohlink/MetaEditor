import { beforeAll, describe, expect, it } from '../scripts/test-browser.js'

let rootId = 'host-1'
const rootPath = path => `${rootId}/${path}`

describe('entry host', () => {
  beforeAll(async t => {
    ;[rootId] = await t.mount(['host'])
  })

  it('mounts desktop entry nodes through bridge path query', async t => {
    const [entry, desktop, entryName] = await t.query([
      { kind: 'node', path: rootPath('entries/0/entry') },
      { kind: 'node', path: rootPath('desktop') },
      { kind: 'text', path: rootPath('entries/0/name') },
    ])
    expect(entry?.id > 0).toBeTruthy()
    expect(desktop?.id > 0).toBeTruthy()
    expect(entryName?.text).toContain('Demo Todo')
  })

  it('keeps state across host dblclick and window spawn flow', async t => {
    // 这类连续交互要保留前一步状态，不按每条用例都重置页面来写
    const [entryBefore] = await t.query([{ kind: 'node', path: rootPath('entries/0/entry') }])
    await t.trigger({ path: rootPath('entries/0/entry'), kind: 'dblclick' })
    expect(entryBefore?.id > 0).toBeTruthy()
    await t.wait([
      { kind: 'exists', path: rootPath('windows/0/window') },
      { kind: 'exists', path: rootPath('topbar-windows/0/window') },
      { kind: 'text_includes', path: rootPath('windows/0/titlebar'), value: 'Demo Todo' },
    ], 'host spawn demo window wait')
    const [windowNode, topbarNode, titleText] = await t.query([
      { kind: 'node', path: rootPath('windows/0/window') },
      { kind: 'node', path: rootPath('topbar-windows/0/window') },
      { kind: 'text', path: rootPath('windows/0/titlebar') },
    ])
    expect(windowNode?.id > 0).toBeTruthy()
    expect(topbarNode?.id > 0).toBeTruthy()
    expect(titleText?.text).toContain('Demo Todo')
  })

  it('keeps desktop interaction paths reachable with open window', async t => {
    await t.trigger({ path: rootPath('entries/0/entry'), kind: 'dblclick' })
    await t.wait([
      { kind: 'exists', path: rootPath('windows/0/window') },
      { kind: 'exists', path: rootPath('topbar-windows/0/window') },
      { kind: 'text_includes', path: rootPath('windows/0/titlebar'), value: 'Demo Todo' },
    ], 'host ensure window wait')
    await t.trigger({ path: rootPath('entries/0/entry'), kind: 'click' })
    await t.trigger({ path: rootPath('topbar-windows/0/window'), kind: 'click' })
    await t.trigger({ path: rootPath('desktop'), kind: 'pointerdown' })
    await t.wait([
      { kind: 'exists', path: rootPath('windows/0/window') },
      { kind: 'exists', path: rootPath('topbar-windows/0/window') },
    ], 'host desktop interaction wait')
  })
})
