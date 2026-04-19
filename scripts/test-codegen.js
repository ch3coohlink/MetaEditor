import process from 'node:process'
import { exec } from './common.js'

const args = process.argv.slice(2)

const runCodegen = exec({ cwd: 'codegen' })`moon run .`
if (runCodegen.error || runCodegen.status !== 0) {
  process.exit(runCodegen.status ?? 1)
}

const testCodegen = exec({ cwd: 'codegen' })`moon test -p parsergen ${args}`
if (testCodegen.error || testCodegen.status !== 0) {
  process.exit(testCodegen.status ?? 1)
}
