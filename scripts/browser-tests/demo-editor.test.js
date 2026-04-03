import { beforeEach, describe, expect, it } from '../test-browser.js'

describe('demo editor scroll', () => {
  beforeEach(async t => {
    await t.goto()
    await t.waitForUI('entry:demo')
    await t.dblclickUI('entry:demo')
    await t.waitForUI('window:1')
  })

  it('keeps editor scroll when adding todo', async t => {
    await t.page.evaluate(() => {
      for (let i = 0; i < 12; i += 1) {
        document.querySelector('[ui-id="demo-add"]')
          ?.dispatchEvent(new MouseEvent('click', { bubbles: true }))
      }
    })
    await t.page.waitForTimeout(100)
    const before = await t.page.evaluate(() => {
      const node = document.querySelector('[ui-id="demo-editor"]')?.parentElement
      if (!node) {
        return null
      }
      node.scrollTop = node.scrollHeight
      return {
        top: node.scrollTop,
        height: node.scrollHeight,
      }
    })
    await t.page.evaluate(() => {
      document.querySelector('[ui-id="demo-add"]')
        ?.dispatchEvent(new MouseEvent('click', { bubbles: true }))
    })
    await t.page.waitForTimeout(100)
    const after = await t.page.evaluate(() => {
      const node = document.querySelector('[ui-id="demo-editor"]')?.parentElement
      if (!node) {
        return null
      }
      return {
        top: node.scrollTop,
        height: node.scrollHeight,
      }
    })
    expect(before).toBeTruthy()
    expect(after).toBeTruthy()
    expect(after.height > before.height).toBeTruthy()
    expect(after.top).toBe(before.top)
  })
})
