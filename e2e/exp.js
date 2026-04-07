import { describe, expect, it } from '../scripts/test-browser.js'

describe('browser native events', () => {
  it('double click dispatches native click and dblclick in order', async t => {
    await t.page.setContent(`
      <button id="btn">demo</button>
      <script>
        window.__events = []
        const btn = document.getElementById('btn')
        ;['mousedown', 'mouseup', 'click', 'dblclick'].forEach(type => {
          btn.addEventListener(type, () => {
            window.__events.push(type)
          })
        })
      </script>
    `)
    await t.page.dblclick('#btn', { delay: 120, timeout: t.options.timeoutMs })
    const events = await t.page.evaluate(() => window.__events.slice())
    expect(events.filter(v => v === 'click').length).toBe(2)
    expect(events.filter(v => v === 'dblclick').length).toBe(1)
    expect(events[events.length - 1]).toBe('dblclick')
  })
})
