import { spawn } from 'node:child_process'
import process from 'node:process'

const STALL_TIMEOUT_MS = 10_000

const formatDuration = elapsedMs => {
  const total = Math.max(0, Math.floor(elapsedMs))
  const minutes = Math.floor(total / 60000)
  const seconds = Math.floor((total % 60000) / 1000)
  const millis = total % 1000
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}.${String(millis).padStart(3, '0')}`
}

const normalizeLine = line => {
  if (!line) {
    return line
  }
  let out = line
  const cwd = process.cwd()
  if (cwd) {
    out = out.split(cwd).join('.')
  }
  const userProfile = process.env.USERPROFILE || process.env.HOME || ''
  if (userProfile) {
    out = out.split(`${userProfile}\\.moon`).join('~\\.moon')
    out = out.split(`${userProfile}/.moon`).join('~/.moon')
  }
  return out
}

const shouldSkipBranchLine = line => {
  if (!line || !line.trim()) {
    return true
  }
  return /(^| )failed:\s+.*\\moonc\.exe\s+build-package\b/.test(line) ||
    /(^| )failed:\s+.*\\moon(\.exe)?\s+build\b/.test(line) ||
    /(^| )failed:\s+.*\\moon(\.exe)?\s+test\b/.test(line)
}

const getBranchDisplayLines = branch => {
  const lines = branch.lines.filter(line => !shouldSkipBranchLine(line))
  if (branch.name !== 'moon' || branch.exitCode === 0) {
    return lines
  }
  const start = lines.findIndex(line => /(^|\])\s*test\s+.+\s+failed:/.test(line))
  return start >= 0 ? lines.slice(start) : []
}

const branchLabel = name => ({
  moon: 'core',
  native: 'nati',
  'browser-build': 'bpre',
  browser: 'brow',
  lifecycle: 'life',
}[name] || name)

const splitLines = text => {
  if (!text) {
    return []
  }
  return text.split(/\r?\n/).filter(Boolean)
}

const startProcess = (file, args) => {
  const child = spawn(file, args, {
    cwd: process.cwd(),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  })
  child.stdout.setEncoding('utf8')
  child.stderr.setEncoding('utf8')
  let stdout = ''
  let stderr = ''
  child.stdout.on('data', chunk => {
    stdout += chunk
  })
  child.stderr.on('data', chunk => {
    stderr += chunk
  })
  const done = new Promise(resolve => {
    child.on('exit', code => resolve({ code: code ?? -1, stdout, stderr }))
    child.on('error', error => resolve({ code: -1, stdout, stderr: `${stderr}\n${error.message}` }))
  })
  return { child, done }
}

const startBranch = (name, steps) => {
  const started = startProcess(steps[0].file, steps[0].args)
  return {
    name,
    label: branchLabel(name),
    startedAt: Date.now(),
    steps,
    stepIndex: 0,
    process: started.child,
    donePromise: started.done,
    lines: [],
    exitCode: null,
    done: false,
  }
}

const collectProcessOutput = async branch => {
  const result = await branch.donePromise
  branch.lines.push(...splitLines(result.stdout), ...splitLines(result.stderr))
  return result.code
}

const advanceBranch = async branch => {
  if (branch.done || branch.process.exitCode == null) {
    return false
  }
  const code = await collectProcessOutput(branch)
  if (code !== 0) {
    branch.exitCode = code
    branch.done = true
    return true
  }
  if (branch.stepIndex + 1 >= branch.steps.length) {
    branch.exitCode = 0
    branch.done = true
    return true
  }
  branch.stepIndex += 1
  const next = branch.steps[branch.stepIndex]
  const started = startProcess(next.file, next.args)
  branch.process = started.child
  branch.donePromise = started.done
  return false
}

const stopBranch = branch => {
  if (!branch || !branch.process) {
    return
  }
  try {
    if (branch.process.exitCode == null) {
      branch.process.kill('SIGKILL')
    }
  } catch {}
}

const printBranch = branch => {
  for (const line of getBranchDisplayLines(branch)) {
    console.log(`[${branch.label}] ${normalizeLine(line)}`)
  }
}

const browserBuildArgs = debugTiming => {
  const args = [
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    'scripts/build-native.ps1',
    '-Package',
    'service',
    '-Silent',
    '-TargetDir',
    '_build_browser',
  ]
  if (debugTiming) {
    args.push('-DebugTiming')
  }
  return args
}

const nativeArgs = debugTiming => {
  const args = [
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    'scripts/build-native.ps1',
    '-Package',
    'service',
    '-Test',
    '-TestPackage',
    'service',
    '-TestFilter',
    'native:*',
    '-TargetDir',
    '_build_test',
  ]
  if (debugTiming) {
    args.push('-DebugTiming')
  }
  return args
}

const lifecycleArgs = debugTiming => {
  const args = ['scripts/test-service-lifecycle.js', '--target-dir', '_build_browser']
  if (debugTiming) {
    args.push('--timing')
  }
  return args
}

const browserArgs = debugTiming => {
  const args = ['scripts/test-browser.js', '--target-dir', '_build_browser', '--start', '--stop']
  if (debugTiming) {
    args.push('--timing')
  }
  return args
}

const main = async () => {
  const debugTiming = process.argv.includes('--debug-timing')
  const startedAt = Date.now()
  const branches = [
    startBranch('moon', [{ file: 'moon', args: ['test'] }]),
    startBranch('browser-build', [{ file: 'pwsh', args: browserBuildArgs(debugTiming) }]),
    startBranch('native', [{ file: 'pwsh', args: nativeArgs(debugTiming) }]),
  ]
  const failed = []
  let timeout = false

  try {
    while (branches.length > 0) {
      if (Date.now() - startedAt >= STALL_TIMEOUT_MS) {
        timeout = true
        break
      }
      const active = branches.filter(branch => !branch.done)
      if (active.length === 0) {
        break
      }
      const winner = await Promise.race([
        ...active.map(branch => branch.donePromise.then(() => branch)),
        new Promise(resolve => setTimeout(() => resolve(null), 250)),
      ])
      if (!winner) {
        continue
      }
      if (!(await advanceBranch(winner))) {
        continue
      }
      printBranch(winner)
      if (winner.exitCode !== 0) {
        failed.push(`${winner.label}(exit ${winner.exitCode})`)
      } else if (winner.name === 'browser-build') {
        branches.push(
          startBranch('browser', [{ file: 'node', args: browserArgs(debugTiming) }]),
          startBranch('lifecycle', [{ file: 'node', args: lifecycleArgs(debugTiming) }]),
        )
      }
      const index = branches.indexOf(winner)
      if (index >= 0) {
        branches.splice(index, 1)
      }
    }
  } finally {
    for (const branch of branches.filter(branch => !branch.done)) {
      stopBranch(branch)
    }
  }

  if (timeout) {
    console.log(`[test] test-all stalled for ${STALL_TIMEOUT_MS / 1000}s`)
  }
  const summary = `[test] total ${formatDuration(Date.now() - startedAt)}`
  if (failed.length > 0 || timeout) {
    console.log(`${summary} failed: ${failed.join(', ')}`)
    process.exit(1)
  }
  console.log(`${summary} ok`)
}

main().catch(error => {
  console.error(error?.stack ?? error?.message ?? String(error))
  process.exit(1)
})
