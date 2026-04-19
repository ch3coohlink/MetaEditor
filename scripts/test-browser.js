import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { exec, sleep } from './common.js'

const processStartedAt = performance.now()
let mainFinishedAt = null
let chromium = null
const getChromium = async () => {
  if (chromium) {
    return chromium
  }
  const mod = await import('playwright')
  chromium = mod.chromium
  return chromium
}

const parseArgs = argv => {
  const options = {
    targetDir: '_build_browser',
    timeoutMs: 2500,
    readyTimeoutMs: 800,
    port: null,
    start: false,
    stop: false,
    timing: false,
    verboseTiming: false,
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--target-dir' && i + 1 < argv.length) {
      options.targetDir = argv[i + 1]
      i += 1
    } else if (arg === '--timeout' && i + 1 < argv.length) {
      options.timeoutMs = Number(argv[i + 1]) || options.timeoutMs
      i += 1
    } else if (arg === '--ready-timeout' && i + 1 < argv.length) {
      options.readyTimeoutMs = Number(argv[i + 1]) || options.readyTimeoutMs
      i += 1
    } else if (arg === '--port' && i + 1 < argv.length) {
      options.port = Number(argv[i + 1]) || options.port
      i += 1
    } else if (arg === '--start') {
      options.start = true
    } else if (arg === '--stop') {
      options.stop = true
    } else if (arg === '--timing') {
      options.timing = true
    } else if (arg === '--verbose-timing') {
      options.verboseTiming = true
    }
  }
  return options
}

const nowMs = () => performance.now()
const queryNode = value => Array.isArray(value) && value[0] === 'Node' ? value[1] ?? null : null
const queryText = value => Array.isArray(value) && value[0] === 'Text' ?
  (typeof value[1] === 'string' ? value[1] : '') : ''
const logVerboseTiming = (options, label, started, detail = '') => {
  if (!options.verboseTiming) {
    return
  }
  const suffix = detail ? ` ${detail}` : ''
  console.log(
    `[browser] ${label}: +${Math.round(nowMs() - started)}ms @${Math.round(nowMs() - processStartedAt)}ms${suffix}`,
  )
}
const installBridgeAdapter = async page => {
  await page.evaluate(() => {
    const encodeQuery = (kind, value) => {
      if (!kind || kind === 'node') { return 'Node' }
      if (kind === 'text') { return 'Text' }
      if (kind === 'attr') { return ['Attr', value ?? ''] }
      if (kind === 'prop') { return ['Prop', value ?? ''] }
      if (kind === 'style') { return ['Style', value ?? ''] }
      return kind
    }
    const encodeEvent = (kind, value) => {
      if (typeof kind !== 'string') {
        return kind
      }
      if (kind === 'click') {
        return {
          kind: 'Click',
          data: ['Pointer', {
            mod: { ctrl: false, shift: false, alt: false, meta: false },
            x: 0, y: 0, vx: 0, vy: 0, button: 0, buttons: 0, pointer_id: 0,
          }],
        }
      }
      return value ?? kind
    }
    if (globalThis.__mbt_test_bridge_installed) {
      return
    }
    const bridge = globalThis.mbt_bridge
    globalThis.mbt_bridge = {
      status: () => bridge.status(),
      init: () => bridge.init(),
      query: (path, kind = 'node', value) => bridge.query(path, encodeQuery(kind, value)),
      dispatch: (path, kind, value) => bridge.dispatch(path, encodeEvent(kind, value)),
      cli: (cmd, arg = '') => bridge.cli(cmd, arg),
      reset: (root = '') => bridge.reset(root),
    }
    globalThis.__mbt_test_bridge_installed = true
  })
}

const withTiming = async (options, label, run) => {
  const started = nowMs()
  try {
    return await run()
  } finally {
    logVerboseTiming(options, label, started)
  }
}
const withTimeout = async (timeoutMs, label, run) => {
  let timer = null
  try {
    return await Promise.race([
      Promise.resolve().then(run),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs)
      }),
    ])
  } finally {
    if (timer) {
      clearTimeout(timer)
    }
  }
}

