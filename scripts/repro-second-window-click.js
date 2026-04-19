import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { chromium } from 'playwright'
import { exec, sleep } from './common.js'

const parseArgs = argv => {
  const options = {
    targetDir: '_build',
    rounds: 6,
    port: null,
    headed: true,
    browserChannel: 'msedge',
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--target-dir' && i + 1 < argv.length) {
      options.targetDir = argv[i + 1]
      i += 1
    } else if (arg === '--rounds' && i + 1 < argv.length) {
      options.rounds = Number(argv[i + 1]) || options.rounds
      i += 1
    } else if (arg === '--port' && i + 1 < argv.length) {
      options.port = Number(argv[i + 1]) || options.port
      i += 1
    } else if (arg === '--headless') {
      options.headed = false
    } else if (arg === '--channel' && i + 1 < argv.length) {
      options.browserChannel = argv[i + 1]
      i += 1
    }
  }
  return options
}

const pickPort = () => new Promise((resolve, reject) => {
  const server = net.createServer()
  server.unref()
  server.on('error', reject)
  server.listen(0, '127.0.0.1', () => {
    const address = server.address()
    if (!address || typeof address === 'string') {
      server.close(() => reject(Error('failed to allocate repro port')))
      return
    }
    const { port } = address
    server.close(error => error ? reject(error) : resolve(port))
  })
})

const waitFor = async (fn, timeoutMs, label) => {
  const started = Date.now()
  for (;;) {
    const value = await fn().catch(() => false)
    if (value) {
      return value
    }
    if (Date.now() - started > timeoutMs) {
      throw Error(`${label} timed out after ${timeoutMs}ms`)
    }
    await sleep(20)
  }
}

const waitForHttp = (port, timeoutMs) => waitFor(async () => {
  const res = await fetch(`http://127.0.0.1:${port}/`)
  return res.ok
}, timeoutMs, 'wait http')

const runMeta = (bin, root, stateDir, args, timeoutMs = 6000) => new Promise((resolve, reject) => {
  const started = exec.start(bin, ['--state-dir', stateDir, ...args], { cwd: root })
  const child = started.child
  const timer = setTimeout(() => {
    try {
      child.kill('SIGKILL')
    } catch {}
    reject(Error(`meta ${args.join(' ')} timed out after ${timeoutMs}ms`))
  }, timeoutMs)
  started.done.then(result => {
    clearTimeout(timer)
    resolve(result)
  })
})

const installBridgeAdapter = async page => {
  await page.evaluate(() => {
    if (globalThis.__mbt_repro_bridge_installed) {
      return
    }
    const bridge = globalThis.mbt_bridge
    const encodeQuery = (kind, value) => {
      if (!kind || kind === 'node') { return 'Node' }
      if (kind === 'text') { return 'Text' }
      if (kind === 'attr') { return ['Attr', value ?? ''] }
      if (kind === 'prop') { return ['Prop', value ?? ''] }
      if (kind === 'style') { return ['Style', value ?? ''] }
      return kind
    }
    globalThis.mbt_bridge = {
      status: () => bridge.status(),
      init: () => bridge.init(),
      query: (path, kind = 'node', value) => bridge.query(path, encodeQuery(kind, value)),
      dispatch: (path, kind, value) => bridge.dispatch(path, value ?? kind),
      cli: (cmd, arg = '') => bridge.cli(cmd, arg),
      reset: (root = '') => bridge.reset(root),
    }
    globalThis.__mbt_repro_bridge_installed = true
  })
}

const textOf = value => Array.isArray(value) && value[0] === 'Text' ? value[1] ?? '' : ''

const entryPath = async (page, title = 'Demo') => {
  for (let i = 0; i < 8; i += 1) {
    const value = await page.evaluate(async path => {
      try {
        return await globalThis.mbt_bridge.query(path, 'text')
      } catch {
        return null
      }
    }, `entries/${i}/name`)
    if (textOf(value) === title) {
      return `entries/${i}/entry`
    }
  }
  throw Error(`missing entry: ${title}`)
}

const pointOf = async (page, targetPath) => {
  const node = await page.evaluate(pathValue => globalThis.mbt_bridge.query(pathValue, 'node'), targetPath)
  const id = Array.isArray(node) && node[0] === 'Node' ? node[1]?.id ?? 0 : 0
  return page.evaluate(value => globalThis.__mbt_bridge_internal?.pointOf?.(value) ?? null, id)
}

const windowTitles = page => page.evaluate(async () => {
  const out = []
  for (let i = 0; i < 4; i += 1) {
    try {
      const value = await globalThis.mbt_bridge.query(`windows/${i}/title`, 'text')
      out.push(Array.isArray(value) && value[0] === 'Text' ? value[1] ?? '' : '')
    } catch {}
  }
  return out
})

