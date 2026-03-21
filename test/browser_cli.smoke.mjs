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

const query = (server, payload) => sendCommand(server, payload, '[QUERY] ')
const exec = (server, payload) => sendCommand(server, payload, '[EXEC] ')

const requireNode = (snapshot, predicate, message) => {
  const found = snapshot.nodes?.find(predicate)
  if (!found) {
    throw Error(message)
  }
  return found
}

const assertCount = (snapshot, expectedCount, expectedVersion) => {
  requireNode(
    snapshot,
    node => String(node.text || '').includes(`Count: ${expectedCount}`),
    `missing count node for Count: ${expectedCount}`
  )
  requireNode(
    snapshot,
    node => String(node.text || '').includes(`Version: ${expectedVersion}`),
    `missing version node for Version: ${expectedVersion}`
  )
}

const assertNodeText = async (server, id, expected) => {
  const node = await query(server, `query {"kind":"node","id":${id}}`)
  if (!node || node.text !== expected) {
    throw Error(`expected node ${id} text to be ${expected}, got ${node?.text}`)
  }
}

const server = spawn('node', ['cli/server.mjs'],
  { cwd: rootDir, shell: true, stdio: ['pipe', 'pipe', 'pipe'] })

server.stderr.on('data', chunk => process.stderr.write(chunk))

let browser
try {
  const hostLine = await waitForLine(server.stdout, line => line.includes('MetaEditor Host Active:'))
  const url = hostLine.match(/http:\/\/localhost:\d+/)?.[0]
  if (!url) {
    throw Error('failed to parse host url')
  }

  browser = await chromium.launch({ headless: true })
  const page = await browser.newPage()
  await page.goto(url)
  await page.waitForTimeout(300)

  const status = await sendCommand(server, 'status', '[STATUS] ')
  if (status.browsers < 1) {
    throw Error('browser client did not connect')
  }

  const initialUi = await query(server, 'query ui')
  const addButton = requireNode(initialUi, node => node.tag === 'button' && node.text === 'Add', 'missing Add button')
  const undoButton = requireNode(initialUi, node => node.tag === 'button' && node.text === 'Undo', 'missing Undo button')
  const redoButton = requireNode(initialUi, node => node.tag === 'button' && node.text === 'Redo', 'missing Redo button')
  assertCount(initialUi, 0, 0)

  const viewport = await query(server, 'query viewport')
  if (!(viewport.width > 0 && viewport.height > 0)) {
    throw Error('invalid viewport snapshot')
  }

  const firstButton = await query(server, 'query {"kind":"selector","selector":"button"}')
  if (firstButton?.id !== addButton.id) {
    throw Error('selector query did not resolve Add button')
  }

  await assertNodeText(server, addButton.id, 'Add')
  await assertNodeText(server, undoButton.id, 'Undo')
  await assertNodeText(server, redoButton.id, 'Redo')

  await exec(server, `exec {"kind":"focus","id":${addButton.id}}`)
  await page.waitForTimeout(100)
  const focused = await query(server, 'query focused')
  if (focused?.id !== addButton.id || focused?.focused !== true) {
    throw Error('focus op did not focus Add button')
  }

  await exec(server, `exec {"kind":"click","id":${addButton.id}}`)
  await page.waitForTimeout(120)
  assertCount(await query(server, 'query ui'), 1, 1)

  await exec(server, 'exec {"kind":"action","name":"add"}')
  await page.waitForTimeout(120)
  assertCount(await query(server, 'query ui'), 2, 2)

  await exec(server, `exec {"kind":"click","id":${undoButton.id}}`)
  await page.waitForTimeout(120)
  assertCount(await query(server, 'query ui'), 1, 1)

  await exec(server, 'exec {"kind":"action","name":"undo"}')
  await page.waitForTimeout(120)
  assertCount(await query(server, 'query ui'), 0, 0)

  await exec(server, 'exec {"kind":"action","name":"redo"}')
  await page.waitForTimeout(120)
  assertCount(await query(server, 'query ui'), 1, 1)

  await exec(server, `exec {"kind":"click","id":${redoButton.id}}`)
  await page.waitForTimeout(120)
  const finalUi = await query(server, 'query ui')
  assertCount(finalUi, 2, 2)
  if (!Array.isArray(finalUi.app_actions) || finalUi.app_actions.join(',') !== 'add,undo,redo') {
    throw Error(`unexpected app actions: ${JSON.stringify(finalUi.app_actions)}`)
  }
  if (finalUi.host?.connected_browsers < 1) {
    throw Error('ui host snapshot missing browser connection info')
  }

  console.log('[SMOKE] browser cli flow ok')
} finally {
  if (browser) {
    await browser.close()
  }
  if (!server.killed) {
    server.stdin.write('exit\n')
    await wait(200)
    server.kill()
  }
}
