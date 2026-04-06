import { spawn } from 'node:child_process'
import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath, pathToFileURL } from 'node:url'

const suite = (name, parent = null) => ({
  name,
  parent,
  suites: [],
  tests: [],
  hooks: { beforeAll: [], afterAll: [], beforeEach: [], afterEach: [] },
})

let current
let root

const resetSuites = () => {
  root = current = suite('root')
}

const parseArgs = argv => {
  const options = {
    url: null,
    port: 18180,
    timeoutMs: 8000,
    totalTimeoutMs: 12000,
    metaTimeoutMs: 4000,
    headless: true,
    channel: process.platform === 'win32' ? 'msedge' : undefined,
    start: false,
    stop: false,
    timing: false,
    portLocked: false,
    stateDir: fs.mkdtempSync(path.join(os.tmpdir(), 'metaeditor-browser-test-')),
    cleanupStateDir: true,
    files: [],
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--url' && i + 1 < argv.length) {
      options.url = argv[i + 1]
      i += 1
    } else if (arg === '--port' && i + 1 < argv.length) {
      options.port = Number(argv[i + 1]) || options.port
      options.portLocked = true
      i += 1
    } else if (arg === '--state-dir' && i + 1 < argv.length) {
      options.stateDir = argv[i + 1]
      options.cleanupStateDir = false
      i += 1
    } else if (arg === '--timeout' && i + 1 < argv.length) {
      options.timeoutMs = Number(argv[i + 1]) || options.timeoutMs
      i += 1
    } else if (arg === '--total-timeout' && i + 1 < argv.length) {
      options.totalTimeoutMs = Number(argv[i + 1]) || options.totalTimeoutMs
      i += 1
    } else if (arg === '--meta-timeout' && i + 1 < argv.length) {
      options.metaTimeoutMs = Number(argv[i + 1]) || options.metaTimeoutMs
      i += 1
    } else if (arg === '--head') {
      options.headless = false
    } else if (arg === '--channel' && i + 1 < argv.length) {
      options.channel = argv[i + 1]
      i += 1
    } else if (arg === '--start') {
      options.start = true
    } else if (arg === '--stop') {
      options.stop = true
    } else if (arg === '--timing') {
      options.timing = true
    } else {
      options.files.push(arg)
    }
  }
  if (!options.url) {
    options.url = `http://127.0.0.1:${options.port}`
  }
  return options
}

const nowMs = () => Number(process.hrtime.bigint() / 1000000n)

const createTiming = enabled => ({
  enabled,
  rows: [],
  totals: new Map(),
})

const timingPush = (timing, scope, label, elapsedMs) => {
  const row = { scope, label, elapsedMs }
  timing.rows.push(row)
  const key = `${scope}\n${label}`
  const current = timing.totals.get(key) ?? {
    scope,
    label,
    count: 0,
    totalMs: 0,
    maxMs: 0,
  }
  current.count += 1
  current.totalMs += elapsedMs
  current.maxMs = Math.max(current.maxMs, elapsedMs)
  timing.totals.set(key, current)
}

const withTiming = async (timing, scope, label, run) => {
  const started = nowMs()
  try {
    return await run()
  } finally {
    timingPush(timing, scope, label, nowMs() - started)
  }
}

const maybeWithTiming = async (timing, scope, label, run) => {
  if (!timing?.enabled) {
    return run()
  }
  return withTiming(timing, scope, label, run)
}

