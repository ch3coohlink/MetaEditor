import { describe, expect, it } from '../test-browser.js'

describe('host desktop', () => {
  it('double click entry opens a window', async t => {
    await t.goto()
    try {
      await t.waitForUI('entry:demo')
    } catch (error) {
      const debug = await t.dumpDebug({
        entryCount: await t.countUI('entry:demo'),
        appInfoText: await t.page.locator('#app-info').innerText().catch(() => null),
      })
      throw Error(`${error.message}\n${JSON.stringify(debug, null, 2)}`)
    }
    await t.dblclickUI('entry:demo')
    try {
      await t.waitForUI('window:1')
    } catch (error) {
      const debug = await t.dumpDebug({
        entryVisible: await t.countUI('entry:demo'),
        windowCount: await t.countUI('window:1'),
      })
      throw Error(`${error.message}\n${JSON.stringify(debug, null, 2)}`)
    }
    expect(await t.countUI('window:1')).toBe(1)
  })
})
