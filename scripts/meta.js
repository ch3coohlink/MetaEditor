import { spawnSync } from 'node:child_process'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

const build = spawnSync(process.execPath, ['scripts/build.js', '-Package', 'service', '-Silent'], {
  cwd: root,
  encoding: 'utf8',
  stdio: 'inherit',
})
if (build.error || build.status !== 0) {
  process.exit(build.status ?? 1)
}

const bin = path.join(root, '_build', 'native', 'debug', 'build', 'service', process.platform === 'win32' ? 'service.exe' : 'service')
const run = spawnSync(bin, process.argv.slice(2), {
  cwd: root,
  stdio: 'inherit',
  windowsHide: true,
})
if (run.error || run.status !== 0) {
  process.exit(run.status ?? 1)
}