const printTiming = timing => {
  if (!timing.enabled) {
    return
  }
  if (Array.isArray(timing.accounting) && timing.accounting.length > 0) {
    const total = timing.accounting.reduce((sum, item) => sum + item.elapsedMs, 0)
    console.log('[browser-test timing] accounting')
    for (const item of timing.accounting) {
      console.log(`  ${item.label} ${item.elapsedMs}ms`)
    }
    console.log(`  accounted total ${total}ms`)
  }
  const summary = Array.from(timing.totals.values())
    .sort((a, b) => b.totalMs - a.totalMs)
  console.log('[browser-test timing] summary')
  for (const item of summary) {
    console.log(
      `  ${item.scope} :: ${item.label} count=${item.count} total=${item.totalMs}ms max=${item.maxMs}ms`,
    )
  }
  console.log('[browser-test timing] events')
  for (const row of timing.rows) {
    console.log(`  ${row.scope} :: ${row.label} ${row.elapsedMs}ms`)
  }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

const removeDirRetry = async target => {
  let lastError = null
  for (let tries = 0; tries < 10; tries += 1) {
    try {
      fs.rmSync(target, { recursive: true, force: true })
      return
    } catch (error) {
      lastError = error
      await sleep(50)
    }
  }
  if (lastError) {
    throw lastError
  }
}

const discoverTests = dir => {
  if (!fs.existsSync(dir)) {
    return []
  }
  const out = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      out.push(...discoverTests(full))
      continue
    }
    if (entry.isFile() && entry.name.endsWith('.test.js')) {
      out.push(path.relative(process.cwd(), full).replace(/\\/g, '/'))
    }
  }
  out.sort()
  return out
}

const defaultTestFiles = () => discoverTests(path.resolve(process.cwd(), 'scripts', 'browser-tests'))

const expect = actual => {
  const fail = message => {
    throw Error(message)
  }
  return {
    toBe(expected) {
      if (actual !== expected) {
        fail(`Expected ${JSON.stringify(actual)} to be ${JSON.stringify(expected)}`)
      }
    },
    toContain(expected) {
      if (!actual?.includes?.(expected)) {
        fail(`Expected ${JSON.stringify(actual)} to contain ${JSON.stringify(expected)}`)
      }
    },
    toBeTruthy() {
      if (!actual) {
        fail(`Expected ${JSON.stringify(actual)} to be truthy`)
      }
    },
    toBeFalsy() {
      if (actual) {
        fail(`Expected ${JSON.stringify(actual)} to be falsy`)
      }
    },
  }
}

const describe = (name, fn) => {
  const parent = current
  const child = suite(name, parent)
  parent.suites.push(child)
  current = child
  try {
    fn()
  } finally {
    current = parent
  }
}

const it = (name, fn) => {
  current.tests.push({ name, fn })
}

const beforeAll = fn => {
  current.hooks.beforeAll.push(fn)
}

const afterAll = fn => {
  current.hooks.afterAll.push(fn)
}

const beforeEach = fn => {
  current.hooks.beforeEach.push(fn)
}

const afterEach = fn => {
  current.hooks.afterEach.push(fn)
}

const failWithLabel = (label, error) => {
  const message = error?.stack ?? error?.message ?? String(error)
  throw Error(`${label}: ${message}`)
}

const runWithTimeout = async (label, timeoutMs, run, timing = null, scope = 'global') => {
  let timer = null
  try {
    const exec = async () => Promise.race([
      Promise.resolve().then(run),
      new Promise((_, reject) => {
        timer = setTimeout(() => {
          reject(Error(`${label} timed out after ${timeoutMs}ms`))
        }, timeoutMs)
      }),
    ])
    if (timing) {
      return await withTiming(timing, scope, label, exec)
    }
    return await exec()
  } catch (error) {
    failWithLabel(label, error)
  } finally {
    clearTimeout(timer)
  }
}

const pickPort = () => new Promise((resolve, reject) => {
  const server = net.createServer()
  server.unref()
  server.on('error', reject)
  server.listen(0, '127.0.0.1', () => {
    const address = server.address()
    if (!address || typeof address === 'string') {
      server.close(() => reject(Error('failed to allocate browser test port')))
      return
    }
    const { port } = address
    server.close(error => {
      if (error) {
        reject(error)
        return
      }
      resolve(port)
    })
  })
})

const serviceBin = () => path.resolve(
  process.cwd(),
  process.platform === 'win32'
    ? '_build/native/debug/build/service/service.exe'
    : '_build/native/debug/build/service/service',
)

