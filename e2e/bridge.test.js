import { afterAll, beforeAll, beforeEach, describe, expect, it } from '../scripts/test-browser.js'

const listen = (event, extra = {}) => ({
  event,
  capture: false,
  passive: false,
  prevent: false,
  stop: false,
  policies: [],
  ...extra,
})

describe('bridge runtime', () => {
  beforeAll(async t => {
    await t.open()
  })

  it('queries default host content through current ws bridge', async t => {
    const [entryName, entryNode] = await t.query([
      { kind: 'text', path: 'entries/0/name' },
      { kind: 'node', path: 'entries/0/entry' },
    ])
    expect(entryName?.text).toBe('Demo')
    expect(entryNode?.id > 0).toBeTruthy()
  })

  it('dispatches click through current ws bridge', async t => {
    await t.trigger({ path: 'entries/0/entry', kind: 'click' })
    await t.wait([
      { kind: 'exists', path: 'windows/0/title' },
      { kind: 'text_eq', path: 'windows/0/title', value: 'Demo' },
    ], 'host window appears')
  })
})

describe('bridge whitebox', () => {
  beforeAll(async t => {
    await t.open()
  })

  beforeEach(async t => {
    await t.useFakeBridge()
    t.domCmd = await t.page.evaluate(() => window.mbt_bridge.bridgeTest.DOM_CMD)
  })

  afterAll(async t => {
    await t.restoreBridge()
  })

  it('applies dom commands into runtime body root and reads them by vnode id', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 100, 'div'],
      [t.domCmd.ATTR, 100, 'ui-id', 'root'],
      [t.domCmd.STYLE, 100, 'background-color', 'rgb(1, 2, 3)'],
      [t.domCmd.CREATE, 101, '', 'hello'],
      [t.domCmd.INSERT, 100, 101],
      [t.domCmd.CREATE, 102, 'input'],
      [t.domCmd.PROP, 102, 'value', 'typed'],
      [t.domCmd.INSERT, 100, 102],
      [t.domCmd.INSERT, 2, 100],
    ])
    const [node, text, attr, style, prop] = await t.query([
      { kind: 'node', id: 100 },
      { kind: 'text', id: 100 },
      { kind: 'attr', id: 100, value: 'ui-id' },
      { kind: 'style', id: 100, value: 'background-color' },
      { kind: 'prop', id: 102, value: 'value' },
    ])
    expect(node?.id).toBe(100)
    expect(text?.text).toBe('hello')
    expect(attr?.value).toBe('root')
    expect(style?.value).toBe('rgb(1, 2, 3)')
    expect(prop?.value).toBe('typed')
  })

  it('inserts before and after reference under the same parent', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 200, 'div'],
      [t.domCmd.ATTR, 200, 'ui-id', 'insert-parent'],
      [t.domCmd.INSERT, 2, 200],
      [t.domCmd.CREATE, 201, 'div', 'first'],
      [t.domCmd.ATTR, 201, 'ui-id', 'insert-first'],
      [t.domCmd.INSERT, 200, 201],
      [t.domCmd.CREATE, 202, 'div', 'second'],
      [t.domCmd.ATTR, 202, 'ui-id', 'insert-second'],
      [t.domCmd.INSERT, 200, 202, 201, true],
      [t.domCmd.CREATE, 203, 'div', 'third'],
      [t.domCmd.ATTR, 203, 'ui-id', 'insert-third'],
      [t.domCmd.INSERT, 200, 203, 202, false],
    ])
    const order = await t.page.evaluate(() =>
      Array.from(document.querySelector('[ui-id="insert-parent"]').children)
        .map(node => node.getAttribute('ui-id')))
    expect(JSON.stringify(order)).toBe(
      JSON.stringify(['insert-first', 'insert-third', 'insert-second']),
    )
  })

  it('triggerById updates form value and focus locally', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 300, 'input'],
      [t.domCmd.ATTR, 300, 'ui-id', 'trigger-input'],
      [t.domCmd.INSERT, 2, 300],
    ])
    const result = await t.page.evaluate(() => {
      const bridge = window.mbt_bridge.bridgeTest
      bridge.triggerById({ id: 300, kind: 'focus' })
      bridge.triggerById({ id: 300, kind: 'input', text: 'typed by bridge' })
      const node = document.querySelector('[ui-id="trigger-input"]')
      return {
        value: node.value,
        focused: document.activeElement === node,
      }
    })
    expect(result.value).toBe('typed by bridge')
    expect(result.focused).toBeTruthy()
  })

  it('listener stop only affects local bubbling semantics', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 400, 'div'],
      [t.domCmd.ATTR, 400, 'ui-id', 'outer'],
      [t.domCmd.INSERT, 2, 400],
      [t.domCmd.CREATE, 401, 'button'],
      [t.domCmd.ATTR, 401, 'ui-id', 'inner'],
      [t.domCmd.LISTEN, 401, listen('onclick', { stop: true })],
      [t.domCmd.INSERT, 400, 401],
    ])
    const result = await t.page.evaluate(() => {
      const outer = document.querySelector('[ui-id="outer"]')
      const inner = document.querySelector('[ui-id="inner"]')
      let bubbled = 0
      outer.addEventListener('click', () => {
        bubbled += 1
      })
      window.mbt_bridge.bridgeTest.triggerById({ id: 401, kind: 'click' })
      return { bubbled }
    })
    expect(result.bubbled).toBe(0)
  })

  it('listener prevent and passive follow current browser behavior', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 500, 'div'],
      [t.domCmd.ATTR, 500, 'ui-id', 'prevent-target'],
      [t.domCmd.LISTEN, 500, listen('onpointerdown', { prevent: true })],
      [t.domCmd.INSERT, 2, 500],
      [t.domCmd.CREATE, 510, 'div'],
      [t.domCmd.ATTR, 510, 'ui-id', 'passive-target'],
      [t.domCmd.LISTEN, 510, listen('onpointermove', { passive: true, prevent: true })],
      [t.domCmd.INSERT, 2, 510],
    ])
    const result = await t.page.evaluate(() => {
      const preventNode = document.querySelector('[ui-id="prevent-target"]')
      const passiveNode = document.querySelector('[ui-id="passive-target"]')
      const down = new PointerEvent('pointerdown', { bubbles: true, cancelable: true })
      const move = new PointerEvent('pointermove', { bubbles: true, cancelable: true })
      const downAllowed = preventNode.dispatchEvent(down)
      const moveAllowed = passiveNode.dispatchEvent(move)
      return {
        downAllowed,
        downPrevented: down.defaultPrevented,
        moveAllowed,
        movePrevented: move.defaultPrevented,
      }
    })
    expect(result.downAllowed).toBe(false)
    expect(result.downPrevented).toBe(true)
    expect(result.moveAllowed).toBe(true)
    expect(result.movePrevented).toBe(false)
  })
})
