import process from 'node:process'
import { exec } from './common.js'

const args = process.argv.slice(2)
const result = exec`${process.execPath} scripts/build.js -Package service -Test -TestPackage service -TestFilter native:* ${args}`
if (result.error || result.status !== 0) {
  process.exit(result.status ?? 1)
}