const waitForServer = async (label, url, timeoutMs, timing = null, scope = 'service') => {
  await runWithTimeout(label, timeoutMs, async () => {
    for (;;) {
      try {
        const response = await fetch(url, { signal: AbortSignal.timeout(1000) })
        if (response.ok) {
          await response.text()
          return
        }
      } catch {}
      await new Promise(resolve => setTimeout(resolve, 10))
    }
  }, timing, scope)
}

const startService = async options => {
  const port = options.portLocked ? options.port : await pickPort()
  options.port = port
  options.url = `http://127.0.0.1:${port}`
  const bin = serviceBin()
  if (!fs.existsSync(bin)) {
    throw Error(`service binary is missing: ${bin}`)
  }
  await runWithTimeout('service spawn', options.totalTimeoutMs, async () => {
    const child = spawn(
      bin,
      ['--internal_boot_as_service', '--state-dir', options.stateDir, '--port', `${port}`],
      {
        cwd: process.cwd(),
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      },
    )
    let stderr = ''
    child.stderr.on('data', chunk => {
      stderr += chunk.toString()
    })
    child.on('error', error => {
      stderr += `\n${error.message}`
    })
    child.unref()
    await new Promise(resolve => setTimeout(resolve, 1))
    if (child.exitCode != null && child.exitCode !== 0) {
      throw Error(`service exited early (${child.exitCode})\n${stderr}`)
    }
  }, options.timingState, 'service')
  await waitForServer('wait service ready', options.url, options.timeoutMs, options.timingState, 'service')
}

const stopService = async options => {
  await runWithTimeout('service stop', options.metaTimeoutMs, async () => {
    const response = await fetch(`${options.url}/_meta/command`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ cmd: 'stop', arg: '' }),
    })
    if (!response.ok) {
      throw Error(`stop failed (${response.status})`)
    }
    await response.json()
  }, options.timingState, 'service').catch(() => {})
}

const collectHooks = (suiteNode, key) => {
  if (!suiteNode) {
    return []
  }
  return [...collectHooks(suiteNode.parent, key), ...suiteNode.hooks[key]]
}

const pageQuery = async spec => {
  const bridge = window.mbt_bridge
  if (typeof spec === 'string') {
    return bridge.query(spec)
  }
  if (spec?.kind === 'node' && spec.path != null) {
    return bridge.query(spec.path)
  }
  if (spec?.kind === 'text' && spec.path != null) {
    const node = bridge.query(spec.path)
    return node ? { id: node.id, text: node.text ?? '' } : null
  }
  return bridge.query(spec)
}

const pageRead = async specs => {
  const bridge = window.mbt_bridge
  const findUiNodeById = id => {
    const ui = bridge.queryLocal({ kind: 'ui' })
    const nodes = Array.isArray(ui?.nodes) ? ui.nodes : []
    return nodes.find(node => node?.id === id) ?? null
  }
  const querySpec = async spec => {
    if (spec.kind === 'node' && spec.path != null) {
      return bridge.query(spec.path)
    }
    if (spec.kind === 'text' && spec.path != null) {
      const node = await bridge.query(spec.path)
      return node ? { id: node.id, text: node.text ?? '' } : null
    }
    return bridge.query(spec)
  }
  const out = []
  for (const spec of specs) {
    if (spec.kind === 'node') {
      out.push(await querySpec(spec))
    } else if (spec.kind === 'text') {
      out.push(await querySpec(spec))
    } else if (spec.kind === 'focused') {
      const focused = bridge.queryLocal({ kind: 'focused' })
      out.push(focused ? findUiNodeById(focused.id) : null)
    } else if (spec.kind === 'ui') {
      out.push(bridge.queryLocal({ kind: 'ui' }))
    } else {
      throw Error(`unsupported read kind: ${spec.kind}`)
    }
  }
  return out
}

