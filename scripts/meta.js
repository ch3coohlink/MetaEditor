import process from 'node:process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { exec } from './common.js'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const targetDir = '_build'
process.chdir(root)

const build = exec`${process.execPath} scripts/build.js -Package service -TargetDir ${targetDir} -Silent`
if (build.error || build.status !== 0) {
  process.exit(build.status ?? 1)
}

const bin = path.join(root, targetDir, 'native', 'debug', 'build', 'service',
  process.platform === 'win32' ? 'service.exe' : 'service')
const run = exec`${bin} ${process.argv.slice(2)}`
if (run.error || run.status !== 0) {
  process.exit(run.status ?? 1)
}
