import { beforeAll, describe, expect, it } from '../scripts/test-browser.js'

const entryPath = async (page, title) => {
  for (let i = 0; i < 8; i += 1) {
    const value = await page.evaluate(async path => {
      try {
        return await globalThis.mbt_bridge.query(path, 'text')
      } catch {
        return null
      }
    }, `entries/${i}/name`)
    if (value?.text === title) {
      return `entries/${i}/entry`
    }
  }
  throw Error(`missing entry: ${title}`)
}

describe('host runtime', () => {
  beforeAll(async t => {
    await t.open()
  })

  it('queries default host content through current ws bridge', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    const demoEntry = await entryPath(t.page, 'Demo')
    const demoName = demoEntry.replace('/entry', '/name')
    const [entryName, entryNode, entryClass, entryClick, latency, time] = await t.query([
      { kind: 'text', path: demoName },
      { kind: 'node', path: demoEntry },
      { kind: 'attr', path: demoEntry, value: 'class' },
      { kind: 'prop', path: demoEntry, value: 'onclick' },
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
    await t.dispatch({ path: await entryPath(t.page, 'Demo'), kind: 'click' })
    await t.wait([
      { kind: 'exists', path: 'windows/0/title' },
      { kind: 'text_eq', path: 'windows/0/title', value: 'Demo' },
    ], 'host window appears after real click')
  })

  it('drags a window by its title bar', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    await t.bridge('dispatch', [await entryPath(t.page, 'Demo'), 'click'])
    await t.wait([
      { kind: 'exists', path: 'windows/0/title' },
      { kind: 'text_eq', path: 'windows/0/title', value: 'Demo' },
    ], 'host window appears before drag')
    const titlePoint = await t.page.evaluate(async () => {
      const node = await globalThis.mbt_bridge.query('windows/0/title', 'node')
      return globalThis.__mbt_bridge_internal?.pointOf?.(node?.id ?? 0) ?? null
    })
    expect(!!titlePoint).toBeTruthy()
    const before = await t.page.evaluate(async () => {
      const left = await globalThis.mbt_bridge.query('windows/0/window', 'style', 'left')
      const top = await globalThis.mbt_bridge.query('windows/0/window', 'style', 'top')
      return { left: left?.value ?? '', top: top?.value ?? '' }
    })
    await t.page.mouse.move(titlePoint.x, titlePoint.y)
    await t.page.mouse.down()
    await t.page.mouse.move(titlePoint.x + 120, titlePoint.y + 80)
    await t.page.mouse.up()
    await t.page.waitForFunction(async expected => {
      const left = await globalThis.mbt_bridge.query('windows/0/window', 'style', 'left')
      const top = await globalThis.mbt_bridge.query('windows/0/window', 'style', 'top')
      return (left?.value ?? '') !== expected.left || (top?.value ?? '') !== expected.top
    }, before, { timeout: t.options.timeoutMs })
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
    await t.bridge('dispatch', [await entryPath(t.page, 'Demo'), 'click'])
    await t.wait([
      { kind: 'exists', path: 'windows/0/title' },
      { kind: 'text_eq', path: 'windows/0/title', value: 'Demo' },
    ], 'host window appears')
  })

  it('syncs dom updates to another browser without waiting for its next request', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    const page2 = await t.openPage()
    await page2.evaluate(() => globalThis.mbt_bridge.reset('host'))
    await t.dispatch({ path: await entryPath(t.page, 'Demo'), kind: 'click' })
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

  it('closes the latest demo window after multiple opens', async t => {
    await t.page.evaluate(() => globalThis.mbt_bridge.reset('host'))
    const demoEntry = await entryPath(t.page, 'Demo')
    await t.bridge('dispatch', [demoEntry, 'click'])
    await t.bridge('dispatch', [demoEntry, 'click'])
    await t.bridge('dispatch', [demoEntry, 'click'])
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