const pageWait = async specs => {
  const bridge = window.mbt_bridge
  const tryQuery = async path => {
    try {
      return await bridge.query(path)
    } catch {
      return null
    }
  }
  const readText = async path => {
    const node = await tryQuery(path)
    return node?.text ?? null
  }
  for (const spec of specs) {
    if (spec.kind === 'exists') {
      if (!await tryQuery(spec.path)) {
        return false
      }
      continue
    }
    if (spec.kind === 'missing') {
      if (await tryQuery(spec.path)) {
        return false
      }
      continue
    }
    if (spec.kind === 'text_eq') {
      if (await readText(spec.path) !== spec.value) {
        return false
      }
      continue
    }
    if (spec.kind === 'text_includes') {
      const text = await readText(spec.path)
      if (typeof text !== 'string' || !text.includes(spec.value)) {
        return false
      }
      continue
    }
    if (spec.kind === 'focus_path') {
      const focused = bridge.queryLocal({ kind: 'focused' })
      const target = await tryQuery(spec.path)
      if (!focused || !target || focused.id !== target.id) {
        return false
      }
      continue
    }
    if (spec.kind === 'sent_event') {
      const sent = Array.isArray(window[spec.source]) ? window[spec.source] : []
      if (!sent.some(item => item?.type === spec.eventType && item?.event === spec.event)) {
        return false
      }
      continue
    }
    throw Error(`unsupported wait kind: ${spec.kind}`)
  }
  return true
}

