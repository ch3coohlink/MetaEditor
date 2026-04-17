import { spawn, spawnSync } from 'node:child_process'
import process from 'node:process'

export const formatDuration = elapsedMs => {
  const total = Math.max(0, Math.floor(elapsedMs))
  const minutes = Math.floor(total / 60000)
  const seconds = Math.floor((total % 60000) / 1000)
  const millis = total % 1000
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}.${String(millis).padStart(3, '0')}`
}

export const normalizeLine = line => {
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

export const writeLog = (silent, message) => {
  if (!silent) {
    console.log(normalizeLine(message))
  }
}

export const writeTimingLog = (silent, enabled, message) => {
  if (enabled && !silent) {
    console.log(normalizeLine(message))
  }
}

export const splitLines = text => {
  if (!text) {
    return []
  }
  return text.split(/\r?\n/).filter(Boolean)
}

export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

const quoteArg = value => {
  const text = String(value)
  if (text === '') {
    return process.platform === 'win32' ? '""' : "''"
  }
  if (process.platform === 'win32') {
    if (!/[\s"&|<>^]/.test(text)) {
      return text
    }
    return `"${text.replace(/"/g, '\\"')}"`
  }
  if (!/[\s"'$`\\]/.test(text)) {
    return text
  }
  return `'${text.replace(/'/g, `'\\''`)}'`
}

const quoteValue = value => {
  if (Array.isArray(value)) {
    return value.map(quoteValue).join(' ')
  }
  return quoteArg(value)
}

const buildCommand = (strings, values) => strings.reduce((out, part, index) => {
  const value = index < values.length ? quoteValue(values[index]) : ''
  return out + part + value
}, '')

const runExec = (command, options = {}) => spawnSync(command, {
  cwd: options.cwd ?? process.cwd(),
  stdio: options.stdio ?? 'inherit',
  encoding: options.encoding ?? 'utf8',
  env: options.env ?? process.env,
  shell: options.shell ?? true,
  windowsHide: options.windowsHide ?? true,
  timeout: options.timeout,
  maxBuffer: options.maxBuffer,
})

export const exec = (first, ...rest) => {
  if (Array.isArray(first) && 'raw' in first) {
    return runExec(buildCommand(first, rest))
  }
  if (typeof first === 'string') {
    return runExec(first, rest[0] ?? {})
  }
  const options = first ?? {}
  return (strings, ...values) => runExec(buildCommand(strings, values), options)
}

exec.start = (command, argsOrOptions = [], maybeOptions = {}) => {
  const withArgs = Array.isArray(argsOrOptions)
  const args = withArgs ? argsOrOptions : []
  const options = withArgs ? maybeOptions : argsOrOptions
  const child = withArgs
    ? spawn(command, args, {
      cwd: options.cwd ?? process.cwd(),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: options.windowsHide ?? true,
    })
    : spawn(command, {
      cwd: options.cwd ?? process.cwd(),
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: options.shell ?? true,
      windowsHide: options.windowsHide ?? true,
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
