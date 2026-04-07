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

const cleanupStateDir = async options => {
  if (!options.cleanupStateDir) {
    return
  }
  await removeDirRetry(options.stateDir)
}

const cleanupHarnessCreateFailure = async (
  _timing,
  options,
  { page = null, context = null, browser = null, stopServiceAfter = false } = {},
) => {
  await Promise.all([
    page ? page.close().catch(() => {}) : Promise.resolve(),
    context ? context.close().catch(() => {}) : Promise.resolve(),
    browser ? browser.close().catch(() => {}) : Promise.resolve(),
    stopServiceAfter ? stopService(options) : Promise.resolve(),
  ])
  await cleanupStateDir(options)
}

const createStartedBrowser = async (timing, options, launchBrowser) => {
  if (!options.start) {
    return { browser: await launchBrowser(), stopServiceAfter: false }
  }
  let serviceStarted = false
  const startServiceTask = withTiming(timing, 'harness', 'start service', async () => {
    await startService(options)
    serviceStarted = true
  })
  try {
    const [browser] = await Promise.all([
      launchBrowser(),
      startServiceTask,
    ])
    return { browser, stopServiceAfter: true }
  } catch (error) {
    await startServiceTask.catch(() => {})
    throw { error, stopServiceAfter: serviceStarted }
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
  const kind = spec?.kind ?? 'node'
  if (typeof spec === 'string') {
    return bridge.query(spec, 'node')
  }
  if (spec?.path != null) {
    return bridge.query(spec.path, kind)
  }
  if (spec?.id != null && kind === 'node') {
    return bridge.bridgeTest.snapshot(spec.id)
  }
  if (spec?.id != null && kind === 'text') {
    const node = bridge.bridgeTest.snapshot(spec.id)
    return node ? { id: node.id, text: node.text ?? '' } : null
  }
  throw Error(`unsupported query spec: ${JSON.stringify(spec)}`)
}

const pageQueryBatch = async specs => {
  const bridge = window.mbt_bridge
  const out = []
  for (const spec of specs) {
    const kind = spec?.kind ?? 'node'
    if (typeof spec === 'string') {
      out.push(await bridge.query(spec, 'node'))
      continue
    }
    if (spec?.path != null) {
      out.push(await bridge.query(spec.path, kind))
      continue
    }
    if (spec?.id != null && kind === 'node') {
      out.push(bridge.bridgeTest.snapshot(spec.id))
      continue
    }
    if (spec?.id != null && kind === 'text') {
      const node = bridge.bridgeTest.snapshot(spec.id)
      out.push(node ? { id: node.id, text: node.text ?? '' } : null)
      continue
    }
    throw Error(`unsupported query spec: ${JSON.stringify(spec)}`)
  }
  return out
}

const pageTrigger = async specs => {
  const bridge = window.mbt_bridge
  const out = []
  for (const spec of specs) {
    if (spec?.path != null) {
      out.push(await bridge.trigger(spec.path, spec.kind, spec.value))
      continue
    }
    if (spec?.id != null) {
      out.push(bridge.bridgeTest.triggerById({
        id: spec.id,
        kind: spec.kind,
        text: typeof spec.value === 'string' ? spec.value : undefined,
        key: spec.value?.key,
        key_event: spec.value?.event,
        code: spec.value?.code,
        ctrl_key: !!spec.value?.ctrlKey,
        shift_key: !!spec.value?.shiftKey,
        alt_key: !!spec.value?.altKey,
        meta_key: !!spec.value?.metaKey,
        target_id: spec.kind === 'drag_to' ? spec.value?.id : undefined,
      }))
      continue
    }
    throw Error(`unsupported trigger spec: ${JSON.stringify(spec)}`)
  }
  return out
}

const pageWait = async specs => {
  const bridge = window.mbt_bridge
  const tryQuery = async path => {
    try {
      return await bridge.query(path, 'node')
    } catch {
      return null
    }
  }
  const readText = async path => {
    try {
      return (await bridge.query(path, 'text'))?.text ?? null
    } catch {
      return null
    }
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
      const target = await tryQuery(spec.path)
      if (!target?.focused) {
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
  let browser
  let context
  let page
  try {
    ;({ browser } = await createStartedBrowser(timing, options, launchBrowser))
    context = await withTiming(timing, 'harness', 'new context', async () => browser.newContext())
    page = await withTiming(timing, 'harness', 'new page', async () => context.newPage())
  } catch (error) {
    const stopServiceAfter = error?.stopServiceAfter ?? !!browser
    await cleanupHarnessCreateFailure(timing, options, {
      page,
      context,
      browser,
      stopServiceAfter,
    })
    throw error?.error ?? error
  }
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
        if (Array.isArray(pathOrSpec)) {
          return page.evaluate(pageQueryBatch, pathOrSpec)
        }
        return page.evaluate(pageQuery, pathOrSpec)
      }, timing, 'query')
    },
    async trigger(specs) {
      const actions = Array.isArray(specs) ? specs : [specs]
      return runWithTimeout('trigger batch', options.timeoutMs, async () => {
        return page.evaluate(pageTrigger, actions)
      }, timing, 'trigger')
    },
    async wait(specs, label = 'wait batch') {
      if (specs.some(spec => spec.kind === 'bridge_ready')) {
        return runWithTimeout(label, options.timeoutMs, async () => {
          await maybeWithTiming(timing, 'wait:phase', `${label} waitForFunction`, async () => {
            await page.waitForFunction(() => {
              const bridge = window.mbt_bridge
              return bridge?.status().state === 'connected'
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
    async useFakeBridge() {
      await runWithTimeout('use fake bridge', options.timeoutMs, async () => {
        await page.evaluate(() => {
          const bridge = window.mbt_bridge
          window.__bridge_sent = []
          bridge.bridgeTest.connectFake(data => {
            window.__bridge_sent.push(data)
          })
        })
      }, timing, 'bridge')
    },
    async restoreBridge() {
      await runWithTimeout('restore bridge', options.timeoutMs, async () => {
        await page.evaluate(() => {
          const bridge = window.mbt_bridge
          bridge.reset()
          bridge.init()
        })
      }, timing, 'bridge')
      await this.wait([{ kind: 'bridge_ready' }], 'restore bridge ready')
    },
    async applyDom(cmds) {
      return runWithTimeout('apply dom batch', options.timeoutMs, async () => {
        return page.evaluate(batch => window.mbt_bridge.bridgeTest.apply(batch), cmds)
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
          await cleanupStateDir(options)
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
