import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { exec, splitLines } from './common.js'

const quote = value => `'${String(value).replace(/'/g, "''")}'`
const quotePath = name => `'Env:${String(name).replace(/'/g, "''")}'`

const main = () => {
  if (process.platform !== 'win32') {
    throw Error('VS environment is only supported on Windows')
  }
  const vswhere = 'C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe'
  if (!fs.existsSync(vswhere)) {
    throw Error('vswhere.exe not found')
  }
  const vs = (exec({
    stdio: 'pipe',
  })`${vswhere} -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`
    .stdout ?? '').trim()
  if (!vs) {
    throw Error('Visual Studio C++ tools not found')
  }
  const devCmd = path.join(vs, 'Common7', 'Tools', 'VsDevCmd.bat')
  if (!fs.existsSync(devCmd)) {
    throw Error('VsDevCmd.bat not found')
  }
  const escapedDevCmd = devCmd.replace(/"/g, '\\"')
  const result = exec(
    `cmd.exe /d /s /c ""${escapedDevCmd}" -arch=amd64 -host_arch=amd64 -no_logo && set"`,
    { stdio: 'pipe', maxBuffer: 1024 * 1024 * 4 },
  )
  if (result.error || result.status !== 0) {
    throw Error((result.stderr || result.stdout || 'failed to import VS environment').trim())
  }
  const lines = []
  for (const line of splitLines(result.stdout ?? '')) {
    const index = line.indexOf('=')
    if (index <= 0) {
      continue
    }
    const name = line.slice(0, index)
    const value = line.slice(index + 1)
    lines.push(`Set-Item -Path ${quotePath(name)} -Value ${quote(value)}`)
  }
  lines.push(`Set-Item -Path ${quotePath('METAEDITOR_VSDEV_IMPORTED')} -Value ${quote(vs)}`)
  lines.push(`Set-Item -Path ${quotePath('CC')} -Value 'clang-cl'`)
  process.stdout.write(lines.join('\n'))
}

main()
