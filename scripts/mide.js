import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const args = process.argv.slice(2)
if (args.length === 0) {
  throw Error('usage: npm run mide -- <ide-subcommand> [args...]')
}

if (process.platform !== 'win32') {
  execFileSync('moon', ['ide', ...args], { stdio: 'inherit' })
  process.exit(0)
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const bashCandidates = []
try {
  const gitPath = execFileSync('where', ['git.exe'], { encoding: 'utf8' }).trim().split(/\r?\n/)[0]
  if (gitPath) {
    bashCandidates.push(path.join(path.dirname(path.dirname(gitPath)), 'bin', 'bash.exe'))
  }
} catch {}
bashCandidates.push('C:\\Program Files\\Git\\bin\\bash.exe', 'C:\\Program Files\\Git\\usr\\bin\\bash.exe')
const bash = bashCandidates.find(candidate => fs.existsSync(candidate))
if (!bash) {
  throw Error('bash.exe not found, install Git for Windows first')
}
const drive = root.slice(0, 1).toLowerCase()
const rest = root.slice(2).replace(/\\/g, '/')
const bashRoot = `/${drive}${rest}`
const bashArgs = args.map(arg => `'${arg.replace(/'/g, `'\\''`)}'`)
const command = `command -v moon >/dev/null || { echo 'moon not found in Git Bash PATH' >&2; exit 127; }; cd '${bashRoot}' && moon ide ${bashArgs.join(' ')}`
execFileSync(bash, ['-lc', command], { stdio: 'inherit' })
