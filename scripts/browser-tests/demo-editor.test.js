import { beforeAll, describe, expect, it } from '../test-browser.js'

describe('demo editor scroll', () => {
  beforeAll(async t => {
    await t.setRoots(['demo'])
    for (let i = 0; i < 24; i += 1) {
      await t.execRoot('add')
    }
    await t.open()
    await t.waitForUI('demo-editor')
    await t.waitForCondition('demo fixture ready', () => {
      return document.querySelectorAll('[ui-id^="demo-item:"]:not([ui-id*="/"])').length === 25
    })
  })

  it('keeps editor scroll when adding todo', async t => {
    await t.page.evaluate(() => {
      const editor = document.querySelector('[ui-id="demo-editor"]')
      if (editor instanceof HTMLElement) {
        editor.style.height = '96px'
        editor.style.overflow = 'auto'
        editor.style.boxSizing = 'border-box'
      }
    })
    const before = await t.page.evaluate(() => {
      const node = document.querySelector('[ui-id="demo-editor"]')
      if (!(node instanceof HTMLElement)) {
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
    await t.waitForCondition('demo height grows', height => {
      const node = document.querySelector('[ui-id="demo-editor"]')
      return node instanceof HTMLElement && node.scrollHeight > height
    }, before.height)
    const after = await t.page.evaluate(() => {
      const node = document.querySelector('[ui-id="demo-editor"]')
      if (!(node instanceof HTMLElement)) {
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
