import { beforeAll, describe, expect, it } from '../test-browser.js'

describe('entry host', () => {
  beforeAll(async t => {
    await t.mount(['host'], ['entry:demo'])
  })

  it('mounts desktop entry nodes through bridge path query', async t => {
    const [entry, desktop, entryName] = await t.read([
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
    const [entryBefore] = await t.read([{ kind: 'node', path: 'entry:demo' }])
    await t.page.evaluate(() => {
      const sent = []
      const ws = window.mbt_bridge.ws
      const rawSend = ws.send.bind(ws)
      ws.send = data => {
        try {
          sent.push(JSON.parse(data))
        } catch {
          sent.push(data)
        }
        return rawSend(data)
      }
      window.__host_sent = sent
    })
    await t.step({
      label: 'host dblclick event',
      act: [{ kind: 'pointer', name: 'dblclick', target: 'entry:demo' }],
      wait: [
        { kind: 'sent_event', source: '__host_sent', eventType: 'event', event: 'ondblclick' },
      ],
    })
    expect(entryBefore?.id > 0).toBeTruthy()
    const sent = await t.page.evaluate(() => window.__host_sent.slice())
    const dblclick = sent.find(item => item?.type === 'event' && item?.event === 'ondblclick')
    expect(dblclick?.id).toBe(entryBefore.id)
    const [windowNode, topbarNode, titleText] = await t.step({
      label: 'host spawn demo window after dblclick',
      wait: [
        { kind: 'exists', path: 'window:1' },
        { kind: 'exists', path: 'topbar-window:1' },
        { kind: 'text_includes', path: 'window:1/titlebar', value: 'Demo Todo' },
      ],
      read: [
        { kind: 'node', path: 'window:1' },
        { kind: 'node', path: 'topbar-window:1' },
        { kind: 'text', path: 'window:1/titlebar' },
      ],
    })
    expect(windowNode?.id > 0).toBeTruthy()
    expect(topbarNode?.id > 0).toBeTruthy()
    expect(titleText?.text).toContain('Demo Todo')
  })
})
