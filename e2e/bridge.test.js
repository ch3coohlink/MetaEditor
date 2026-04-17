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

  it('queries default host content through current ws bridge', async t => {
    const [entryName, entryNode, entryClass, entryClick] = await t.query([
      { kind: 'text', path: 'entries/0/name' },
      { kind: 'node', path: 'entries/0/entry' },
      { kind: 'attr', path: 'entries/0/entry', value: 'class' },
      { kind: 'prop', path: 'entries/0/entry', value: 'onclick' },
    ])
    expect(entryName?.text).toBe('Demo')
    expect(entryNode?.id > 0).toBeTruthy()
    expect(typeof entryClass?.value === 'string' && entryClass.value.length > 0).toBeTruthy()
    expect(entryClick?.value).toBe('onclick')
  })

  it('dispatches click through current ws bridge', async t => {
    await t.trigger({ path: 'entries/0/entry', kind: 'click' })
    await t.wait([
      { kind: 'exists', path: 'windows/0/title' },
      { kind: 'text_eq', path: 'windows/0/title', value: 'Demo' },
    ], 'host window appears')
  })

  it('resets the current page and reloads the root', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    const resetOk = await t.page.evaluate(async () => {
      for (let i = 0; i < 100; i += 1) {
        const name = await globalThis.mbt_bridge.query('entries/0/name', 'text')
          .catch(() => null)
        if (name?.text === 'Demo') {
          return true
        }
        await new Promise(resolve => setTimeout(resolve, 20))
      }
      return false
    })
    expect(resetOk).toBe(true)
    const status = await t.page.evaluate(() => globalThis.mbt_bridge.status())
    expect(status.state).toBe('connected')
  })
})