const pickPort = () => new Promise((resolve, reject) => {
  const server = net.createServer()
  server.unref()
  server.on('error', reject)
  server.listen(0, '127.0.0.1', () => {
    const address = server.address()
    if (!address || typeof address === 'string') {
      server.close(() => reject(Error('failed to allocate browser port')))
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

const serviceBin = targetDir => path.resolve(
  process.cwd(),
  process.platform === 'win32'
    ? `${targetDir}/native/debug/build/service/service.exe`
    : `${targetDir}/native/debug/build/service/service`,
)
const browserRoot = targetDir => path.resolve(
  process.cwd(),
  targetDir,
  'js',
  'debug',
  'build',
  'browser',
)

const findBrowserExecutable = () => {
  const candidates = process.platform === 'win32' ? [
    process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
    `${process.env.ProgramFiles}\\Google\\Chrome\\Application\\chrome.exe`,
    `${process.env['ProgramFiles(x86)']}\\Google\\Chrome\\Application\\chrome.exe`,
    `${process.env.LocalAppData}\\Google\\Chrome\\Application\\chrome.exe`,
    `${process.env.ProgramFiles}\\Microsoft\\Edge\\Application\\msedge.exe`,
    `${process.env['ProgramFiles(x86)']}\\Microsoft\\Edge\\Application\\msedge.exe`,
    `${process.env.LocalAppData}\\Microsoft\\Edge\\Application\\msedge.exe`,
  ] : [
    process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
  ]
  for (const file of candidates) {
    if (file && fs.existsSync(file)) {
      return file
    }
  }
  return null
}

const waitForHttp = async (port, timeoutMs) => {
  const started = nowMs()
  for (;;) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/`)
      if (response.ok) {
        return
      }
    } catch {}
    if (nowMs() - started > timeoutMs) {
      throw Error(`timed out waiting for browser service after ${timeoutMs}ms`)
    }
    await sleep(20)
  }
}

const loadTests = async () => {
  const dir = path.resolve(process.cwd(), 'e2e')
  const files = fs.readdirSync(dir)
    .filter(name => name.endsWith('.js'))
    .sort()
  for (const file of files) {
    await import(pathToFileURL(path.join(dir, file)).href)
  }
}

const suites = []
let currentSuite = null

const pushItem = item => {
  if (!currentSuite) {
    throw Error('test helpers must be called inside describe()')
  }
  currentSuite.items.push(item)
}

const describe = (name, fn) => {
  const suite = { name, beforeAll: [], items: [] }
  if (currentSuite) {
    currentSuite.items.push({ type: 'suite', suite })
  } else {
    suites.push(suite)
  }
  const prev = currentSuite
  currentSuite = suite
  try {
    fn()
  } finally {
    currentSuite = prev
  }
}

const beforeAll = fn => {
  if (!currentSuite) {
    throw Error('beforeAll() must be called inside describe()')
  }
  currentSuite.beforeAll.push(fn)
}

const it = (name, fn) => {
  pushItem({ type: 'test', name, fn })
}

const expect = actual => ({
  toBe: expected => {
    if (!Object.is(actual, expected)) {
      throw Error(`expected ${JSON.stringify(actual)} to be ${JSON.stringify(expected)}`)
    }
  },
  toBeTruthy: () => {
    if (!actual) {
      throw Error(`expected ${JSON.stringify(actual)} to be truthy`)
    }
  },
  toEqual: expected => {
    const a = JSON.stringify(actual)
    const b = JSON.stringify(expected)
    if (a !== b) {
      throw Error(`expected ${a} to equal ${b}`)
    }
  },
})

const runHooks = async (hooks, ctx, trail) => {
  for (let i = 0; i < hooks.length; i += 1) {
    await withTimeout(
      ctx.options.timeoutMs,
      `${trail.join(' > ')} > beforeAll #${i + 1}`,
      () => hooks[i](ctx),
    )
  }
}

const runItem = async (item, ctx, trail, report) => {
  if (item.type === 'suite') {
    await runSuite(item.suite, ctx, trail.concat(item.suite.name), report)
    return
  }
  const name = trail.concat(item.name).join(' > ')
  const started = nowMs()
  try {
    await withTimeout(ctx.options.timeoutMs, name, () => item.fn(ctx))
    if (ctx.options.verboseTiming) {
      console.log(`[browser] test ${name}: +${Math.round(nowMs() - started)}ms @${Math.round(nowMs() - processStartedAt)}ms`)
    }
    report.pass(name)
  } catch (error) {
    if (ctx.options.verboseTiming) {
      console.log(`[browser] test ${name}: +${Math.round(nowMs() - started)}ms @${Math.round(nowMs() - processStartedAt)}ms`)
    }
    report.fail(name, error)
  }
}

const runSuite = async (suite, ctx, trail, report) => {
  await runHooks(suite.beforeAll, ctx, trail)
  for (const item of suite.items) {
    await runItem(item, ctx, trail, report)
  }
}

class BrowserHarness {
  constructor(options) {
    this.options = options
    this.browser = null
    this.context = null
    this.page = null
    this.rawPage = null
    this.service = null
    this.stateDir = null
    this.port = null
    this.opened = false
  }

  wrapMouse(mouse, name) {
    return new Proxy(mouse, {
      get: (target, prop) => {
        const value = target[prop]
        if (typeof value !== 'function') {
          return value
        }
        if (!['click', 'move', 'down', 'up'].includes(prop)) {
          return value.bind(target)
        }
        return async (...args) => withTiming(
          this.options,
          `${name}.mouse.${prop}`,
          () => value.apply(target, args),
        )
      },
    })
  }

  wrapPage(page, name) {
    const mouse = this.wrapMouse(page.mouse, name)
    return new Proxy(page, {
      get: (target, prop) => {
        if (prop === 'mouse') {
          return mouse
        }
        const value = target[prop]
        if (typeof value !== 'function') {
          return value
        }
        if (!['evaluate', 'waitForFunction', 'goto', 'close'].includes(prop)) {
          return value.bind(target)
        }
        return async (...args) => withTiming(
          this.options,
          `${name}.${prop}`,
          () => value.apply(target, args),
        )
      },
    })
  }

  async init() {
    const executablePath = findBrowserExecutable()
    const started = nowMs()
    try {
      const browserType = await getChromium()
      this.browser = await browserType.launch({
        headless: true,
        executablePath: executablePath ?? undefined,
      })
    } catch (error) {
      if (!executablePath) {
        throw Error('No local Chrome/Edge or Playwright browser was found. Please run `npx playwright install chromium`.')
      }
      throw error
    }
    this.context = await this.browser.newContext()
    this.rawPage = await withTiming(this.options, 'browser page init', () => this.context.newPage())
    this.rawPage.setDefaultTimeout(this.options.timeoutMs)
    this.page = this.wrapPage(this.rawPage, 'page')
    logVerboseTiming(this.options, 'browser init', started)
  }

  async startService() {
    if (this.service) {
      return
    }
    await withTiming(this.options, 'service start', async () => {
      const bin = serviceBin(this.options.targetDir)
      const root = browserRoot(this.options.targetDir)
      if (!fs.existsSync(bin)) {
        throw Error(`service binary is missing: ${bin}`)
      }
      this.stateDir = fs.mkdtempSync(path.join(os.tmpdir(), 'metaeditor-browser-'))
      this.port = this.options.port ?? await withTiming(this.options, 'service pick port', pickPort)
      this.service = exec.start(bin, [
        '--internal_boot_as_service',
        '--state-dir', this.stateDir,
        '--port', String(this.port),
      ], { cwd: root })
      await withTiming(
        this.options,
        'service wait ready',
        () => waitForHttp(this.port, this.options.readyTimeoutMs),
      )
    })
  }

  async open() {
    if (this.opened) {
      return this.page
    }
    const started = nowMs()
    if (this.options.start) {
      await this.startService()
    }
    if (!this.port) {
      throw Error('browser service is not started')
    }
    await withTiming(
      this.options,
      'open goto',
      () => this.rawPage.goto(`http://127.0.0.1:${this.port}/`, { waitUntil: 'domcontentloaded' }),
    )
    await withTiming(this.options, 'open install bridge', () => installBridgeAdapter(this.rawPage))
    await withTiming(this.options, 'open wait connected', () => this.rawPage.waitForFunction(
      () => globalThis.mbt_bridge?.status?.().state === 'connected',
      null,
      { timeout: this.options.timeoutMs },
    ))
    this.opened = true
    logVerboseTiming(this.options, 'browser load', started)
    return this.page
  }

  async openPage() {
    await this.open()
    const started = nowMs()
    const rawPage = await withTiming(this.options, 'openPage newPage', () => this.context.newPage())
    rawPage.setDefaultTimeout(this.options.timeoutMs)
    await withTiming(
      this.options,
      'openPage goto',
      () => rawPage.goto(`http://127.0.0.1:${this.port}/`, { waitUntil: 'domcontentloaded' }),
    )
    await withTiming(this.options, 'openPage install bridge', () => installBridgeAdapter(rawPage))
    await withTiming(this.options, 'openPage wait connected', () => rawPage.waitForFunction(
      () => globalThis.mbt_bridge?.status?.().state === 'connected',
      null,
      { timeout: this.options.timeoutMs },
    ))
    logVerboseTiming(this.options, 'openPage', started)
    return this.wrapPage(rawPage, `page#${this.context.pages().length}`)
  }

  async bridgeCall(name, args) {
    return withTiming(this.options, `bridge ${name}`, () => this.rawPage.evaluate(
      payload => globalThis.mbt_bridge[payload.name](...payload.args),
      { name, args },
    ))
  }

  async query(items) {
    return withTiming(this.options, `query x${items.length}`, () => this.rawPage.evaluate(
      payload => Promise.all(payload.items.map(item =>
        globalThis.mbt_bridge.query(item.path, item.kind ?? 'node', item.value),
      )),
      { items },
    ))
  }

  async pointOf(path) {
    const started = nowMs()
    const value = await withTiming(this.options, `pointOf query ${path}`, () => this.rawPage.evaluate(
      targetPath => globalThis.mbt_bridge.query(targetPath, 'node'),
      path,
    ))
    const point = await withTiming(this.options, `pointOf lookup ${path}`, () => this.rawPage.evaluate(
      id => globalThis.__mbt_bridge_internal?.pointOf?.(id) ?? null,
      queryNode(value)?.id ?? 0,
    ))
    if (!point) {
      throw Error(`click target not found: ${path}`)
    }
    logVerboseTiming(this.options, `pointOf ${path}`, started)
    return point
  }

  async dispatch(item) {
    if (item.kind === 'click') {
      const point = await this.pointOf(item.path)
      await withTiming(
        this.options,
        `dispatch click ${item.path}`,
        () => this.rawPage.mouse.click(point.x, point.y),
      )
      return
    }
    return withTiming(this.options, `dispatch ${item.kind} ${item.path}`, () => this.rawPage.evaluate(
      payload => globalThis.mbt_bridge.dispatch(payload.path, payload.kind, payload.value),
      item,
    ))
  }

  async wait(items, label = 'wait') {
    const started = nowMs()
    let rounds = 0
    for (;;) {
      rounds += 1
      const values = await withTiming(this.options, `${label} poll#${rounds}`, () => this.rawPage.evaluate(
        payload => Promise.all(payload.items.map(async item => {
          try {
            return await globalThis.mbt_bridge.query(item.path, item.kind ?? 'node', item.value)
          } catch {
            return null
          }
        })),
        { items: items.map(item => ({
          path: item.path,
          kind: item.kind === 'text_eq' ? 'text' : 'node',
        })) },
      ))
      let ok = true
      for (let i = 0; i < items.length; i += 1) {
        const item = items[i]
        const value = values[i]
        if (item.kind === 'exists') {
          if (!value) {
            ok = false
          }
        } else if (item.kind === 'text_eq') {
          if (queryText(value) !== item.value) {
            ok = false
          }
        } else {
          throw Error(`unsupported wait kind: ${item.kind}`)
        }
      }
      if (ok) {
        logVerboseTiming(this.options, label, started, `(rounds=${rounds})`)
        return
      }
      if (nowMs() - started > this.options.timeoutMs) {
        throw Error(`${label} timed out after ${this.options.timeoutMs}ms`)
      }
      await sleep(20)
    }
  }

  async close() {
    const started = nowMs()
    if (this.options.stop && this.opened) {
      await this.page.evaluate(() => globalThis.mbt_bridge?.cli?.('stop').catch(() => '')).catch(() => {})
    }
    if (this.page) {
      await this.page.close().catch(() => {})
    }
    if (this.context) {
      await this.context.close().catch(() => {})
    }
    if (this.browser) {
      await this.browser.close().catch(() => {})
    }
    if (this.options.stop && this.service?.child?.exitCode == null) {
      try {
        this.service.child.kill('SIGKILL')
      } catch {}
    }
    if (this.service) {
      await this.service.done.catch(() => {})
      if (this.service.child?.exitCode == null) {
        try {
          this.service.child.kill('SIGKILL')
        } catch {}
      }
    }
    if (this.stateDir) {
      fs.rmSync(this.stateDir, { recursive: true, force: true })
    }
    if (this.options.verboseTiming) {
      console.log(`[browser] browser close: +${Math.round(nowMs() - started)}ms @${Math.round(nowMs() - processStartedAt)}ms`)
    }
  }
}

const main = async () => {
  const options = parseArgs(process.argv.slice(2))
  if (options.verboseTiming) {
    console.log(`[browser] process boot: @${Math.round(nowMs() - processStartedAt)}ms`)
  }
  const harness = new BrowserHarness(options)
  await harness.init()

  const report = {
    passed: 0,
    failed: 0,
    pass(name) {
      this.passed += 1
    },
    fail(name, error) {
      this.failed += 1
      console.log(`[browser] not ok ${name}`)
      console.log(error?.stack ?? error?.message ?? String(error))
    },
  }

  const ctx = {
    page: harness.page,
    options,
    open: () => harness.open(),
    openPage: () => harness.openPage(),
    query: items => harness.query(items),
    dispatch: item => harness.dispatch(item),
    wait: (items, label) => harness.wait(items, label),
    bridge: (...args) => harness.bridgeCall(...args),
    pointOf: path => harness.pointOf(path),
  }

  globalThis.describe = describe
  globalThis.beforeAll = beforeAll
  globalThis.it = it
  globalThis.expect = expect

  try {
    const loadStarted = nowMs()
    await loadTests()
    if (options.verboseTiming) {
      console.log(`[browser] test load: +${Math.round(nowMs() - loadStarted)}ms @${Math.round(nowMs() - processStartedAt)}ms`)
    }
    for (const suite of suites) {
      const started = nowMs()
      await runSuite(suite, ctx, [suite.name], report)
      if (options.verboseTiming) {
        console.log(`[browser] suite ${suite.name}: +${Math.round(nowMs() - started)}ms @${Math.round(nowMs() - processStartedAt)}ms`)
      }
    }
  } finally {
    await harness.close().catch(() => {})
  }

  const total = report.passed + report.failed
  mainFinishedAt = performance.now()
  console.log(`[browser] total ${total}, passed: ${report.passed}, failed: ${report.failed}`)
  if (options.timing) {
    console.log(`[browser] process total: @${Math.round(nowMs() - processStartedAt)}ms`)
  }
  if (report.failed > 0) {
    process.exit(1)
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.on('beforeExit', () => {
    if (mainFinishedAt != null && process.argv.includes('--verbose-timing')) {
      console.log(`[browser] beforeExit gap: +${Math.round(performance.now() - mainFinishedAt)}ms @${Math.round(performance.now() - processStartedAt)}ms`)
    }
  })
  main().catch(error => {
    console.error(error?.stack ?? error?.message ?? String(error))
    process.exit(1)
  })
}

export { beforeAll, describe, expect, it }
