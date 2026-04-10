import { afterAll, beforeAll, beforeEach, describe, expect, it } from '../scripts/test-browser.js'

const listen = (event, extra = {}) => ({
  event,
  capture: false,
  passive: false,
  prevent: ['onclick', 'ondblclick', 'onpointerdown', 'onpointerup', 'onpointermove', 'onkeydown', 'onkeyup']
    .includes(event),
  stop: false,
  policies: [],
  ...extra,
})
const keyPolicy = (extra = {}) => ({
  key: undefined,
  code: undefined,
  ctrl: undefined,
  shift: undefined,
  alt: undefined,
  meta: undefined,
  prevent: false,
  stop: false,
  ...extra,
})

describe('bridge runtime', () => {
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

  it('reads nodes by vnode id after dom commands apply', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 100, 'div'],
      [t.domCmd.ATTR, 100, 'ui-id', 'root'],
      [t.domCmd.STYLE, 100, 'background-color', 'rgb(1, 2, 3)'],
      [t.domCmd.CREATE, 102, 'input'],
      [t.domCmd.PROP, 102, 'value', 'typed'],
      [t.domCmd.INSERT, 100, 102],
      [t.domCmd.CREATE, 101, '', 'hello'],
      [t.domCmd.INSERT, 100, 101],
      [t.domCmd.INSERT, 0, 100],
    ])
    const [node, text, attr, style, prop, input] = await t.query([
      { kind: 'node', id: 100 },
      { kind: 'text', id: 100 },
      { kind: 'attr', id: 100, value: 'ui-id' },
      { kind: 'style', id: 100, value: 'background-color' },
      { kind: 'prop', id: 102, value: 'value' },
      { kind: 'node', id: 102 },
    ])
    expect(node?.id).toBe(100)
    expect(text?.text).toBe('hello')
    expect(attr?.value).toBe('root')
    expect(style?.value).toBe('rgb(1, 2, 3)')
    expect(prop?.value).toBe('typed')
    expect(input?.value).toBe('typed')
  })

  it('inserts child before and after reference under the same parent', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 500, 'div'],
      [t.domCmd.ATTR, 500, 'ui-id', 'insert-parent'],
      [t.domCmd.INSERT, 0, 500],
      [t.domCmd.CREATE, 501, 'div', 'first'],
      [t.domCmd.ATTR, 501, 'ui-id', 'insert-first'],
      [t.domCmd.INSERT, 500, 501],
      [t.domCmd.CREATE, 502, 'div', 'second'],
      [t.domCmd.ATTR, 502, 'ui-id', 'insert-second'],
      [t.domCmd.INSERT, 500, 502, 501, true],
      [t.domCmd.CREATE, 503, 'div', 'third'],
      [t.domCmd.ATTR, 503, 'ui-id', 'insert-third'],
      [t.domCmd.INSERT, 500, 503, 502, false],
    ])
    const order = await t.page.evaluate(() =>
      Array.from(document.querySelector('[ui-id="insert-parent"]').children)
        .map(node => node.getAttribute('ui-id')))
    expect(JSON.stringify(order)).toBe(
      JSON.stringify(['insert-first', 'insert-third', 'insert-second']),
    )
  })

  it('appends child when insert reference is managed but belongs to another parent', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 510, 'div'],
      [t.domCmd.ATTR, 510, 'ui-id', 'insert-parent-a'],
      [t.domCmd.INSERT, 0, 510],
      [t.domCmd.CREATE, 511, 'div'],
      [t.domCmd.ATTR, 511, 'ui-id', 'insert-parent-b'],
      [t.domCmd.INSERT, 0, 511],
      [t.domCmd.CREATE, 512, 'div', 'anchor'],
      [t.domCmd.ATTR, 512, 'ui-id', 'insert-anchor'],
      [t.domCmd.INSERT, 511, 512],
      [t.domCmd.CREATE, 513, 'div', 'moved'],
      [t.domCmd.ATTR, 513, 'ui-id', 'insert-moved'],
      [t.domCmd.INSERT, 510, 513, 512, false],
    ])
    const state = await t.page.evaluate(() => {
      const parentA = document.querySelector('[ui-id="insert-parent-a"]')
      const parentB = document.querySelector('[ui-id="insert-parent-b"]')
      const moved = document.querySelector('[ui-id="insert-moved"]')
      return {
        parentA: Array.from(parentA.children).map(node => node.getAttribute('ui-id')),
        parentB: Array.from(parentB.children).map(node => node.getAttribute('ui-id')),
        mounted: document.body.contains(moved),
        parentTag: moved.parentElement?.getAttribute('ui-id') ?? '',
      }
    })
    expect(JSON.stringify(state.parentA)).toBe(JSON.stringify(['insert-moved']))
    expect(JSON.stringify(state.parentB)).toBe(JSON.stringify(['insert-anchor']))
    expect(state.mounted).toBe(true)
    expect(state.parentTag).toBe('insert-parent-a')
  })

  it('reads mounted real DOM style through bridge path query', async t => {
    await t.restoreBridge()
    const [rootId] = await t.mount(['host'])
    const entryPath = `${rootId}/entries/0/entry`
    const [entry, bridgeStyle] = await t.query([
      { kind: 'node', path: entryPath },
      { kind: 'style', path: entryPath, value: 'background-color' },
    ])
    const domStyle = await t.page.evaluate(() => {
      const entry = document.querySelector('[ui-id="desktop"] [ui-id="entry"]')
      return {
        mounted: document.body.contains(entry),
        value: entry ? getComputedStyle(entry).getPropertyValue('background-color') : '',
      }
    })
    expect(entry?.id > 0).toBeTruthy()
    expect(domStyle.mounted).toBe(true)
    expect(bridgeStyle?.value).toBe(domStyle.value)
  })

  it('runs trigger actions on vnode ids', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 200, 'div'],
      [t.domCmd.ATTR, 200, 'ui-id', 'event-root'],
      [t.domCmd.INSERT, 0, 200],
      [t.domCmd.CREATE, 201, 'button', 'x'],
      [t.domCmd.ATTR, 201, 'ui-id', 'event-btn'],
      [t.domCmd.LISTEN, 201, listen('onclick')],
      [t.domCmd.LISTEN, 201, listen('ondblclick')],
      [t.domCmd.LISTEN, 201, listen('onpointerdown')],
      [t.domCmd.LISTEN, 201, listen('onkeydown')],
      [t.domCmd.INSERT, 200, 201],
    ])
    await t.trigger([
      { id: 201, kind: 'focus' },
      { id: 201, kind: 'click' },
      { id: 201, kind: 'dblclick' },
      { id: 201, kind: 'pointerdown' },
      { id: 201, kind: 'key', value: { key: 'Enter', event: 'keydown', code: 'Enter' } },
    ])
    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const clickEvents = sent.filter(v => v.type === 'event' && v.event === 'onclick')
    const dblclickEvents = sent.filter(v => v.type === 'event' && v.event === 'ondblclick')
    const pointerDownEvents = sent.filter(v => v.type === 'event_data' && v.event === 'onpointerdown')
    const keyEvents = sent.filter(v => v.type === 'event_data' && v.event === 'onkeydown')
    expect(clickEvents.length >= 1).toBeTruthy()
    expect(dblclickEvents.length).toBe(1)
    expect(pointerDownEvents.length).toBe(1)
    expect(keyEvents.length).toBe(1)
    expect(clickEvents.every(v => v.id === 201)).toBeTruthy()
    expect(dblclickEvents[0].id).toBe(201)
    expect(pointerDownEvents[0].id).toBe(201)
    expect(keyEvents[0].id).toBe(201)
    expect(keyEvents[0].data.key).toBe('Enter')
  })

  it('stops bubbling for listeners with stop modifier', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 300, 'div'],
      [t.domCmd.ATTR, 300, 'ui-id', 'outer'],
      [t.domCmd.LISTEN, 300, listen('onclick')],
      [t.domCmd.INSERT, 0, 300],
      [t.domCmd.CREATE, 301, 'button'],
      [t.domCmd.ATTR, 301, 'ui-id', 'inner'],
      [t.domCmd.LISTEN, 301, listen('onclick', { stop: true })],
      [t.domCmd.INSERT, 300, 301],
    ])
    await t.trigger([{ id: 301, kind: 'click' }])
    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const outerClicks = sent.filter(v => v.type === 'event' && v.id === 300 && v.event === 'onclick')
    const innerClicks = sent.filter(v => v.type === 'event' && v.id === 301 && v.event === 'onclick')
    expect(innerClicks.length).toBe(1)
    expect(outerClicks.length).toBe(0)
  })

  it('applies policy prevent and stop only when key match hits', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 400, 'div'],
      [t.domCmd.ATTR, 400, 'ui-id', 'outer-key'],
      [t.domCmd.INSERT, 0, 400],
      [t.domCmd.CREATE, 401, 'input'],
      [t.domCmd.ATTR, 401, 'ui-id', 'inner-key'],
      [t.domCmd.LISTEN, 401, listen('onkeydown', {
        prevent: false,
        policies: [keyPolicy({ key: 's', ctrl: true, prevent: true, stop: true })],
      })],
      [t.domCmd.INSERT, 400, 401],
    ])
    const result = await t.page.evaluate(() => {
      const outer = document.querySelector('[ui-id="outer-key"]')
      const inner = document.querySelector('[ui-id="inner-key"]')
      const seen = []
      outer.addEventListener('keydown', e => {
        seen.push({
          key: e.key,
          defaultPrevented: e.defaultPrevented,
        })
      })
      const hit = new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        key: 's',
        ctrlKey: true,
      })
      const miss = new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        key: 'x',
        ctrlKey: true,
      })
      const hitAllowed = inner.dispatchEvent(hit)
      const missAllowed = inner.dispatchEvent(miss)
      return {
        hitAllowed,
        missAllowed,
        hitDefaultPrevented: hit.defaultPrevented,
        missDefaultPrevented: miss.defaultPrevented,
        seen,
      }
    })
    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const keys = sent.filter(v => v.type === 'event_data' && v.id === 401).map(v => v.data.key)
    expect(result.hitAllowed).toBe(false)
    expect(result.hitDefaultPrevented).toBe(true)
    expect(result.missAllowed).toBe(true)
    expect(result.missDefaultPrevented).toBe(false)
    expect(JSON.stringify(result.seen)).toBe(JSON.stringify([{ key: 'x', defaultPrevented: false }]))
    expect(JSON.stringify(keys)).toBe(JSON.stringify(['s', 'x']))
  })

  it('falls back to spec default when policy does not override stop', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 410, 'div'],
      [t.domCmd.ATTR, 410, 'ui-id', 'outer-stop-default'],
      [t.domCmd.LISTEN, 410, listen('onclick')],
      [t.domCmd.INSERT, 0, 410],
      [t.domCmd.CREATE, 411, 'button'],
      [t.domCmd.ATTR, 411, 'ui-id', 'inner-stop-default'],
      [t.domCmd.LISTEN, 411, listen('onclick', {
        stop: true,
        policies: [keyPolicy({ key: 'Enter', prevent: true })],
      })],
      [t.domCmd.INSERT, 410, 411],
    ])
    await t.trigger([{ id: 411, kind: 'click' }])
    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const outerClicks = sent.filter(v => v.type === 'event' && v.id === 410 && v.event === 'onclick')
    const innerClicks = sent.filter(v => v.type === 'event' && v.id === 411 && v.event === 'onclick')
    expect(innerClicks.length).toBe(1)
    expect(outerClicks.length).toBe(0)
  })

  it('replaces previous listener spec when listen command is sent again', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 420, 'div'],
      [t.domCmd.ATTR, 420, 'ui-id', 'outer-relisten'],
      [t.domCmd.INSERT, 0, 420],
      [t.domCmd.CREATE, 421, 'input'],
      [t.domCmd.ATTR, 421, 'ui-id', 'inner-relisten'],
      [t.domCmd.LISTEN, 421, listen('onkeydown')],
      [t.domCmd.INSERT, 420, 421],
    ])
    await t.applyDom([
      [t.domCmd.LISTEN, 421, listen('onkeydown', {
        prevent: false,
        policies: [keyPolicy({ key: 'p', prevent: true, stop: true })],
      })],
    ])
    const result = await t.page.evaluate(() => {
      const outer = document.querySelector('[ui-id="outer-relisten"]')
      const inner = document.querySelector('[ui-id="inner-relisten"]')
      let bubbled = 0
      outer.addEventListener('keydown', () => {
        bubbled += 1
      })
      const hit = new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        key: 'p',
      })
      const miss = new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        key: 'q',
      })
      const hitAllowed = inner.dispatchEvent(hit)
      const missAllowed = inner.dispatchEvent(miss)
      return {
        hitAllowed,
        missAllowed,
        hitDefaultPrevented: hit.defaultPrevented,
        missDefaultPrevented: miss.defaultPrevented,
        bubbled,
      }
    })
    expect(result.hitAllowed).toBe(false)
    expect(result.hitDefaultPrevented).toBe(true)
    expect(result.missAllowed).toBe(true)
    expect(result.missDefaultPrevented).toBe(false)
    expect(result.bubbled).toBe(1)
  })

  it('runs capture listener before target bubble listener', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 430, 'div'],
      [t.domCmd.ATTR, 430, 'ui-id', 'outer-capture'],
      [t.domCmd.LISTEN, 430, listen('onclick', { capture: true, prevent: false })],
      [t.domCmd.INSERT, 0, 430],
      [t.domCmd.CREATE, 431, 'button'],
      [t.domCmd.ATTR, 431, 'ui-id', 'inner-capture'],
      [t.domCmd.LISTEN, 431, listen('onclick', { prevent: false })],
      [t.domCmd.INSERT, 430, 431],
    ])
    await t.trigger([{ id: 431, kind: 'click' }])
    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const clicks = sent.filter(v => v.type === 'event' && v.event === 'onclick')
    expect(clicks.length).toBe(2)
    expect(clicks[0].id).toBe(430)
    expect(clicks[1].id).toBe(431)
  })

  it('keeps passive listener from marking event defaultPrevented', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 440, 'div'],
      [t.domCmd.ATTR, 440, 'ui-id', 'passive-target'],
      [t.domCmd.LISTEN, 440, listen('onpointermove', { passive: true, prevent: true })],
      [t.domCmd.INSERT, 0, 440],
    ])
    const result = await t.page.evaluate(() => {
      const node = document.querySelector('[ui-id="passive-target"]')
      const ev = new PointerEvent('pointermove', {
        bubbles: true,
        cancelable: true,
        pointerId: 7,
      })
      const allowed = node.dispatchEvent(ev)
      return {
        allowed,
        defaultPrevented: ev.defaultPrevented,
      }
    })
    const sent = await t.page.evaluate(() => window.__bridge_sent.slice())
    const moveEvents = sent.filter(v => v.type === 'event_data' && v.id === 440 && v.event === 'onpointermove')
    expect(result.allowed).toBe(true)
    expect(result.defaultPrevented).toBe(false)
    expect(moveEvents.length).toBe(1)
  })

  it('matches policy by code and modifiers', async t => {
    await t.applyDom([
      [t.domCmd.CREATE, 450, 'div'],
      [t.domCmd.ATTR, 450, 'ui-id', 'outer-code'],
      [t.domCmd.INSERT, 0, 450],
      [t.domCmd.CREATE, 451, 'input'],
      [t.domCmd.ATTR, 451, 'ui-id', 'inner-code'],
      [t.domCmd.LISTEN, 451, listen('onkeydown', {
        prevent: false,
        policies: [keyPolicy({
          code: 'KeyP',
          meta: true,
          shift: true,
          prevent: true,
          stop: true,
        })],
      })],
      [t.domCmd.INSERT, 450, 451],
    ])
    const result = await t.page.evaluate(() => {
      const outer = document.querySelector('[ui-id="outer-code"]')
      const inner = document.querySelector('[ui-id="inner-code"]')
      let bubbled = 0
      outer.addEventListener('keydown', () => {
        bubbled += 1
      })
      const hit = new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        key: 'p',
        code: 'KeyP',
        metaKey: true,
        shiftKey: true,
      })
      const miss = new KeyboardEvent('keydown', {
        bubbles: true,
        cancelable: true,
        key: 'p',
        code: 'KeyP',
        metaKey: true,
        shiftKey: false,
      })
      const hitAllowed = inner.dispatchEvent(hit)
      const missAllowed = inner.dispatchEvent(miss)
      return {
        hitAllowed,
        missAllowed,
        hitDefaultPrevented: hit.defaultPrevented,
        missDefaultPrevented: miss.defaultPrevented,
        bubbled,
      }
    })
    expect(result.hitAllowed).toBe(false)
    expect(result.hitDefaultPrevented).toBe(true)
    expect(result.missAllowed).toBe(true)
    expect(result.missDefaultPrevented).toBe(false)
    expect(result.bubbled).toBe(1)
  })
})
