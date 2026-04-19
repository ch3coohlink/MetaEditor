import { beforeAll, describe, expect, it } from '../scripts/test-browser.js'

const textOf = value => Array.isArray(value) && value[0] === 'Text' ? value[1] ?? '' : ''
const nodeOf = value => Array.isArray(value) && value[0] === 'Node' ? value[1] ?? null : null

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
      return Array.isArray(v) &&
        v[0] === 'Text' &&
        typeof v[1] === 'string' &&
        /^box=\d+x\d+ view=\d+x\d+ text=\d+$/.test(v[1])
    }, null, { timeout: t.options.timeoutMs })
  })

  it('keeps session state and browser reads isolated across browser sessions', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('multi-session'))
    await t.wait([{ kind: 'exists', path: 'multi-state' }], 'first multi session appears')
    const page2 = await t.openSession()
    await page2.page.evaluate(() => globalThis.mbt_bridge.reset('multi-session'))
    await page2.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=0 idle'
    }, null, { timeout: t.options.timeoutMs })

    await t.dispatch({ path: 'multi-add', kind: 'click' })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=1 idle'
    }, null, { timeout: t.options.timeoutMs })
    await page2.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=1 idle'
    }, null, { timeout: t.options.timeoutMs })

    await page2.page.evaluate(() => globalThis.mbt_bridge.dispatch('multi-add', 'click'))
    await page2.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=2 idle'
    }, null, { timeout: t.options.timeoutMs })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && v[1] === 'count=2 idle'
    }, null, { timeout: t.options.timeoutMs })

    await t.dispatch({ path: 'multi-measure', kind: 'click' })
    await t.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && /^count=2 view=\d+x44 text=\d+$/.test(v[1])
    }, null, { timeout: t.options.timeoutMs })
    const stillIdle = await page2.page.evaluate(() => globalThis.mbt_bridge.query('multi-state', 'text'))
    expect(textOf(stillIdle).endsWith(' idle')).toBeTruthy()

    await page2.page.evaluate(() => globalThis.mbt_bridge.dispatch('multi-measure', 'click'))
    await page2.page.waitForFunction(async () => {
      const v = await globalThis.mbt_bridge.query('multi-state', 'text')
      return Array.isArray(v) && v[0] === 'Text' && /^count=2 view=\d+x44 text=\d+$/.test(v[1])
    }, null, { timeout: t.options.timeoutMs })
    await page2.close()
  })
})