const createHarness = async options => {
  const timing = options.timingState
  let playwright
  try {
    playwright = await import('playwright')
  } catch {
    throw Error('playwright is not installed, run `npm install` first')
  }
  const launchBrowser = () => withTiming(timing, 'harness', 'launch browser', async () => playwright.chromium.launch({
    headless: options.headless,
    channel: options.channel,
  }))
  const browser = options.start
    ? (await Promise.all([
      withTiming(timing, 'harness', 'start service', async () => startService(options)),
      launchBrowser(),
    ]))[1]
    : await launchBrowser()
  const context = await withTiming(timing, 'harness', 'new context', async () => browser.newContext())
  const page = await withTiming(timing, 'harness', 'new page', async () => context.newPage())
  const consoleLogs = []
  page.on('console', msg => {
    consoleLogs.push(`${msg.type()}: ${msg.text()}`)
  })
  page.on('pageerror', error => {
    consoleLogs.push(`pageerror: ${error.message}`)
  })
  const harness = {
    options,
    page,
    consoleLogs,
    opened: false,
    currentRootIds: [],
    async goto() {
      await runWithTimeout('open page', options.timeoutMs, async () => {
        await page.goto(options.url, {
          waitUntil: 'domcontentloaded',
          timeout: options.timeoutMs,
        })
      }, timing, 'harness')
    },
    async open() {
      if (this.opened) {
        return
      }
      await this.goto()
      await this.wait([{ kind: 'bridge_ready' }], 'wait bridge ready')
      this.opened = true
    },
    async command(cmd, arg = '') {
      return runWithTimeout(`command ${cmd}`, options.timeoutMs, async () => {
        await this.open()
        return maybeWithTiming(timing, 'command:phase', `${cmd} request`, async () => {
          return page.evaluate(({ currentCmd, currentArg }) => {
            return window.mbt_bridge.command(currentCmd, currentArg)
          }, { currentCmd: cmd, currentArg: arg })
        })
      }, timing, 'command')
    },
    parseRoots(text) {
      const line = text.trim()
      if (line === 'roots cleared') {
        this.currentRootIds = []
        return []
      }
      if (!line.startsWith('roots ')) {
        throw Error(`unexpected roots response: ${text}`)
      }
      const ids = line.slice(6)
        .split(',')
        .map(v => v.trim())
        .filter(Boolean)
      this.currentRootIds = ids
      return ids
    },
    async mount(entryIds, ready = []) {
      const ids = Array.isArray(entryIds) ? entryIds : [entryIds]
      const arg = ids.map(id => JSON.stringify(id)).join(' ')
      await this.open()
      this.parseRoots(await this.command('roots', arg))
      await this.command('sync')
      if (ready.length > 0) {
        await this.wait(ready.map(path => ({ kind: 'exists', path })), `mount ${ids.join(', ')}`)
      }
      return this.currentRootIds
    },
    async query(pathOrSpec) {
      return runWithTimeout(`query ${JSON.stringify(pathOrSpec)}`, options.timeoutMs, async () => {
        return page.evaluate(pageQuery, pathOrSpec)
      }, timing, 'query')
    },
    async read(specs) {
      return runWithTimeout('read batch', options.timeoutMs, async () => {
        return page.evaluate(pageRead, specs)
      }, timing, 'read')
    },
    actionPoint(node, action, point = null) {
      const rect = node?.rect
      if (!rect) {
        throw Error(`action target has no rect: ${action.target ?? action.path ?? action.kind}`)
      }
      const baseX = rect.x + rect.width / 2
      const baseY = rect.y + rect.height / 2
      if (!point) {
        return { x: baseX, y: baseY }
      }
      return {
        x: point.x ?? baseX,
        y: point.y ?? baseY,
      }
    },
    async resolveActionTarget(action) {
      const target = action.target ?? action.path
      if (target == null) {
        throw Error(`action target missing for ${action.kind}`)
      }
      const node = await this.query(target)
      if (!node) {
        throw Error(`action target not found: ${target}`)
      }
      return node
    },
    async actionElement(node, action) {
      const target = action.target ?? action.path
      const handle = await page.evaluateHandle(async currentTarget => {
        return window.mbt_bridge.queryNodeForTest(currentTarget)
      }, target)
      const element = handle.asElement()
      if (!element) {
        await handle.dispose()
        throw Error(`action target has no element: ${action.target ?? action.path ?? action.kind}`)
      }
      return { element }
    },
    async withFocusedAction(action, run) {
      const node = await this.resolveActionTarget(action)
      const { element } = await this.actionElement(node, action)
      try {
        await element.focus()
      } finally {
        await element.dispose()
      }
      return run(node)
    },
    async runAction(action) {
      if (action.kind === 'focus') {
        return this.withFocusedAction(action, node => ({ ok: true, kind: 'focus', target: node }))
      }
      if (action.kind === 'input') {
        return this.withFocusedAction(action, async node => {
          await page.keyboard.press('ControlOrMeta+A')
          await page.keyboard.press('Delete')
          if ((action.text ?? '') !== '') {
            await page.keyboard.insertText(action.text)
          }
          return { ok: true, kind: 'input', target: node }
        })
      }
      if (action.kind === 'key') {
        return this.withFocusedAction(action, async node => {
          if (action.press) {
            await page.keyboard.press(action.press)
            return { ok: true, kind: 'key', name: action.press, target: node }
          }
          const name = action.name ?? 'keydown'
          if (name === 'keydown') {
            await page.keyboard.down(action.key)
          } else if (name === 'keyup') {
            await page.keyboard.up(action.key)
          } else {
            throw Error(`unsupported key action: ${name}`)
          }
          return { ok: true, kind: 'key', name, target: node }
        })
      }
      if (action.kind === 'pointer') {
        const node = await this.resolveActionTarget(action)
        const { x, y } = this.actionPoint(node, action)
        const name = action.name ?? 'click'
        if (name === 'click') {
          await page.mouse.click(x, y, { clickCount: 1, delay: action.delay ?? 0 })
        } else if (name === 'dblclick') {
          await page.mouse.dblclick(x, y, { delay: action.delay ?? 0 })
        } else if (name === 'down') {
          await page.mouse.move(x, y)
          await page.mouse.down()
        } else if (name === 'move') {
          await page.mouse.move(x, y)
        } else if (name === 'up') {
          await page.mouse.move(x, y)
          await page.mouse.up()
        } else {
          throw Error(`unsupported pointer action: ${name}`)
        }
        return { ok: true, kind: 'pointer', name, target: node }
      }
      if (action.kind === 'drag') {
        const node = await this.resolveActionTarget(action)
        const points = Array.isArray(action.points) ? action.points : []
        if (points.length < 2) {
          throw Error('drag expects at least two points')
        }
        const first = this.actionPoint(node, action, points[0])
        await page.mouse.move(first.x, first.y)
        await page.mouse.down()
        for (let i = 1; i < points.length; i += 1) {
          const next = this.actionPoint(node, action, points[i])
          await page.mouse.move(next.x, next.y)
        }
        await page.mouse.up()
        return { ok: true, kind: 'drag', target: node }
      }
      throw Error(`unsupported action kind: ${action.kind}`)
    },
    async act(actions) {
      return runWithTimeout('act batch', options.timeoutMs, async () => {
        const out = []
        for (const action of actions) {
          out.push(await this.runAction(action))
        }
        return out
      }, timing, 'act')
    },
    async wait(specs, label = 'wait batch') {
      if (specs.some(spec => spec.kind === 'bridge_ready')) {
        return runWithTimeout(label, options.timeoutMs, async () => {
          await maybeWithTiming(timing, 'wait:phase', `${label} waitForFunction`, async () => {
            await page.waitForFunction(() => {
              const bridge = window.mbt_bridge
              return bridge &&
                bridge.state === 'connected' &&
                bridge.ws &&
                bridge.ws.readyState === 1
            }, { timeout: options.timeoutMs })
          })
        }, timing, 'wait')
      }
      return runWithTimeout(label, options.timeoutMs, async () => {
        let attempts = 0
        let evalMs = 0
        let sleepMs = 0
        for (;;) {
          attempts += 1
          const evalStarted = nowMs()
          const done = await page.evaluate(pageWait, specs)
          evalMs += nowMs() - evalStarted
          if (done) {
            if (timing?.enabled) {
              timingPush(timing, 'wait:phase', `${label} evaluate`, evalMs)
              timingPush(timing, 'wait:phase', `${label} attempts`, attempts)
              timingPush(timing, 'wait:phase', `${label} sleep`, sleepMs)
            }
            return
          }
          const sleepStarted = nowMs()
          await sleep(10)
          sleepMs += nowMs() - sleepStarted
        }
      }, timing, 'wait')
    },
    async step({
      label,
      act = [],
      wait = [],
      read = [],
    }) {
      const stepLabel = label ?? 'step'
      return runWithTimeout(stepLabel, options.timeoutMs, async () => {
        if (act.length > 0) {
          await this.act(act)
        }
        if (wait.length > 0) {
          await this.wait(wait, `${stepLabel} wait`)
        }
        if (read.length > 0) {
          return this.read(read)
        }
        return []
      }, timing, 'step')
    },
    async useFakeBridge() {
      await runWithTimeout('use fake bridge', options.timeoutMs, async () => {
        await page.evaluate(() => {
          const bridge = window.mbt_bridge
          bridge.resetForTest()
          bridge.state = 'connected'
          bridge.ws = {
            readyState: 1,
            send(data) {
              try {
                window.__bridge_sent.push(JSON.parse(data))
              } catch {
                window.__bridge_sent.push(data)
              }
            },
            close() {},
          }
          window.__bridge_sent = []
        })
      }, timing, 'bridge')
    },
    async restoreBridge() {
      await runWithTimeout('restore bridge', options.timeoutMs, async () => {
        await page.evaluate(() => {
          const bridge = window.mbt_bridge
          bridge.resetForTest()
          bridge.should_reconnect = true
          bridge.connect_to_core()
        })
      }, timing, 'bridge')
      await this.wait([{ kind: 'bridge_ready' }], 'restore bridge ready')
    },
    async applyDom(cmds) {
      return runWithTimeout('apply dom batch', options.timeoutMs, async () => {
        return page.evaluate(batch => window.mbt_bridge.apply(batch), cmds)
      }, timing, 'bridge')
    },
    async dumpDebug(extra = {}) {
      const snapshot = await page.evaluate(() => ({
        title: document.title,
        url: location.href,
        body: document.body?.innerHTML?.slice(0, 6000) ?? '',
      })).catch(() => ({ title: '', url: '', body: '' }))
      return {
        consoleLogs: consoleLogs.slice(),
        ...snapshot,
        ...extra,
      }
    },
    async close() {
      const closeBrowser = async () => {
        await withTiming(timing, 'harness', 'close page', async () => page.close().catch(() => {}))
        await withTiming(timing, 'harness', 'close context', async () => context.close().catch(() => {}))
        await withTiming(timing, 'harness', 'close browser', async () => browser.close().catch(() => {}))
      }
      const stopBrowser = options.stop && options.start
        ? withTiming(timing, 'harness', 'stop service', async () => stopService(options))
        : Promise.resolve()
      await Promise.all([
        closeBrowser(),
        stopBrowser,
      ])
      if (options.cleanupStateDir) {
        await withTiming(timing, 'harness', 'cleanup state dir', async () => {
          await removeDirRetry(options.stateDir)
        })
      }
    },
  }
  return harness
}

