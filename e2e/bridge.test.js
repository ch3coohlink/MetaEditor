import { beforeAll, describe, expect, it } from '../scripts/test-browser.js'

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
    expect(body?.text).toBe('Demo app')
    expect(hostEntry).toBe(null)
    const status = await t.page.evaluate(() => globalThis.mbt_bridge.status())
    expect(status.state).toBe('connected')
  })
})
