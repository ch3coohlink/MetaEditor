import { spawn } from 'node:child_process'
import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import process from 'node:process'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const withTimeout = (promise, ms, label) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => {
    reject(Error(`${label} timed out after ${ms}ms`))
  }, ms)
  promise.then(
    value => {
      clearTimeout(timer)
      resolve(value)
    },
    error => {
      clearTimeout(timer)
      reject(error)
    },
  )
})

const newSuite = (name, parent = null) => ({
  name,
  parent,
  suites: [],
  tests: [],
  hooks: { beforeAll: [], afterAll: [], beforeEach: [], afterEach: [] },
})

let current
let root

const resetSuites = () => {
  root = current = newSuite('root')
}

resetSuites()

const describe = (name, fn) => {
  const parent = current
  const suite = newSuite(name, parent)
  parent.suites.push(suite)
  current = suite
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

const parseArgs = argv => {
  const options = {
    url: null,
    port: 18180,
    timeoutMs: 8000,
    totalTimeoutMs: 10000,
    metaTimeoutMs: 4000,
    headless: false,
    channel: process.platform === 'win32' ? 'msedge' : undefined,
    start: false,
    stop: false,
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
    } else if (arg === '--headless') {
      options.headless = true
    } else if (arg === '--channel' && i + 1 < argv.length) {
      options.channel = argv[i + 1]
      i += 1
    } else if (arg === '--start') {
      options.start = true
    } else if (arg === '--stop') {
      options.stop = true
    } else {
      options.files.push(arg)
    }
  }
  if (!options.url) {
    options.url = `http://127.0.0.1:${options.port}`
  }
  return options
}

const defaultTestFiles = () => {
  const dir = path.resolve(process.cwd(), 'scripts', 'browser-tests')
  if (!fs.existsSync(dir)) {
    return []
  }
  return [
    'scripts/browser-tests/demo-editor.test.js',
    'scripts/browser-tests/host.test.js',
    'scripts/browser-tests/bridge.test.js',
  ]
}

const parseStartedPort = text => {
  const match = text.match(/http:\/\/localhost:(\d+)/)
  return match ? Number(match[1]) : null
}

const quoteShellArg = arg => {
  const text = String(arg)
  const needQuote = text === '' || /[\s"\\]/.test(text)
  if (!needQuote) {
    return text
  }
  return `"${text.replace(/["\\]/g, '\\$&')}"`
}

const serviceBin = () => path.resolve(
  process.cwd(),
  process.platform === 'win32'
    ? '_build/native/debug/build/service/service.exe'
    : '_build/native/debug/build/service/service',
)

const latestMtime = target => {
  if (!fs.existsSync(target)) {
    return 0
  }
  const stat = fs.statSync(target)
  if (!stat.isDirectory()) {
    return stat.mtimeMs
  }
  let latest = stat.mtimeMs
  for (const name of fs.readdirSync(target)) {
    latest = Math.max(latest, latestMtime(path.join(target, name)))
  }
  return latest
}

const serviceBinStale = bin => {
  if (!fs.existsSync(bin)) {
    return true
  }
  const builtAt = fs.statSync(bin).mtimeMs
  const sourceAt = Math.max(
    latestMtime(path.resolve(process.cwd(), 'service')),
    latestMtime(path.resolve(process.cwd(), 'src')),
    latestMtime(path.resolve(process.cwd(), 'moon.mod.json')),
  )
  return sourceAt > builtAt
}

const ensureServiceBin = async () => {
  const bin = serviceBin()
  if (!serviceBinStale(bin)) {
    return bin
  }
  await new Promise((resolve, reject) => {
    const child = spawn(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        '.\\scripts\\build-native.ps1',
        '-Package',
        'service',
      ],
      {
        cwd: process.cwd(),
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      },
    )
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', chunk => {
      stdout += chunk.toString()
    })
    child.stderr.on('data', chunk => {
      stderr += chunk.toString()
    })
    child.on('error', reject)
    child.on('exit', code => {
      if (code === 0) {
        resolve()
        return
      }
      reject(Error(`build-native failed (${code})\n${stdout}\n${stderr}`))
    })
  })
  if (!fs.existsSync(bin)) {
    throw Error(`service binary is missing: ${bin}`)
  }
  return bin
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