const runSuite = async (suiteNode, ctx, depth = 0, reporter = console) => {
  const indent = '  '.repeat(depth)
  let passed = 0
  let failed = 0
  for (const hook of suiteNode.hooks.beforeAll) {
    await hook(ctx)
  }
  for (const test of suiteNode.tests) {
    const before = collectHooks(suiteNode, 'beforeEach')
    const after = collectHooks(suiteNode, 'afterEach')
    try {
      for (const hook of before) {
        await hook(ctx)
      }
      await test.fn(ctx)
      passed += 1
    } catch (error) {
      if (suiteNode.name !== 'root') {
        reporter.error(`${indent}[suite] ${suiteNode.name}`)
      }
      reporter.error(`${indent}  [fail] ${test.name}`)
      reporter.error(`${indent}  ${error.stack ?? error.message}`)
      failed += 1
    } finally {
      for (const hook of after) {
        await hook(ctx)
      }
    }
  }
  for (const child of suiteNode.suites) {
    const result = await runSuite(child, ctx, depth + 1, reporter)
    passed += result.passed
    failed += result.failed
  }
  for (const hook of suiteNode.hooks.afterAll) {
    await hook(ctx)
  }
  return { passed, failed }
}

const runFile = async (options, harness, file) => {
  resetSuites()
  const abs = path.resolve(process.cwd(), file)
  await withTiming(options.timingState, file, 'import test file', async () => {
    await import(pathToFileURL(abs).href + `?t=${Date.now()}`)
  })
  return runWithTimeout(`browser test run (${file})`, options.totalTimeoutMs, async () => {
    return runSuite(root, harness)
  }, options.timingState, file)
}

