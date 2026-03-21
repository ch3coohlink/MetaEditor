import { WebSocketServer } from 'ws'
import { createServer } from 'http'
import { readFile } from 'fs/promises'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'
import readline from 'readline'
import fs from 'fs'
import os from 'os'
import crypto from 'crypto'

const __dirname = dirname(fileURLToPath(import.meta.url))
const rootDir = join(__dirname, '..')
const projectHash = crypto.createHash('md5').update(rootDir).digest('hex').slice(0, 8)
const pidFile = join(os.tmpdir(), `mbt_editor_${projectHash}.pid`)
const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: false })

// --- 安全的旧进程清理 ---
if (fs.existsSync(pidFile)) {
  const content = fs.readFileSync(pidFile, 'utf8')
  const [oldPid, oldPath] = content.split('\n')
  
  if (oldPid && oldPath === rootDir) {
    const pid = parseInt(oldPid)
    try {
      process.kill(pid, 0)
      console.log(`Cleaning up old server for this project (PID: ${pid})...`)
      process.kill(pid, 'SIGKILL')
      // 给 OS 一点时间释放端口
      await new Promise(r => setTimeout(r, 100))
    } catch (e) { /* 不存在或无权 */ }
  }
}
fs.writeFileSync(pidFile, `${process.pid}\n${rootDir}`)

const cleanup = () => {
  if (fs.existsSync(pidFile)) {
    try {
      const content = fs.readFileSync(pidFile, 'utf8')
      if (content.split('\n')[0] === process.pid.toString()) fs.unlinkSync(pidFile)
    } catch (e) {}
  }
  process.exit(0)
}
process.on('SIGINT', cleanup)
process.on('SIGTERM', cleanup)
// --------------------

let wss = null
let clients = new Set()
let mbt_trigger = null
let mbt_trigger_ev = null
let ui_history = []
let app_actions = new Map()
let nextRequestId = 1
let pendingRequests = new Map()

const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

const getClientInfo = ws => ws._meta || { role: 'unknown' }
const setClientInfo = (ws, patch) => {
  ws._meta = { ...getClientInfo(ws), ...patch }
}
const getBrowserClient = () => {
  for (const client of clients) {
    if (client.readyState === 1 && getClientInfo(client).role === 'browser') {
      return client
    }
  }
  return null
}
const rejectPendingFor = ws => {
  for (const [requestId, pending] of pendingRequests) {
    if (pending.ws === ws) {
      clearTimeout(pending.timer)
      pending.reject(Error('browser disconnected'))
      pendingRequests.delete(requestId)
    }
  }
}
const requestBrowser = (payload, timeoutMs = 3000) => {
  const ws = getBrowserClient()
  if (!ws) {
    return Promise.reject(Error('no browser client connected'))
  }
  const requestId = nextRequestId++
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pendingRequests.delete(requestId)
      reject(Error(`browser request timeout: ${payload.action}`))
    }, timeoutMs)
    pendingRequests.set(requestId, { ws, resolve, reject, timer })
    ws.send(JSON.stringify({ type: 'bridge:request', request_id: requestId, ...payload }))
  })
}
const parseMaybeJson = raw => {
  if (!raw) {
    return null
  }
  const text = raw.trim()
  if (!text) {
    return null
  }
  if (text.startsWith('{')) {
    return JSON.parse(text)
  }
  return null
}
const parseQueryInput = raw => {
  const parsed = parseMaybeJson(raw)
  if (parsed) {
    return parsed
  }
  const text = (raw || '').trim()
  if (!text) {
    throw Error('missing query payload')
  }
  if (text === 'ui') {
    return { kind: 'ui' }
  }
  if (text === 'focused') {
    return { kind: 'focused' }
  }
  if (text === 'viewport') {
    return { kind: 'viewport' }
  }
  if (text.startsWith('node ')) {
    return { kind: 'node', id: Number(text.slice(5).trim()) }
  }
  if (text.startsWith('selector ')) {
    return { kind: 'selector', selector: text.slice(9).trim() }
  }
  if (text.startsWith('text ')) {
    return { kind: 'text', selector: text.slice(5).trim() }
  }
  return { kind: text }
}
const parseExecInput = raw => {
  const parsed = parseMaybeJson(raw)
  if (parsed) {
    return parsed
  }
  const text = (raw || '').trim()
  if (!text) {
    throw Error('missing exec payload')
  }
  if (text.startsWith('click ')) {
    return { kind: 'click', selector: text.slice(6).trim() }
  }
  if (text.startsWith('focus ')) {
    return { kind: 'focus', selector: text.slice(6).trim() }
  }
  return { kind: 'action', name: text }
}
const enrichUiSnapshot = snapshot => ({
  ...snapshot,
  app_actions: Array.from(app_actions.keys()),
  host: {
    connected_browsers: Array.from(clients).filter(client => getClientInfo(client).role === 'browser' && client.readyState === 1).length,
    command_history: ui_history.length,
  },
})
const runQuery = async raw => {
  const query = parseQueryInput(raw)
  const result = await requestBrowser({ action: 'query', query })
  if (query.kind === 'ui') {
    return enrichUiSnapshot(result)
  }
  return result
}
const runExec = async raw => {
  const command = parseExecInput(raw)
  if (command.kind === 'action') {
    const callbackId = app_actions.get(command.name)
    if (callbackId == null || !mbt_trigger) {
      throw Error(`unknown action: ${command.name}`)
    }
    mbt_trigger(callbackId)
    await wait(command.settle_ms ?? 50)
    return { ok: true, kind: 'action', name: command.name }
  }
  const result = await requestBrowser({ action: 'exec', command })
  await wait(command.settle_ms ?? 50)
  return result
}

