import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const parseArgs = argv => ({
  includeSupport: argv.includes('--include-support'),
})

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

const walk = dir => {
  const entries = fs.readdirSync(dir, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      files.push(...walk(full))
    } else {
      files.push(full)
    }
  }
  return files
}

const main = () => {
  const options = parseArgs(process.argv.slice(2))
  const targets = ['app', 'service', 'src']
  if (options.includeSupport) {
    targets.push('scripts', 'index.html', 'moon.mod.json')
  }
  const extensions = new Set(['.mbt', '.js', '.mjs', '.c', '.sh', '.html', '.json', '.pkg'])
  const rows = []
  for (const target of targets) {
    const filePath = path.join(root, target)
    if (!fs.existsSync(filePath)) {
      continue
    }
    const stat = fs.statSync(filePath)
    const files = stat.isDirectory()
      ? walk(filePath).filter(file => extensions.has(path.extname(file).toLowerCase()))
      : [filePath]
    for (const file of files) {
      const relative = path.relative(root, file).split(path.sep).join('/')
      const text = fs.readFileSync(file, 'utf8')
      const lineCount = text ? text.split(/\r?\n/).length - (/\r?\n$/.test(text) ? 1 : 0) : 0
      const scope = relative.split('/')[0]
      const kind = /(^|\/)(test|tests)(\/|$)/.test(relative) || /\.test\./.test(relative)
        ? 'test'
        : 'prod'
      rows.push({ scope, relative, ext: path.extname(file).toLowerCase(), kind, lines: lineCount })
    }
  }
  const sum = rows => rows.reduce((total, row) => total + row.lines, 0)
  const byKind = kind => rows.filter(row => row.kind === kind)
  const group = key => Object.values(rows.reduce((map, row) => {
    const name = key(row)
    if (!map[name]) {
      map[name] = { name, files: 0, lines: 0 }
    }
    map[name].files += 1
    map[name].lines += row.lines
    return map
  }, {})).sort((a, b) => b.lines - a.lines)
  console.log(`core_total=${sum(rows)}`)
  console.log(`prod_total=${sum(byKind('prod'))}`)
  console.log(`test_total=${sum(byKind('test'))}`)
  console.log('')
  console.log('by_kind')
  for (const row of group(row => row.kind).sort((a, b) => a.name.localeCompare(b.name))) {
    console.log(`${row.name}\t${row.files}\t${row.lines}`)
  }
  console.log('by_scope_kind')
  for (const row of group(row => `${row.scope}\0${row.kind}`)) {
    const [scope, kind] = row.name.split('\0')
    console.log(`${scope}\t${kind}\t${row.files}\t${row.lines}`)
  }
  console.log('by_scope')
  for (const row of group(row => row.scope)) {
    console.log(`${row.name}\t${row.files}\t${row.lines}`)
  }
  console.log('by_ext')
  for (const row of group(row => row.ext).sort((a, b) => b.lines - a.lines)) {
    console.log(`${row.name}\t${row.files}\t${row.lines}`)
  }
}

main()
