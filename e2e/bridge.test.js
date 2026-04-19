import { beforeAll, describe, expect, it } from '../scripts/test-browser.js'

const textOf = value => Array.isArray(value) && value[0] === 'Text' ? value[1] ?? '' : ''
const nodeOf = value => Array.isArray(value) && value[0] === 'Node' ? value[1] ?? null : null
const parseMeasure = text => {
  const m = /^box=(\d+)x(\d+) view=(\d+)x(\d+) text=(\d+)$/.exec(text)
  if (!m) {
    return null
  }
  return {
    boxW: Number(m[1]),
    boxH: Number(m[2]),
    viewW: Number(m[3]),
    viewH: Number(m[4]),
    textW: Number(m[5]),
  }
}
const parseMultiMeasure = text => {
  const m = /^count=(\d+) view=(\d+)x(\d+) text=(\d+)$/.exec(text)
  if (!m) {
    return null
  }
  return {
    count: Number(m[1]),
    viewW: Number(m[2]),
    viewH: Number(m[3]),
    textW: Number(m[4]),
  }
}
const parseResize = text => {
  const m = /^resize=(\d+)x(\d+)$/.exec(text)
  if (!m) {
    return null
  }
  return {
    viewW: Number(m[1]),
    viewH: Number(m[2]),
  }
}