const startService = async options => {
  const bin = await ensureServiceBin()
  const port = options.portLocked ? options.port : await pickPort()
  options.port = port
  options.url = `http://127.0.0.1:${port}`
  const child = spawn(
    bin,
    ['--internal_boot_as_service', '--state-dir', options.stateDir, '--port', `${port}`],
    {
      cwd: process.cwd(),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    },
  )
  let stdout = ''
  let stderr = ''
  child.stdout.on('data', chunk => {
    stdout += chunk.toString()
  })
  child.stderr.on('data', chunk => {
    stderr += chunk.toString()
  })
  child.on('error', error => {
    stderr += `\n${error.message}`
  })
  await waitForServer(options.url, options.timeoutMs, child, () => `${stdout}\n${stderr}`)
  return { child, stdout: () => stdout, stderr: () => stderr }
}

const waitForExit = (child, timeoutMs, label) => new Promise((resolve, reject) => {
  if (!child || child.exitCode != null) {
    resolve()
    return
  }
  const timer = setTimeout(() => {
    reject(Error(`${label} timed out after ${timeoutMs}ms`))
  }, timeoutMs)
  child.once('exit', () => {
    clearTimeout(timer)
    resolve()
  })
})

const runMeta = (options, args) => {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        '.\\meta.ps1',
        '--state-dir',
        options.stateDir,
        ...args,
      ],
      {
        cwd: process.cwd(),
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      },
    )
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', chunk => {
      stdout += chunk.toString()
    })
    child.stderr.on('data', chunk => {
      stderr += chunk.toString()
    })
    child.on('error', reject)
    const timer = setTimeout(() => {
      child.kill()
      reject(Error(`meta ${args.join(' ')} timed out after ${options.metaTimeoutMs}ms`))
    }, options.metaTimeoutMs)
    child.on('exit', code => {
      clearTimeout(timer)
      if (code === 0) {
        resolve({ stdout, stderr })
        return
      }
      reject(Error(`meta ${args.join(' ')} failed (${code})\n${stdout}\n${stderr}`))
    })
  })
}

const waitForServer = async (url, timeoutMs, child = null, details = () => '') => {
  const started = Date.now()
  let lastError = ''
  while (Date.now() - started < timeoutMs) {
    if (child && child.exitCode != null) {
      throw Error(`service exited before ready (${child.exitCode})\n${details()}`)
    }
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(1000) })
      if (response.ok) {
        await response.text()
        return
      }
      lastError = `http ${response.status}`
    } catch (error) {
      lastError = String(error)
    }
    await sleep(10)
  }
  throw Error(`server did not become ready: ${lastError}`)
}

