import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { execFileSync, spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { formatDuration, splitLines, writeLog, writeTimingLog } from './common.js'

const scriptPath = fileURLToPath(import.meta.url)
const root = path.resolve(path.dirname(scriptPath), '..')

const parseArgs = argv => {
  const options = {
    package: 'service',
    targetDir: '_build',
    test: false,
    testPackage: '',
    testFile: '',
    testFilter: '',
    cleanupOnly: false,
    cleanupStageLabel: '',
    debugTiming: false,
    buildOnly: false,
    skipBuild: false,
    skipCleanup: false,
    silent: false,
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '-Package' && i + 1 < argv.length) {
      options.package = argv[i + 1]
      i += 1
    } else if (arg === '-TargetDir' && i + 1 < argv.length) {
      options.targetDir = argv[i + 1]
      i += 1
    } else if (arg === '-Test') {
      options.test = true
    } else if (arg === '-TestPackage' && i + 1 < argv.length) {
      options.testPackage = argv[i + 1]
      i += 1
    } else if (arg === '-TestFile' && i + 1 < argv.length) {
      options.testFile = argv[i + 1]
      i += 1
    } else if (arg === '-TestFilter' && i + 1 < argv.length) {
      options.testFilter = argv[i + 1]
      i += 1
    } else if (arg === '-CleanupOnly') {
      options.cleanupOnly = true
    } else if (arg === '-CleanupStageLabel' && i + 1 < argv.length) {
      options.cleanupStageLabel = argv[i + 1]
      i += 1
    } else if (arg === '-DebugTiming') {
      options.debugTiming = true
    } else if (arg === '-BuildOnly') {
      options.buildOnly = true
    } else if (arg === '-SkipBuild') {
      options.skipBuild = true
    } else if (arg === '-SkipCleanup') {
      options.skipCleanup = true
    } else if (arg === '-Silent') {
      options.silent = true
    }
  }
  return options
}

const shouldDisplayNativeLine = line => {
  if (!line || !line.trim()) {
    return true
  }
  if (line.match(/^[^\\/\s][^\\/:]*\.c$/)) {
    return false
  }
  if (line.includes('.lib') && line.includes('.exp')) {
    return false
  }
  if (line.includes('"artifacts_path":')) {
    return false
  }
  return true
}

const nativeBinary = (packageName, targetDir) => path.join(
  root,
  targetDir,
  'native',
  'debug',
  'build',
  packageName,
  process.platform === 'win32' ? `${packageName}.exe` : packageName,
)

const stateRoot = path.join(os.tmpdir(), 'metaeditor-service-test')

const clearNativeServiceState = packageName => {
  if (packageName !== 'service') {
    return
  }
  for (const file of [
    '.meta-editor-service.pid',
    '.meta-editor-service.json',
    'metaeditor-service.stdout.log',
    'metaeditor-service.stderr.log',
    'test-service-cli.out',
    'test-service-cli.err',
  ]) {
    const target = path.join(stateRoot, file)
    if (fs.existsSync(target)) {
      fs.rmSync(target, { force: true })
    }
  }
}

const stopProcessTree = pid => {
  if (!pid || pid <= 0) {
    return
  }
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore' })
    return
  }
  try {
    process.kill(pid, 'SIGKILL')
  } catch {}
}

const stopRunningNativeBinary = (packageName, targetDir) => {
  const binaryPath = nativeBinary(packageName, targetDir)
  if (!fs.existsSync(binaryPath)) {
    return
  }
  if (packageName !== 'service') {
    return
  }
  const stateFile = path.join(stateRoot, '.meta-editor-service.json')
  if (!fs.existsSync(stateFile)) {
    return
  }
  try {
    const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'))
    const pid = Number(state?.pid)
    if (Number.isInteger(pid) && pid > 0) {
      stopProcessTree(pid)
    }
  } catch {}
}