describe('bridge runtime', () => {
  beforeAll(async t => {
    await t.open()
  })

  it('reports connected status and runs cli', async t => {
    const status = await t.page.evaluate(() => globalThis.mbt_bridge.status())
    expect(status.state).toBe('connected')
    const cliStatus = await t.page.evaluate(() => globalThis.mbt_bridge.cli('status'))
    expect(cliStatus.includes('running')).toBeTruthy()
  })

  it('resets the current page and reloads the demo root', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('demo'))
    const [body, hostEntry] = await t.page.evaluate(async () => {
      const body = await globalThis.mbt_bridge.query('demo-body', 'text')
      const hostEntry = await globalThis.mbt_bridge.query('entries/0/name', 'text').catch(() => null)
      return [body, hostEntry]
    })
    expect(textOf(body)).toBe('Demo app')
    expect(hostEntry).toBe(null)
    const status = await t.page.evaluate(() => globalThis.mbt_bridge.status())
    expect(status.state).toBe('connected')
  })

  it('keeps pointermove and pointerup on the same node after pointerdown capture', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('pointer-capture'))
    await t.wait([{ kind: 'exists', path: 'capture-box' }], 'pointer capture page appears')
    const box = await t.pointOf('capture-box')
    expect(!!box).toBeTruthy()
    await t.page.mouse.move(box.x, box.y)
    await t.page.mouse.down()
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('capture-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'down'
    }, null, { timeout: t.options.timeoutMs })
    await t.page.mouse.move(box.x + 220, box.y + 140)
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('capture-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && typeof v[1] === 'string' && v[1].startsWith('move:')
    }, null, { timeout: t.options.timeoutMs })
    await t.page.mouse.up()
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('capture-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'up'
    }, null, { timeout: t.options.timeoutMs })
  })

  it('measures browser data through batched read and updates dom', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('measure-read'))
    await t.wait([{ kind: 'exists', path: 'measure-box' }], 'measure page appears')
    await t.dispatch({ path: 'measure-box', kind: 'click' })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('measure-state', 'text')
      if (!Array.isArray(v) || v[0] !== 'Text' || typeof v[1] !== 'string') {
        return false
      }
      const m = /^box=(\d+)x(\d+) view=(\d+)x(\d+) text=(\d+)$/.exec(v[1])
      return !!m &&
        Number(m[1]) > 0 &&
        Number(m[2]) > 0 &&
        Number(m[3]) > 0 &&
        Number(m[4]) > 0 &&
        Number(m[5]) > 0
    }, null, { timeout: t.options.timeoutMs })
    const state = await t.page.evaluate(() => globalThis.mbt_bridge.query('measure-state', 'text'))
    const value = parseMeasure(textOf(state))
    expect(value).toBeTruthy()
    expect(value.boxW > 0).toBeTruthy()
    expect(value.boxH > 0).toBeTruthy()
    expect(value.viewW > 0).toBeTruthy()
    expect(value.viewH > 0).toBeTruthy()
    expect(value.textW > 0).toBeTruthy()
  })

  it('keeps session state and browser reads isolated across browser sessions', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('multi-session'))
    await t.wait([{ kind: 'exists', path: 'multi-state' }], 'first multi session appears')
    const page2 = await t.openPage()
    await page2.evaluate(() => globalThis.mbt_bridge.reset('multi-session'))
    await page2.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=0 idle'
    }, null, { timeout: t.options.timeoutMs })

    await t.dispatch({ path: 'multi-add', kind: 'click' })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=1 idle'
    }, null, { timeout: t.options.timeoutMs })
    await page2.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=1 idle'
    }, null, { timeout: t.options.timeoutMs })

    await page2.evaluate(() => globalThis.mbt_bridge.dispatch('multi-add', 'click'))
    await page2.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=2 idle'
    }, null, { timeout: t.options.timeoutMs })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=2 idle'
    }, null, { timeout: t.options.timeoutMs })

    await t.dispatch({ path: 'multi-measure-box', kind: 'click' })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      if (!Array.isArray(v) || v[0] !== 'Text' || typeof v[1] !== 'string') {
        return false
      }
      const m = /^count=(\d+) view=(\d+)x(\d+) text=(\d+)$/.exec(v[1])
      return !!m &&
        Number(m[1]) === 2 &&
        Number(m[2]) > 0 &&
        Number(m[3]) > 0 &&
        Number(m[4]) > 0
    }, null, { timeout: t.options.timeoutMs })
    const firstMeasured = await t.page.evaluate(() => globalThis.mbt_bridge.query('multi-state', 'text'))
    const firstValue = parseMultiMeasure(textOf(firstMeasured))
    expect(firstValue).toBeTruthy()
    expect(firstValue.count).toBe(2)
    expect(firstValue.viewW > 0).toBeTruthy()
    expect(firstValue.viewH > 0).toBeTruthy()
    expect(firstValue.textW > 0).toBeTruthy()
    const stillIdle = await page2.evaluate(() => globalThis.mbt_bridge.query('multi-state', 'text'))
    expect(textOf(stillIdle).endsWith(' idle')).toBeTruthy()

    await page2.evaluate(() => globalThis.mbt_bridge.dispatch('multi-measure-box', 'click'))
    await page2.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      if (!Array.isArray(v) || v[0] !== 'Text' || typeof v[1] !== 'string') {
        return false
      }
      const m = /^count=(\d+) view=(\d+)x(\d+) text=(\d+)$/.exec(v[1])
      return !!m &&
        Number(m[1]) === 2 &&
        Number(m[2]) > 0 &&
        Number(m[3]) > 0 &&
        Number(m[4]) > 0
    }, null, { timeout: t.options.timeoutMs })
    const secondMeasured = await page2.evaluate(() => globalThis.mbt_bridge.query('multi-state', 'text'))
    const secondValue = parseMultiMeasure(textOf(secondMeasured))
    expect(secondValue).toBeTruthy()
    expect(secondValue.count).toBe(2)
    expect(secondValue.viewW > 0).toBeTruthy()
    expect(secondValue.viewH > 0).toBeTruthy()
    expect(secondValue.textW > 0).toBeTruthy()
    await page2.close()
  })

  it('routes scroll resize and composition through the browser bridge', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('event-probe'))
    await t.wait([
      { kind: 'exists', path: 'probe-scroll-box' },
      { kind: 'exists', path: 'probe-resize-box' },
      { kind: 'exists', path: 'probe-input' },
    ], 'event probe appears')

    await t.page.evaluate(async () => {
      const value = await globalThis.mbt_bridge.query('probe-scroll-box', 'attr', 'class')
      const cls = Array.isArray(value) && value[0] === 'Attr' ? value[2] ?? '' : ''
      const node = document.querySelector(`.${cls}`)
      node.scrollTop = 48
      node.dispatchEvent(new Event('scroll'))
    })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('probe-scroll-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'scroll=48'
    }, null, { timeout: t.options.timeoutMs })

    await t.dispatch({ path: 'probe-resize-btn', kind: 'click' })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('probe-resize-state', 'text')
      if (!Array.isArray(v) || v[0] !== 'Text' || typeof v[1] !== 'string') {
        return false
      }
      const m = /^resize=(\d+)x(\d+)$/.exec(v[1])
      return !!m && Number(m[1]) > 0 && Number(m[2]) > 0
    }, null, { timeout: t.options.timeoutMs })
    const resizeState = await t.page.evaluate(() => globalThis.mbt_bridge.query('probe-resize-state', 'text'))
    const resizeValue = parseResize(textOf(resizeState))
    expect(resizeValue).toBeTruthy()
    expect(resizeValue.viewW > 0).toBeTruthy()
    expect(resizeValue.viewH > 0).toBeTruthy()
    await t.page.waitForTimeout(80)
    const stableResizeState = await t.page.evaluate(() => globalThis.mbt_bridge.query('probe-resize-state', 'text'))
    const stableResizeValue = parseResize(textOf(stableResizeState))
    expect(stableResizeValue).toBeTruthy()
    expect(stableResizeValue.viewW > 0).toBeTruthy()
    expect(stableResizeValue.viewH > 0).toBeTruthy()

    await t.page.evaluate(async () => {
      const value = await globalThis.mbt_bridge.query('probe-input', 'attr', 'class')
      const cls = Array.isArray(value) && value[0] === 'Attr' ? value[2] ?? '' : ''
      const node = document.querySelector(`.${cls}`)
      node.dispatchEvent(new CompositionEvent('compositionstart'))
      node.dispatchEvent(new CompositionEvent('compositionend'))
      node.dispatchEvent(new CompositionEvent('compositioncancel'))
    })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('probe-composition-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'composition=cancel'
    }, null, { timeout: t.options.timeoutMs })
  })
})