const createHarness = async options => {
  let playwright
  try {
    playwright = await import('playwright')
  } catch {
    throw Error('playwright is not installed, run `npm install` first')
  }
  let service = null
  if (options.start) {
    service = await startService(options)
  }
  const browser = await playwright.chromium.launch({
    headless: options.headless,
    channel: options.channel,
  })
  const context = await browser.newContext()
  const page = await context.newPage()
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
    currentRootIds: [],
    opened: false,
    async open() {
      if (this.opened) {
        return
      }
      await this.goto()
      await this.waitForBridgeReady()
      this.opened = true
    },
    async goto() {
      await this.page.goto(options.url, {
        waitUntil: 'domcontentloaded',
        timeout: options.timeoutMs,
      })
    },
    async command(cmd, arg = '') {
      const response = await fetch(`${options.url}/_meta/command`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ cmd, arg }),
      })
      const payload = await response.json()
      if (!response.ok) {
        throw Error(payload.error ?? `command ${cmd} failed (${response.status})`)
      }
      if (!payload.ok) {
        throw Error(payload.error ?? `command ${cmd} failed`)
      }
      return payload.result ?? ''
    },
    async roots(...entryIds) {
      const quoted = entryIds.map(id => JSON.stringify(id)).join(' ')
      return this.command('roots', quoted)
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
    currentRootId() {
      if (this.currentRootIds.length !== 1) {
        throw Error(`expected one root, got ${this.currentRootIds.join(', ')}`)
      }
      return this.currentRootIds[0]
    },
    async syncBrowser() {
      return this.command('sync')
    },
    async setRoots(entryIds, readyUiId = undefined) {
      const ids = Array.isArray(entryIds) ? entryIds : [entryIds]
      const text = await this.roots(...ids)
      this.parseRoots(text)
      if (this.opened) {
        await this.syncBrowser()
      }
      if (readyUiId) {
        await this.waitForUI(readyUiId)
      }
      return this.currentRootIds
    },
    async execRoot(action, args = [], ready = undefined) {
      const root = this.currentRootId()
      const argv = [root, action, ...args.map(quoteShellArg)]
      const result = await this.command('exec', argv.join(' '))
      if (this.opened) {
        await this.syncBrowser()
      }
      if (ready) {
        if (typeof ready === 'string') {
          await this.waitForUI(ready)
        } else {
          await this.waitForCondition(ready.name, ready.fn, ready.arg)
        }
      }
      return result
    },
    async waitForBridgeReady() {
      await this.page.waitForFunction(() => {
        const bridge = window.mbt_bridge
        return bridge &&
          bridge.state === 'connected' &&
          bridge.ws &&
          bridge.ws.readyState === 1
      }, { timeout: options.timeoutMs })
    },
    async useFakeBridge() {
      await this.page.evaluate(() => {
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
    },
    async restoreBridge() {
      await this.page.evaluate(() => {
        const bridge = window.mbt_bridge
        bridge.resetForTest()
        bridge.should_reconnect = true
        bridge.connect_to_core()
      })
      await this.waitForBridgeReady()
    },
    async waitForUI(uiId, state = 'visible') {
      await this.page.locator(`[ui-id="${uiId}"]`).waitFor({
        state,
        timeout: options.timeoutMs,
      })
    },
    async clickUI(uiId) {
      await this.page.click(`[ui-id="${uiId}"]`, { timeout: options.timeoutMs })
    },
    async dblclickUI(uiId) {
      await this.page.dblclick(`[ui-id="${uiId}"]`, {
        delay: 40,
        timeout: options.timeoutMs,
      })
    },
    async textOfUI(uiId) {
      return this.page.locator(`[ui-id="${uiId}"]`).innerText()
    },
    async countUI(uiId) {
      return this.page.locator(`[ui-id="${uiId}"]`).count()
    },
    async waitForCondition(name, fn, arg = undefined) {
      if (arg === undefined) {
        await this.page.waitForFunction(fn, { timeout: options.timeoutMs })
        return
      }
      await this.page.waitForFunction(fn, arg, { timeout: options.timeoutMs })
      return name
    },
    async dumpDebug(extra = {}) {
      let bodyHtml = ''
      try {
        bodyHtml = await this.page.locator('body').innerHTML()
      } catch {
        bodyHtml = ''
      }
      return {
        url: this.page?.url?.() ?? '',
        consoleLogs: this.consoleLogs,
        bodyHtml: bodyHtml.slice(0, 6000),
        ...extra,
      }
    },
    async close() {
      await this.page.close().catch(() => {})
      await context.close()
      await browser.close()
      if (options.stop && service) {
        await this.command('stop').catch(() => {})
        await waitForExit(service.child, options.metaTimeoutMs, 'service stop').catch(() => {})
      }
      if (options.cleanupStateDir) {
        fs.rmSync(options.stateDir, { recursive: true, force: true })
      }
    },
  }
  return harness
}

const collectHooks = (suite, key) => {
  if (!suite) {
    return []
  }
  return [...collectHooks(suite.parent, key), ...suite.hooks[key]]
}

const runSuite = async (suite, ctx, depth = 0, reporter = console) => {
  const indent = '  '.repeat(depth)
  let passed = 0
  let failed = 0
  for (const hook of suite.hooks.beforeAll) {
    await hook(ctx)
  }
  for (const test of suite.tests) {
    const before = collectHooks(suite, 'beforeEach')
    const after = collectHooks(suite, 'afterEach')
    try {
      for (const hook of before) {
        await hook(ctx)
      }
      await test.fn(ctx)
      passed += 1
    } catch (error) {
      if (suite.name !== 'root') {
        reporter.error(`${indent}[suite] ${suite.name}`)
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
  for (const child of suite.suites) {
    const result = await runSuite(child, ctx, depth + 1, reporter)
    passed += result.passed
    failed += result.failed
  }
  for (const hook of suite.hooks.afterAll) {
    await hook(ctx)
  }
  return { passed, failed }
}

const runCli = async argv => {
  const options = parseArgs(argv)
  if (options.files.length === 0) {
    options.files = defaultTestFiles()
  }
  if (options.files.length === 0) {
    throw Error('missing browser test file')
  }
  const started = Date.now()
  let passed = 0
  let failed = 0
  const harness = await createHarness(options)
  try {
    for (const file of options.files) {
      resetSuites()
      const abs = path.resolve(process.cwd(), file)
      await import(pathToFileURL(abs).href)
      const result = await withTimeout(
        runSuite(root, harness),
        options.totalTimeoutMs,
        `browser test run (${file})`,
      )
      passed += result.passed
      failed += result.failed
    }
  } finally {
    await harness.close()
  }
  const total = passed + failed
  console.log(`[browser-test] pass=${passed} fail=${failed} total=${total} time=${Date.now() - started}ms`)
  if (failed > 0) {
    process.exitCode = 1
  }
}

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
  createHarness,
  describe,
  expect,
  it,
  runCli,
}
