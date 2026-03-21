import { chromium } from 'playwright'
import { spawn } from 'child_process'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const rootDir = join(__dirname, '..')
const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

const waitForLine = (stream, predicate, timeoutMs = 15000) => new Promise((resolve, reject) => {
  let buffer = ''
  const timer = setTimeout(() => {
    cleanup()
    reject(Error('timed out waiting for process output'))
  }, timeoutMs)
  const cleanup = () => {
    clearTimeout(timer)
    stream.off('data', onData)
  }
  const onData = chunk => {
    buffer += chunk.toString()
    const lines = buffer.split(/\r?\n/)
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      if (predicate(line)) {
        cleanup()
        resolve(line)
        return
      }
    }
  }
  stream.on('data', onData)
})

const sendCommand = async (server, command, marker) => {
  server.stdin.write(`${command}\n`)
  const line = await waitForLine(server.stdout, value => value.startsWith(marker))
  return JSON.parse(line.slice(marker.length))
}

const server = spawn('node', ['cli/server.mjs'],
  { cwd: rootDir, shell: true, stdio: ['pipe', 'pipe', 'pipe'] })

server.stderr.on('data', chunk => process.stderr.write(chunk))

let browser
try {
  const hostLine = await waitForLine(server.stdout, line => line.includes('MetaEditor Host Active:'))
  const url = hostLine.match(/http:\/\/localhost:\d+/)?.[0]
  if (!url) { throw Error('failed to parse host url') }

  browser = await chromium.launch({ headless: true })
  const page = await browser.newPage()
  await page.goto(url)
  await page.waitForTimeout(300)

  const status = await sendCommand(server, 'status', '[STATUS] ')
  if (status.browsers < 1) { throw Error('browser client did not connect') }

  const ui = await sendCommand(server, 'query ui', '[QUERY] ')
  if (!ui.nodes?.some(node => node.tag === 'button' && node.text.includes('Add'))) {
    throw Error('failed to discover Add button in UI snapshot')
  }

  await sendCommand(server, 'exec {"kind":"click","selector":"button"}', '[EXEC] ')
  await page.waitForTimeout(200)

  const updatedUi = await sendCommand(server, 'query ui', '[QUERY] ')
  if (!updatedUi.nodes?.some(node => String(node.text || '').includes('Count: 1'))) {
    throw Error('count did not update after click')
  }

  console.log('[SMOKE] browser cli flow ok')
} finally {
  if (browser) { await browser.close() }
  if (!server.killed) {
    server.stdin.write('exit\n')
    await wait(200)
    server.kill()
  }
}