const waitConnected = (page, timeoutMs, label) => waitFor(
  () => page.evaluate(() => globalThis.mbt_bridge?.status?.().state === 'connected'),
  timeoutMs,
  label,
)

const waitDemoEntry = (page, timeoutMs, label) => waitFor(
  () => entryPath(page).catch(() => ''),
  timeoutMs,
  label,
)

const launchBrowser = async options => {
  const launchOptions = { headless: !options.headed }
  if (options.browserChannel) {
    try {
      return await chromium.launch({ ...launchOptions, channel: options.browserChannel })
    } catch {}
  }
  return chromium.launch(launchOptions)
}

const assertOk = (result, label) => {
  if (result.code !== 0) {
    const text = [result.stdout, result.stderr].filter(Boolean).join('\n')
    throw Error(`${label} failed\n${text}`)
  }
}

const bootPage = async (context, port) => {
  const page = await context.newPage()
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'domcontentloaded' })
  await installBridgeAdapter(page)
  await waitConnected(page, 3000, 'wait connected')
  await page.evaluate(() => globalThis.mbt_bridge.reset('host'))
  await waitDemoEntry(page, 3000, 'wait demo entry')
  return page
}

const main = async () => {
  const options = parseArgs(process.argv.slice(2))
  const port = options.port ?? await pickPort()
  const bin = path.resolve(
    process.cwd(),
    options.targetDir,
    'native',
    'debug',
    'build',
    'service',
    process.platform === 'win32' ? 'service.exe' : 'service',
  )
  const root = path.resolve(process.cwd(), options.targetDir, 'js', 'debug', 'build', 'browser')
  if (!fs.existsSync(bin)) {
    throw Error(`missing service binary under ${options.targetDir}`)
  }
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), 'metaeditor-second-window-'))
  const service = exec.start(bin, [
    '--internal_boot_as_service',
    '--state-dir', stateDir,
    '--port', String(port),
  ], { cwd: root })
  let browser1 = null
  let browser2 = null
  let context1 = null
  let context2 = null
  let reproduced = 0
  try {
    await waitForHttp(port, 3000)
    browser1 = await launchBrowser(options)
    browser2 = await launchBrowser(options)
    context1 = await browser1.newContext({ viewport: { width: 1200, height: 900 } })
    context2 = await browser2.newContext({ viewport: { width: 1200, height: 900 } })
    const page1 = await bootPage(context1, port)
    const page2 = await bootPage(context2, port)

    for (let i = 0; i < options.rounds; i += 1) {
      const restart = await runMeta(bin, root, stateDir, ['restart', String(port)])
      assertOk(restart, 'meta restart')
      await waitForHttp(port, 3000)
      await waitConnected(page1, 3000, `page1 reconnect ${i}`)
      await waitConnected(page2, 3000, `page2 reconnect ${i}`)
      await waitDemoEntry(page1, 3000, `page1 demo ${i}`)
      await waitDemoEntry(page2, 3000, `page2 demo ${i}`)
      await sleep(1200)

      const point1 = await pointOf(page1, await entryPath(page1))
      await page1.bringToFront()
      await sleep(400)
      await page1.mouse.click(point1.x, point1.y)
      await sleep(500)

      const point2 = await pointOf(page2, await entryPath(page2))
      await page2.bringToFront()
      await sleep(400)
      await page2.mouse.click(point2.x, point2.y)
      await sleep(500)
      const first = await windowTitles(page2)
      if (first.length === 0) {
        await page2.mouse.click(point2.x, point2.y)
        await sleep(500)
      }
      const second = await windowTitles(page2)
      const hit = first.length === 0 && second.length > 0
      if (hit) {
        reproduced += 1
      }
      console.log(JSON.stringify({ round: i, first, second, reproduced: hit }))

      await page2.evaluate(() => globalThis.mbt_bridge.reset('host'))
      await waitDemoEntry(page2, 3000, `page2 reset ${i}`)
      await page1.evaluate(() => globalThis.mbt_bridge.reset('host'))
      await waitDemoEntry(page1, 3000, `page1 reset ${i}`)
    }

    if (reproduced === 0) {
      throw Error('repro did not trigger')
    }
    console.log(`reproduced ${reproduced}/${options.rounds}`)
  } finally {
    await context1?.close().catch(() => {})
    await context2?.close().catch(() => {})
    await browser1?.close().catch(() => {})
    await browser2?.close().catch(() => {})
    await runMeta(bin, root, stateDir, ['stop'], 1500).catch(() => {})
    try {
      service.child.kill('SIGKILL')
    } catch {}
    fs.rmSync(stateDir, { recursive: true, force: true })
  }
}

main().catch(error => {
  console.error(error?.stack ?? error?.message ?? String(error))
  process.exit(1)
})
