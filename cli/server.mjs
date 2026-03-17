import { WebSocketServer } from 'ws'
import { createServer } from 'http'
import { readFile } from 'fs/promises'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'
import readline from 'readline'
import fs from 'fs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const rootDir = join(__dirname, '..')
const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: false })

let httpServer = null
let wss = null
let clients = new Set()
let mbt_trigger = null
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
          res.writeHead(200, { 'Content-Type': types[ext] || 'text/plain' })
          res.end(content)
        } catch (e) { res.writeHead(404); res.end("Not Found") }
      })

      const wsServer = new WebSocketServer({ server })
      server.on('error', (e) => {
        if (e.code === 'EADDRINUSE') {
          server.close(); port++; tryListen()
        } else console.error("Server failure:", e)
      })

      server.listen(port, () => {
        httpServer = server; wss = wsServer
        console.log(`\n🚀 MetaEditor Host: http://localhost:${port}`)
        fs.writeFileSync(join(rootDir, '.port'), port.toString())
        
        wss.on('connection', (ws) => {
          clients.add(ws)
          if (ui_history.length > 0) ws.send(JSON.stringify(ui_history))
          ws.on('message', (msg) => {
            try {
              const data = JSON.parse(msg)
              if (data.type === 'event' && mbt_trigger) mbt_trigger(data.callback_id)
            } catch (e) { console.error("Event error:", e) }
          })
          ws.on('close', () => clients.delete(ws))

        })
      })
    }
    tryListen()
  },
  send_batch: (cmds) => {
    for (const cmd of cmds) {
      if (cmd.$tag === 8) {
        console.log(`[AppAction] registered: '${cmd._0}'`)
        app_actions.set(cmd._0, cmd._1)
      }
    }
    ui_history.push(...cmds)
    if (clients.size === 0) return
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
      console.log("Commands: status, history, query <name>, exit")
      console.log("App Actions:", Array.from(app_actions.keys()).join(', ') || "(none)")
      break
    case 'query':
      if (mbt_query && args[0]) console.log(`Result: ${mbt_query(args[0])}`)
      break
    case 'status':
      console.log(`Projectors: ${clients.size}, History: ${ui_history.length}`)
      break
    case 'exit':
      if (fs.existsSync(join(rootDir, '.port'))) fs.unlinkSync(join(rootDir, '.port'))
      process.exit(0)
    default: console.log(`Unknown: ${cmd}`)
  }
})

async function run() {
  try {
    const mbt_module = await import('../_build/js/debug/build/cli/cli.js')
    mbt_trigger = mbt_module.trigger_callback
    mbt_query = mbt_module.trigger_query
  } catch (e) { console.error("Core load failed:", e) }
}
run()
