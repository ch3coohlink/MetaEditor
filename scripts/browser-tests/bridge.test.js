import { beforeEach, describe, expect, it } from '../test-browser.js'

const apply = (t, cmds) => t.page.evaluate(cmds => {
  window.mbt_bridge.apply(cmds)
}, cmds)

const setupBridge = t => t.page.evaluate(() => {
  const bridge = window.mbt_bridge
  bridge.should_reconnect = false
  if (bridge.reconnect_timer != null) {
    clearTimeout(bridge.reconnect_timer)
    bridge.reconnect_timer = null
  }
  bridge.ws = {
    readyState: 1,
    send(data) {
      try {
        window.__bridge_sent.push(JSON.parse(data))
      } catch {
        window.__bridge_sent.push(data)
      }
    },
    close() {},
  }
  window.__bridge_sent = []
  document.body.replaceChildren()
  for (const node of document.querySelectorAll('[data-mbt-css]')) {
    node.remove()
  }
})

describe('bridge dom commands', () => {
  beforeEach(async t => {
    await t.goto()
    await setupBridge(t)
    t.domCmd = await t.page.evaluate(() => window.mbt_bridge.DOM_CMD)
  })

  it('creates, updates and removes nodes, attrs and styles', async t => {
    await apply(t, [
      [t.domCmd.CREATE, 100, 'div', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 100, 'ui-id', 'root'],
      [t.domCmd.ATTR, 100, 'data-state', 'init'],
      [t.domCmd.SET_STYLE, 100, 'color', 'red'],
      [t.domCmd.CREATE, 101, '', ''],
      [t.domCmd.TEXT, 101, 'hello'],
      [t.domCmd.APPEND, 100, 101],
      [t.domCmd.APPEND, 0, 100],
      [t.domCmd.UPDATE_ATTR, 100, 'data-state', 'ready'],
      [t.domCmd.UPDATE_TEXT, 101, 'world'],
      [t.domCmd.REMOVE_ATTR, 100, 'data-state'],
      [t.domCmd.REMOVE_STYLE, 100, 'color'],
    ])
    const first = await t.page.evaluate(() => {
      const root = document.querySelector('[ui-id="root"]')
      return {
        tag: root?.tagName?.toLowerCase(),
        text: root?.textContent,
        dataState: root?.getAttribute('data-state'),
        color: root?.style?.getPropertyValue('color'),
        nodeId: root?.getAttribute('data-mbt-id'),
      }
    })
    expect(first.tag).toBe('div')
    expect(first.text).toBe('world')
    expect(first.dataState).toBe(null)
    expect(first.color).toBe('')
    expect(first.nodeId).toBe('100')

    await apply(t, [[t.domCmd.REMOVE, 100]])
    const count = await t.page.evaluate(() => document.querySelectorAll('[ui-id="root"]').length)
    expect(count).toBe(0)
  })

  it('keeps DOM order correct for append and insertBefore', async t => {
    await apply(t, [
      [t.domCmd.CREATE, 200, 'div', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 200, 'ui-id', 'order-root'],
      [t.domCmd.APPEND, 0, 200],
      [t.domCmd.CREATE, 201, 'span', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 201, 'ui-id', 'a'],
      [t.domCmd.CREATE, 202, 'span', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 202, 'ui-id', 'b'],
      [t.domCmd.CREATE, 203, 'span', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 203, 'ui-id', 'c'],
      [t.domCmd.APPEND, 200, 201],
      [t.domCmd.APPEND, 200, 202],
      [t.domCmd.INSERT_BEFORE, 200, 203, 202],
    ])
    let order = await t.page.evaluate(() =>
      Array.from(document.querySelector('[ui-id="order-root"]').children).map(node => node.getAttribute('ui-id'))
    )
    expect(order.join(',')).toBe('a,c,b')
  })

  it('applies host commands and stylesheet commands', async t => {
    await apply(t, [
      [t.domCmd.CREATE, 300, 'input', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 300, 'ui-id', 'focus-target'],
      [t.domCmd.APPEND, 0, 300],
      [t.domCmd.HOST_CMD, 300, 'focus'],
      [t.domCmd.SET_CSS, 'theme', '.x { color: red; }'],
    ])
    const focused = await t.page.evaluate(() => document.activeElement?.getAttribute('ui-id'))
    const cssText = await t.page.evaluate(() => document.querySelector('[data-mbt-css="theme"]')?.textContent ?? '')
    expect(focused).toBe('focus-target')
    expect(cssText).toContain('color: red')

    await apply(t, [[t.domCmd.REMOVE_CSS, 'theme']])
    const cssCount = await t.page.evaluate(() => document.querySelectorAll('[data-mbt-css="theme"]').length)
    expect(cssCount).toBe(0)
  })

  it('sends click, dblclick and key event payloads with stable ids after moves', async t => {
    await apply(t, [
      [t.domCmd.CREATE, 400, 'div', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 400, 'ui-id', 'event-root'],
      [t.domCmd.APPEND, 0, 400],
      [t.domCmd.CREATE, 401, 'button', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 401, 'ui-id', 'event-btn'],
      [t.domCmd.TEXT, 401, 'x'],
      [t.domCmd.LISTEN, 401, 'onclick', 'event-btn'],
      [t.domCmd.LISTEN, 401, 'ondblclick', 'event-btn'],
      [t.domCmd.LISTEN, 401, 'onkeydown', 'event-btn'],
      [t.domCmd.APPEND, 400, 401],
      [t.domCmd.CREATE, 402, 'span', 'http://www.w3.org/1999/xhtml'],
      [t.domCmd.ATTR, 402, 'ui-id', 'tail'],
      [t.domCmd.APPEND, 400, 402],
      [t.domCmd.INSERT_BEFORE, 400, 401, 402],
    ])
    const nodeId = await t.page.evaluate(() =>
      document.querySelector('[ui-id="event-btn"]').getAttribute('data-mbt-id')
    )
    expect(nodeId).toBe('401')

    await t.page.click('[ui-id="event-btn"]')
    await t.page.dblclick('[ui-id="event-btn"]', { delay: 40, timeout: t.options.timeoutMs })
    await t.page.focus('[ui-id="event-btn"]')
    await t.page.keyboard.press('Enter')

    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const clickEvents = sent.filter(v => v.type === 'event' && v.event === 'onclick')
    const dblclickEvents = sent.filter(v => v.type === 'event' && v.event === 'ondblclick')
    const keyEvents = sent.filter(v => v.type === 'event_data' && v.event === 'onkeydown')
    expect(clickEvents.length >= 3).toBeTruthy()
    expect(dblclickEvents.length).toBe(1)
    expect(keyEvents.length).toBe(1)
    expect(clickEvents.every(v => v.id === 401)).toBeTruthy()
    expect(dblclickEvents[0].id).toBe(401)
    expect(keyEvents[0].id).toBe(401)
    expect(keyEvents[0].data).toContain('Enter')
  })
})
