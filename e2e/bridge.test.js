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
})
