import { beforeEach, describe, expect, it } from '../test-browser.js'

describe('host desktop', () => {
  beforeEach(async t => {
    await t.goto()
    await t.waitForUI('entry:demo')
  })

  it('double click sends expected events and opens a window', async t => {
    const beforeId = await t.page.locator('[ui-id="entry:demo"]').getAttribute('data-mbt-id')
    await t.clickUI('entry:demo')
    await t.page.waitForFunction(() => {
      return (document.querySelector('[ui-id="entry:demo"]')?.getAttribute('style') ?? '').includes('#6aa7ff')
    }, { timeout: t.options.timeoutMs })
    const afterId = await t.page.locator('[ui-id="entry:demo"]').getAttribute('data-mbt-id')
    expect(afterId).toBe(beforeId)
    await t.page.evaluate(() => {
      const sent = []
      const ws = window.mbt_bridge.ws
      const rawSend = ws.send.bind(ws)
      ws.send = data => {
        try {
          sent.push(JSON.parse(data))
        } catch {}
        return rawSend(data)
      }
      window.__mbt_sent = sent
    })
    await t.dblclickUI('entry:demo')
    await t.waitForUI('window:1')
    const messages = await t.page.evaluate(() => window.__mbt_sent.slice())
    const events = messages.filter(v => v.type === 'event' && v.ui_id === 'entry:demo')
    expect(events.length).toBe(3)
    expect(events[0].event).toBe('onclick')
    expect(events[1].event).toBe('onclick')
    expect(events[2].event).toBe('ondblclick')
    expect(Object.prototype.hasOwnProperty.call(events[2], 'id')).toBeFalsy()
    const count = await t.page.evaluate(() => {
      return Array.from(document.querySelectorAll('[ui-id^="window:"]'))
        .filter(node => {
          const uiId = node.getAttribute('ui-id') ?? ''
          return uiId.startsWith('window:') && !uiId.includes('/')
        })
        .length
    })
    expect(count).toBe(1)
  })
})
