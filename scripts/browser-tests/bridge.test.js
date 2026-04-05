import { afterAll, beforeAll, beforeEach, describe, expect, it } from '../test-browser.js'

describe('bridge runtime', () => {
  beforeAll(async t => {
    await t.open()
  })

  beforeEach(async t => {
    await t.useFakeBridge()
    t.domCmd = await t.page.evaluate(() => window.mbt_bridge.DOM_CMD)
  })

  afterAll(async t => {
    await t.restoreBridge()
  })

  it('resolves path queries after dom commands apply', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 100, 'div', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 100, 'ui-id', 'root'],
      [t.domCmd.CREATE, 101, '', ''],
      [t.domCmd.TEXT, 101, 'hello'],
      [t.domCmd.APPEND, 100, 101],
      [t.domCmd.APPEND, 0, 100],
    ])
    const [node, text] = await t.read([
      { kind: 'node', path: 'root' },
      { kind: 'text', path: 'root' },
    ])
    expect(node?.id).toBe(100)
    expect(text?.text).toBe('hello')
  })

  it('runs unified pointer and key actions on vnode ids resolved from path', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 200, 'div', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 200, 'ui-id', 'event-root'],
      [t.domCmd.APPEND, 0, 200],
      [t.domCmd.CREATE, 201, 'button', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 201, 'ui-id', 'event-btn'],
      [t.domCmd.TEXT, 201, 'x'],
      [t.domCmd.LISTEN, 201, 'onclick', 'event-btn'],
      [t.domCmd.LISTEN, 201, 'ondblclick', 'event-btn'],
      [t.domCmd.LISTEN, 201, 'onkeydown', 'event-btn'],
      [t.domCmd.APPEND, 200, 201],
      [t.domCmd.HOST_CMD, 201, 'focus'],
    ])
    await t.step({
      label: 'bridge pointer and key actions',
      act: [
        { kind: 'pointer', name: 'click', target: 'event-btn' },
        { kind: 'pointer', name: 'dblclick', target: 'event-btn' },
        { kind: 'key', name: 'keydown', target: 'event-btn', key: 'Enter', code: 'Enter' },
      ],
    })
    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const clickEvents = sent.filter(v => v.type === 'event' && v.event === 'onclick')
    const dblclickEvents = sent.filter(v => v.type === 'event' && v.event === 'ondblclick')
    const keyEvents = sent.filter(v => v.type === 'event_data' && v.event === 'onkeydown')
    expect(clickEvents.length >= 1).toBeTruthy()
    expect(dblclickEvents.length).toBe(1)
    expect(keyEvents.length).toBe(1)
    expect(clickEvents.every(v => v.id === 201)).toBeTruthy()
    expect(dblclickEvents[0].id).toBe(201)
    expect(keyEvents[0].id).toBe(201)
    expect(keyEvents[0].data).toContain('Enter')
  })
})
