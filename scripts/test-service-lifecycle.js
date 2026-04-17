import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { spawn } from 'node:child_process'

const parseArgs = argv => {
  const options = {
    targetDir: '_build_browser',
    timeoutMs: 2500,
    readyTimeoutMs: 800,
    port: null,
    timing: false,
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
    } else if (arg === '--timing') {
      options.timing = true
    }
  }
  return options
}

const nowMs = () => Number(process.hrtime.bigint() / 1000000n)

const withTiming = async (options, label, run) => {
  const started = nowMs()
  try {
    return await run()
  } finally {
    if (options.timing) {
      console.log(`[lifecycle] ${label}: ${nowMs() - started}ms`)
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
      server.close(() => reject(Error('failed to allocate lifecycle port')))
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

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

const runMeta = (bin, stateDir, args, timeoutMs) => new Promise((resolve, reject) => {
  const child = spawn(bin, ['--state-dir', stateDir, ...args], {
    cwd: process.cwd(),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  })
  const chunks = []
  let settled = false
  const push = chunk => {
    if (chunk?.length) {
      chunks.push(Buffer.from(chunk))
    }
  }
  const finish = action => {
    if (settled) {
      return
    }
    settled = true
    clearTimeout(timer)
    child.stdout.destroy()
    child.stderr.destroy()
    action()
  }
  child.stdout.on('data', push)
  child.stderr.on('data', push)
  child.on('error', error => finish(() => reject(error)))
  const timer = setTimeout(() => {
    child.kill()
    finish(() => reject(Error(`meta ${args.join(' ')} timed out after ${timeoutMs}ms`)))
  }, timeoutMs)
  child.on('exit', code => {
    setTimeout(() => finish(() => resolve({
      code: code ?? -1,
      output: Buffer.concat(chunks).toString('utf8'),
    })), 20)
  })
})

const waitForServiceStatePort = async (stateDir, timeoutMs) => {
  const statePath = path.join(stateDir, '.meta-editor-service.json')
  const started = nowMs()
  for (;;) {
    try {
      const text = fs.readFileSync(statePath, 'utf8')
      const state = JSON.parse(text)
      const port = Number(state?.port)
      if (Number.isInteger(port) && port > 0) {
        return port
      }
    } catch {}
    if (nowMs() - started > timeoutMs) {
      throw Error(`timed out waiting for service port after ${timeoutMs}ms`)
    }
    await sleep(20)
  }
}

const waitPageReady = async (port, timeoutMs) => {
  const started = nowMs()
  for (;;) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/`)
      const body = await response.text()
      if (
        response.ok &&
        body.includes('<div id="app-info">Status: Initializing Bridge...</div>') &&
        body.includes('<script src="src/bridge.js"></script>')
      ) {
        return
      }
    } catch {}
    if (nowMs() - started > timeoutMs) {
      throw Error(`timed out waiting for page ready after ${timeoutMs}ms`)
    }
    await sleep(20)
  }
}

const clearStateFiles = stateDir => {
  for (const file of ['.meta-editor-service.json', '.meta-editor-service.lock']) {
    const target = path.join(stateDir, file)
    if (fs.existsSync(target)) {
      fs.rmSync(target, { force: true })
    }
  }
}

const writeState = (stateDir, pid, port) => {
  fs.writeFileSync(
    path.join(stateDir, '.meta-editor-service.json'),
    JSON.stringify({ pid, port }),
    'utf8',
  )
}

const stopService = async (bin, stateDir, timeoutMs, label) => {
  const result = await runMeta(bin, stateDir, ['stop'], timeoutMs)
  if (result.code !== 0) {
    throw Error(`${label}: stop exit ${result.code}\n${result.output}`)
  }
}

const assertContains = (text, expected, label) => {
  if (!text.includes(expected)) {
    throw Error(`${label}: expected output to contain ${JSON.stringify(expected)}\n${text}`)
  }
}

const main = async () => {
  const options = parseArgs(process.argv.slice(2))
  const bin = serviceBin(options.targetDir)
  if (!fs.existsSync(bin)) {
    throw Error(`service binary is missing: ${bin}`)
  }
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), 'metaeditor-lifecycle-'))
  const port = options.port ?? await pickPort()
  try {
    await runMeta(bin, stateDir, ['stop'], 500).catch(() => {})
    clearStateFiles(stateDir)

    const totalStarted = nowMs()
    const idleStop = await withTiming(options, 'idle stop', () => runMeta(bin, stateDir, ['stop'], 500))
    if (idleStop.code !== 0) {
      throw Error(`idle stop exit ${idleStop.code}\n${idleStop.output}`)
    }
    assertContains(idleStop.output, 'service is not running', 'idle stop')

    writeState(stateDir, 999999, 19199)
    const start = await withTiming(options, 'start command', () => runMeta(
      bin,
      stateDir,
      ['start', `${port}`],
      options.timeoutMs,
    ))
    if (start.code !== 0) {
      throw Error(`start exit ${start.code}\n${start.output}`)
    }
    assertContains(start.output, `started http://localhost:${port}`, 'start')
    const readyPort = await withTiming(options, 'start port', () => waitForServiceStatePort(
      stateDir,
      options.readyTimeoutMs,
    ))
    await withTiming(options, 'start ready', () => waitPageReady(readyPort, options.readyTimeoutMs))

    await withTiming(options, 'stop command', () => stopService(
      bin,
      stateDir,
      options.timeoutMs,
      'stop after first start',
    ))

    const startAgain = await withTiming(options, 'start again command', () => runMeta(
      bin,
      stateDir,
      ['start', `${port}`],
      options.timeoutMs,
    ))
    if (startAgain.code !== 0) {
      throw Error(`start again exit ${startAgain.code}\n${startAgain.output}`)
    }
    assertContains(startAgain.output, `started http://localhost:${port}`, 'start again')
    const startAgainPort = await withTiming(options, 'start again port', () => waitForServiceStatePort(
      stateDir,
      options.readyTimeoutMs,
    ))
    await withTiming(options, 'start again ready', () => waitPageReady(
      startAgainPort,
      options.readyTimeoutMs,
    ))

    const restart = await withTiming(options, 'restart command', () => runMeta(
      bin,
      stateDir,
      ['restart', `${port}`],
      options.timeoutMs,
    ))
    if (restart.code !== 0) {
      throw Error(`restart exit ${restart.code}\n${restart.output}`)
    }
    const restartPort = await withTiming(options, 'restart port', () => waitForServiceStatePort(
      stateDir,
      options.readyTimeoutMs,
    ))
    await withTiming(options, 'restart ready', () => waitPageReady(
      restartPort,
      options.readyTimeoutMs,
    ))

    await withTiming(options, 'final stop', () => stopService(bin, stateDir, options.timeoutMs, 'final stop'))
    if (options.timing) {
      console.log(`[lifecycle] total: ${nowMs() - totalStarted}ms`)
    }
    console.log('[lifecycle] ok')
  } finally {
    await runMeta(bin, stateDir, ['stop'], 500).catch(() => {})
    fs.rmSync(stateDir, { recursive: true, force: true })
  }
}

main().catch(error => {
  console.error(error?.stack ?? error?.message ?? String(error))
  process.exit(1)
})
