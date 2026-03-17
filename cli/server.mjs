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
let mbt_query = null
let ui_history = []
let app_actions = new Map()

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
          if (ui_history.length > 0) ws.send(JSON.stringify(ui_history))
          ws.on('message', (msg) => {
            try {
              const data = JSON.parse(msg)
              if (data.type === 'event' && mbt_trigger) mbt_trigger(data.callback_id)
              else if (data.type === 'event_data' && mbt_trigger_ev) mbt_trigger_ev(data.callback_id, data.data)
            } catch (e) { console.error('Event error:', e) }
          })
          ws.on('close', () => clients.delete(ws))
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
  const [cmd, ...args] = line.trim().split(/\s+/)
  if (!cmd) return
  if (app_actions.has(cmd)) {
    if (mbt_trigger) mbt_trigger(app_actions.get(cmd))
    return
  }
  switch (cmd) {
    case 'help':
      console.log('System: status, history, query <name>, exit')
      console.log('App Actions:', Array.from(app_actions.keys()).join(', ') || '(none)')
      break
    case 'query':
      if (mbt_query && args[0]) console.log(`[QUERY] ${args[0]} = ${mbt_query(args[0])}`)
      break
    case 'status':
      console.log(`[STATUS] Clients: ${clients.size}, CmdHistory: ${ui_history.length}`)
      break
    case 'history':
      console.log('[HISTORY]\n', JSON.stringify(ui_history, null, 2))
      break
    case 'exit': cleanup()
    default: console.log(`Unknown command: ${cmd}`)
  }
})

async function run() {
  try {
    const mbt_module = await import('../_build/js/debug/build/cli/cli.js')
    mbt_trigger = mbt_module.trigger_callback
    mbt_trigger_ev = mbt_module.trigger_callback_ev
    mbt_query = mbt_module.trigger_query
  } catch (e) { console.error('Core load failed:', e) }
}
run()