const ensureVsEnvironment = () => {
  if (process.platform !== 'win32') {
    return
  }
  if (
    process.env.METAEDITOR_VSDEV_IMPORTED &&
    process.env.VSCMD_VER &&
    process.env.CC === 'clang-cl'
  ) {
    return
  }
  const vswhere = 'C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe'
  if (!fs.existsSync(vswhere)) {
    throw Error('vswhere.exe not found')
  }
  const vs = execFileSync(vswhere, [
    '-latest',
    '-products',
    '*',
    '-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '-property',
    'installationPath',
  ], { encoding: 'utf8' }).trim()
  if (!vs) {
    throw Error('Visual Studio C++ tools not found')
  }
  const devCmd = path.join(vs, 'Common7', 'Tools', 'VsDevCmd.bat')
  if (!fs.existsSync(devCmd)) {
    throw Error('VsDevCmd.bat not found')
  }
  const escapedDevCmd = devCmd.replace(/"/g, '\\"')
  const result = spawnSync('cmd.exe', [
    '/d',
    '/s',
    '/c',
    `""${escapedDevCmd}" -arch=amd64 -host_arch=amd64 -no_logo && set"`,
  ], {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 4,
    windowsVerbatimArguments: true,
  })
  if (result.error || result.status !== 0) {
    throw Error((result.stderr || result.stdout || 'failed to import VS environment').trim())
  }
  for (const line of splitLines(result.stdout)) {
    const index = line.indexOf('=')
    if (index <= 0) {
      continue
    }
    process.env[line.slice(0, index)] = line.slice(index + 1)
  }
  process.env.METAEDITOR_VSDEV_IMPORTED = vs
  process.env.CC = 'clang-cl'
}

const runStep = (label, stageLabel, file, args, timeoutMs, silent, quietOnSuccess = false) => {
  const started = Date.now()
  if (!quietOnSuccess) {
    writeLog(silent, label)
  }
  const result = spawnSync(file, args, {
    cwd: root,
    encoding: 'utf8',
    env: process.env,
    maxBuffer: 1024 * 1024 * 8,
    timeout: timeoutMs > 0 ? timeoutMs : undefined,
    windowsHide: true,
  })
  const output = splitLines(`${result.stdout ?? ''}${result.stderr ?? ''}`)
  if (result.error?.code === 'ETIMEDOUT') {
    for (const line of output) {
      writeLog(silent, line)
    }
    throw Error(`${label} timed out after ${timeoutMs} ms`)
  }
  if (result.error) {
    for (const line of output) {
      writeLog(silent, line)
    }
    throw result.error
  }
  const exitCode = result.status ?? 0
  const visible = exitCode === 0 ? output.filter(shouldDisplayNativeLine) : output
  if (!quietOnSuccess || exitCode !== 0) {
    for (const line of visible) {
      writeLog(silent, line)
    }
  }
  if (exitCode !== 0) {
    writeLog(silent, `${label} failed with exit code ${exitCode}`)
    process.exit(exitCode)
  }
  writeTimingLog(silent, process.env.METAEDITOR_DEBUG_TIMING === '1', `[timing] ${stageLabel} took ${formatDuration(Date.now() - started)}`)
}

const main = () => {
  const options = parseArgs(process.argv.slice(2))
  const started = Date.now()
  const buildTimeoutMs = 120000
  const testBuildTimeoutMs = 120000
  const testTimeoutMs = 5000
  process.chdir(root)
  if (options.cleanupOnly) {
    if (!options.skipCleanup) {
      stopRunningNativeBinary(options.package, options.targetDir)
      clearNativeServiceState(options.package)
    }
    return
  }
  if (options.debugTiming) {
    process.env.METAEDITOR_DEBUG_TIMING = '1'
  } else {
    delete process.env.METAEDITOR_DEBUG_TIMING
  }
  ensureVsEnvironment()
  if (!options.skipCleanup) {
    stopRunningNativeBinary(options.package, options.targetDir)
    clearNativeServiceState(options.package)
  }
  const moon = 'moon'
  const testArgs = options.testPackage
    ? ['test', '--target', 'native', '-p', options.testPackage]
    : ['test', '--target', 'native', options.package]
  if (options.testFile) {
    testArgs.push('--file', options.testFile)
  }
  if (options.testFilter) {
    testArgs.push('--filter', options.testFilter)
  }
  if (options.test) {
    runStep(
      `[native] ${[...testArgs, '--build-only'].join(' ')}`,
      'build native tests',
      moon,
      [...testArgs, '--build-only', '--target-dir', options.targetDir],
      testBuildTimeoutMs,
      options.silent,
      true,
    )
    if (options.buildOnly) {
      writeLog(options.silent, '[native] skip run native tests')
      writeTimingLog(options.silent, options.debugTiming, `[timing] total ${formatDuration(Date.now() - started)}`)
      return
    }
    runStep(
      `[native] ${testArgs.join(' ')}`,
      'run native tests',
      moon,
      [...testArgs, '--target-dir', options.targetDir],
      testTimeoutMs,
      options.silent,
    )
    writeTimingLog(options.silent, options.debugTiming, `[timing] total ${formatDuration(Date.now() - started)}`)
    return
  }
  if (options.skipBuild) {
    writeLog(options.silent, '[native] skip build native package')
  } else {
    runStep(
      `[native] moon build --target native ${options.package}`,
      'build native package',
      moon,
      ['build', '--target', 'native', options.package, '--target-dir', options.targetDir],
      buildTimeoutMs,
      options.silent,
      true,
    )
  }
  writeTimingLog(options.silent, options.debugTiming, `[timing] total ${formatDuration(Date.now() - started)}`)
}

main()
