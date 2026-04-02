import { spawn } from 'node:child_process'
import fs from 'node:fs'
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
  return fs.readdirSync(dir)
    .filter(name => name.endsWith('.test.js'))
    .sort()
    .map(name => path.join('scripts', 'browser-tests', name))
}

const parseStartedPort = text => {
  const match = text.match(/http:\/\/localhost:(\d+)/)
  return match ? Number(match[1]) : null
}

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

const waitForServer = async (url, timeoutMs) => {
  const started = Date.now()
  let lastError = ''
  while (Date.now() - started < timeoutMs) {
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
    await sleep(200)
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
  if (options.start) {
    const started = await runMeta(options, ['start', `${options.port}`, '--silent'])
    const actualPort = parseStartedPort(`${started.stdout}\n${started.stderr}`)
    if (actualPort) {
      options.port = actualPort
      options.url = `http://127.0.0.1:${actualPort}`
    }
    await waitForServer(options.url, options.timeoutMs)
  }
  const browser = await playwright.chromium.launch({
    headless: options.headless,
    channel: options.channel,
  })
  const page = await browser.newPage()
  const consoleLogs = []
  page.on('console', msg => {
    consoleLogs.push(`${msg.type()}: ${msg.text()}`)
  })
  page.on('pageerror', error => {
    consoleLogs.push(`pageerror: ${error.message}`)
  })
  const harness = {
    options,
    browser,
    page,
    consoleLogs,
    async goto() {
      await this.page.goto(options.url, {
        waitUntil: 'domcontentloaded',
        timeout: options.timeoutMs,
      })
    },
    async resetHostPage() {
      await this.page.goto(options.url, {
        waitUntil: 'domcontentloaded',
        timeout: options.timeoutMs,
      })
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
      await browser.close()
      if (options.stop) {
        await runMeta(options, ['stop']).catch(() => {})
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
  for (const file of options.files) {
    resetSuites()
    const abs = path.resolve(process.cwd(), file)
    await import(pathToFileURL(abs).href)
    const harness = await createHarness(options)
    try {
      const result = await withTimeout(
        runSuite(root, harness),
        options.totalTimeoutMs,
        `browser test run (${file})`,
      )
      passed += result.passed
      failed += result.failed
    } finally {
      await harness.close()
    }
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