const runCli = async argv => {
  const options = parseArgs(argv)
  options.timingState = createTiming(options.timing)
  options.timingState.accounting = []
  if (options.files.length === 0) {
    options.files = defaultTestFiles()
  }
  if (options.files.length === 0) {
    throw Error('missing browser test file')
  }
  const started = Date.now()
  let passed = 0
  let failed = 0
  let phaseStarted = Date.now()
  const harness = await createHarness(options)
  options.timingState.accounting.push({
    label: 'setup',
    elapsedMs: Date.now() - phaseStarted,
  })
  try {
    for (const file of options.files) {
      phaseStarted = Date.now()
      const result = await withTiming(
        options.timingState,
        file,
        'total file',
        async () => runFile(options, harness, file),
      )
      options.timingState.accounting.push({
        label: file,
        elapsedMs: Date.now() - phaseStarted,
      })
      passed += result.passed
      failed += result.failed
    }
  } finally {
    phaseStarted = Date.now()
    await harness.close()
    options.timingState.accounting.push({
      label: 'teardown',
      elapsedMs: Date.now() - phaseStarted,
    })
  }
  const total = passed + failed
  console.log(`[browser-test] pass=${passed} fail=${failed} total=${total} time=${Date.now() - started}ms`)
  printTiming(options.timingState)
  if (failed > 0) {
    process.exitCode = 1
  }
}

resetSuites()

const isCli = process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))

if (isCli) {
  runCli(process.argv.slice(2)).catch(error => {
    console.error(error.stack ?? error.message)
    process.exit(1)
  })
}

export {
  afterAll,
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
}