const mbt_server = {
  start: (startPort = 8080) => {
    let port = startPort
    const tryListen = () => {
      const server = createServer(async (req, res) => {
        let filePath = join(rootDir, req.url === '/' ? 'index.html' : req.url)
        try {
          const content = await readFile(filePath)
          const ext = filePath.split('.').pop()
          const types = { html: 'text/html', js: 'text/javascript', css: 'text/css' }
          res.writeHead(200, { 'Content-Type': types[ext] || 'text/plain', 'Cache-Control': 'no-cache' })
          res.end(content)
        } catch (e) {
          res.writeHead(404)
          res.end('Not Found')
        }
      })

      server.on('error', (e) => {
        if (e.code === 'EADDRINUSE') {
          server.close()
          port++
          tryListen()
        } else console.error('Server failure:', e)
      })

      server.listen(port, () => {
        wss = new WebSocketServer({ server })
        console.log(`\n🚀 MetaEditor Host Active: http://localhost:${port}\n`)

        wss.on('connection', (ws) => {
          clients.add(ws)
          setClientInfo(ws, { role: 'unknown' })
          if (ui_history.length > 0) ws.send(JSON.stringify(ui_history))
          ws.on('message', (msg) => {
            try {
              const data = JSON.parse(msg)
              if (data.type === 'bridge:hello') {
                setClientInfo(ws, { role: 'browser', user_agent: data.user_agent })
              } else if (data.type === 'bridge:response') {
                const pending = pendingRequests.get(data.request_id)
                if (pending) {
                  clearTimeout(pending.timer)
                  pendingRequests.delete(data.request_id)
                  if (data.ok === false) pending.reject(Error(data.error || 'browser request failed'))
                  else pending.resolve(data.result)
                }
              } else if (data.type === 'event' && mbt_trigger) mbt_trigger(data.callback_id)
              else if (data.type === 'event_data' && mbt_trigger_ev) mbt_trigger_ev(data.callback_id, data.data)
            } catch (e) { console.error('Event error:', e) }
          })
          ws.on('close', () => {
            rejectPendingFor(ws)
            clients.delete(ws)
          })
        })
      })
    }
    tryListen()
  },
  send_batch: (jsonStrings) => {
    const cmds = jsonStrings.map(s => JSON.parse(s))
    for (const cmd of cmds) {
      if (cmd[0] === 8) app_actions.set(cmd[1], cmd[2])
    }
    ui_history.push(...cmds)
    const msg = JSON.stringify(cmds)
    for (const client of clients) if (client.readyState === 1) client.send(msg)
  }
}

globalThis.mbt_server = mbt_server
rl.on('line', (line) => {
  const trimmed = line.trim()
  if (!trimmed) return
  const splitIndex = trimmed.indexOf(' ')
  const cmd = splitIndex >= 0 ? trimmed.slice(0, splitIndex) : trimmed
  const rest = splitIndex >= 0 ? trimmed.slice(splitIndex + 1) : ''
  if (!cmd) return
  if (app_actions.has(cmd)) {
    if (mbt_trigger) mbt_trigger(app_actions.get(cmd))
    return
  }
  ;(async () => {
    switch (cmd) {
      case 'help':
        console.log('System: status, history, query <json|kind>, exec <json|action>, exit')
        console.log('Examples:')
        console.log('  query ui')
        console.log('  query {"kind":"selector","selector":"button"}')
        console.log('  exec {"kind":"click","selector":"button"}')
        console.log('  exec {"kind":"action","name":"undo"}')
        console.log('App Actions:', Array.from(app_actions.keys()).join(', ') || '(none)')
        break
      case 'query': {
        const result = await runQuery(rest)
        console.log(`[QUERY] ${JSON.stringify(result)}`)
        break
      }
      case 'exec': {
        const result = await runExec(rest)
        console.log(`[EXEC] ${JSON.stringify(result)}`)
        break
      }
      case 'status':
        console.log(`[STATUS] ${JSON.stringify({
          clients: clients.size,
          browsers: Array.from(clients).filter(client => getClientInfo(client).role === 'browser' && client.readyState === 1).length,
          cmd_history: ui_history.length,
          app_actions: Array.from(app_actions.keys()),
        })}`)
        break
      case 'history':
        console.log('[HISTORY]\n', JSON.stringify(ui_history, null, 2))
        break
      case 'exit':
        cleanup()
        break
      default:
        console.log(`Unknown command: ${cmd}`)
    }
  })().catch(error => {
    console.log(`[ERROR] ${error.message}`)
  })
})

async function run() {
  try {
    const mbt_module = await import('../_build/js/debug/build/cli/cli.js')
    mbt_trigger = mbt_module.trigger_callback
    mbt_trigger_ev = mbt_module.trigger_callback_ev
  } catch (e) { console.error('Core load failed:', e) }
}
run()
