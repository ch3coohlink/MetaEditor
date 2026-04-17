import { beforeAll, describe, expect, it } from '../scripts/test-browser.js'

describe('host runtime', () => {
  beforeAll(async t => {
    await t.open()
  })

  it('queries default host content through current ws bridge', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    const [entryName, entryNode, entryClass, entryClick, latency, time] = await t.query([
      { kind: 'text', path: 'entries/0/name' },
      { kind: 'node', path: 'entries/0/entry' },
      { kind: 'attr', path: 'entries/0/entry', value: 'class' },
      { kind: 'prop', path: 'entries/0/entry', value: 'onclick' },
      { kind: 'text', path: 'latency' },
      { kind: 'text', path: 'time' },
    ])
    expect(entryName?.text).toBe('Demo')
    expect(entryNode?.id > 0).toBeTruthy()
    expect(typeof entryClass?.value === 'string' && entryClass.value.length > 0).toBeTruthy()
    expect(entryClick?.value).toBe('onclick')
    expect(latency?.text).toBe('--ms')
    expect(time?.text).toBe('--:--')
  })

  it('opens a window through real page click', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    await t.dispatch({ path: 'entries/0/entry', kind: 'click' })
    await t.wait([
      { kind: 'exists', path: 'windows/0/title' },
      { kind: 'text_eq', path: 'windows/0/title', value: 'Demo' },
    ], 'host window appears after real click')
  })

  it('keeps desktop pinned to current window size', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    const size = await t.page.evaluate(() => ({
      client: document.documentElement.clientHeight,
      scroll: document.documentElement.scrollHeight,
    }))
    expect(size.scroll).toBe(size.client)
  })

  it('dispatches click through current ws bridge', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    await t.bridge('dispatch', ['entries/0/entry', 'click'])
    await t.wait([
      { kind: 'exists', path: 'windows/0/title' },
      { kind: 'text_eq', path: 'windows/0/title', value: 'Demo' },
    ], 'host window appears')
  })

  it('syncs dom updates to another browser without waiting for its next request', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    const page2 = await t.openPage()
    await page2.evaluate(() => globalThis.mbt_bridge.reset('host'))
    await t.dispatch({ path: 'entries/0/entry', kind: 'click' })
    await page2.waitForFunction(async () => {
      try {
        const v = await globalThis.mbt_bridge.query('windows/0/title', 'text')
        return v?.text === 'Demo'
      } catch {
        return false
      }
    }, null, { timeout: t.options.timeoutMs })
    await page2.close()
  })

  it('closes the latest demo window through real page click after multiple opens', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    await t.dispatch({ path: 'entries/0/entry', kind: 'click' })
    await t.dispatch({ path: 'entries/0/entry', kind: 'click' })
    await t.dispatch({ path: 'entries/0/entry', kind: 'click' })
    await t.wait([
      { kind: 'exists', path: 'windows/2/title' },
      { kind: 'text_eq', path: 'windows/2/title', value: 'Demo' },
    ], 'third host window appears')
    await t.dispatch({ path: 'windows/2/close', kind: 'click' })
    const [second, third] = await t.page.evaluate(async () => {
      const second = await globalThis.mbt_bridge.query('windows/1/title', 'text').catch(() => null)
      const third = await globalThis.mbt_bridge.query('windows/2/title', 'text').catch(() => null)
      return [second, third]
    })
    expect(second?.text).toBe('Demo')
    expect(third).toBe(null)
  })
})
