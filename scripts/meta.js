import fs from 'node:fs'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { exec } from './common.js'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const targetDir = '_build'
const browserRoot = path.join(root, targetDir, 'js', 'debug', 'build', 'browser')
const ensureBrowserEntry = targetDir => {
  const dir = path.join(root, targetDir, 'js', 'debug', 'build', 'browser')
  fs.mkdirSync(dir, { recursive: true })
  fs.copyFileSync(path.join(root, 'browser', 'index.html'), path.join(dir, 'index.html'))
}
process.chdir(root)

const nativeBuild = exec.start(process.execPath, [
  'scripts/build.js',
  '-Package',
  'service',
  '-TargetDir',
  targetDir,
  '-Silent',
])
const browserBuild = exec.start('moon', [
  'build',
  '--target',
  'js',
  'browser',
  '--target-dir',
  targetDir,
])
const [nativeResult, browserResult] = await Promise.all([
  nativeBuild.done,
  browserBuild.done,
])
if (nativeResult.code !== 0) {
  process.stdout.write(nativeResult.stdout ?? '')
  process.stderr.write(nativeResult.stderr ?? '')
  process.exit(nativeResult.code)
}
if (browserResult.code !== 0) {
  process.stdout.write(browserResult.stdout ?? '')
  process.stderr.write(browserResult.stderr ?? '')
  process.exit(browserResult.code)
}
ensureBrowserEntry(targetDir)

const bin = path.join(root, targetDir, 'native', 'debug', 'build', 'service',
  process.platform === 'win32' ? 'service.exe' : 'service')
const run = exec({ cwd: browserRoot })`${bin} ${process.argv.slice(2)}`
if (run.error || run.status !== 0) {
  process.exit(run.status ?? 1)
}
