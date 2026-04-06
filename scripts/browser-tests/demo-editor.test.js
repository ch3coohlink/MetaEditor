import { beforeAll, describe, expect, it } from '../test-browser.js'

describe('entry demo', () => {
  beforeAll(async t => {
    await t.mount(['demo'], ['demo-editor', 'demo-add', 'demo-summary'])
  })

  it('mounts core nodes through bridge path query', async t => {
    const [editor, addButton, summary] = await t.read([
      { kind: 'node', path: 'demo-editor' },
      { kind: 'node', path: 'demo-add' },
      { kind: 'text', path: 'demo-summary' },
    ])
    expect(editor?.id > 0).toBeTruthy()
    expect(addButton?.id > 0).toBeTruthy()
    expect(summary?.text).toContain('Visible 1 / 2 todos')
  })

  it('runs add action through unified pointer act path', async t => {
    const [beforeSummary] = await t.read([{ kind: 'text', path: 'demo-summary' }])
    const [afterSummary, newItem] = await t.step({
      label: 'demo add todo',
      act: [{ kind: 'pointer', name: 'click', target: 'demo-add' }],
      wait: [
        { kind: 'text_eq', path: 'demo-summary', value: 'Visible 2 / 3 todos' },
        { kind: 'exists', path: 'demo-list/1/text' },
      ],
      read: [
        { kind: 'text', path: 'demo-summary' },
        { kind: 'text', path: 'demo-list/1/text' },
      ],
    })
    expect(beforeSummary?.text).toBe('Visible 1 / 2 todos')
    expect(afterSummary?.text).toBe('Visible 2 / 3 todos')
    expect(newItem?.text).toContain('Todo 3')
  })
})
