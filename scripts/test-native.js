import { execFileSync } from 'node:child_process'
import process from 'node:process'

const args = process.argv.slice(2)
execFileSync(process.execPath, ['scripts/build.js', '-Package', 'service', '-Test', '-TestPackage', 'service', '-TestFilter', 'native:*', ...args], {
  stdio: 'inherit',
})
