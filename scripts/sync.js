import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const parseArgs = argv => {
  const options = {
    otherWorkspace: '../MetaEditor-2',
    remote: 'origin',
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--other-workspace' && i + 1 < argv.length) {
      options.otherWorkspace = argv[i + 1]
      i += 1
    } else if (arg === '--remote' && i + 1 < argv.length) {
      options.remote = argv[i + 1]
      i += 1
    }
  }
  return options
}

const fail = message => {
  throw Error(message)
}

const git = (repo, args, silent = false) => {
  const output = execFileSync('git', ['-C', repo, ...args], {
    cwd: repo,
    encoding: 'utf8',
    stdio: silent ? ['ignore', 'pipe', 'pipe'] : ['ignore', 'pipe', 'pipe'],
  })
  return output.trim()
}

const gitOk = (repo, args) => {
  try {
    execFileSync('git', ['-C', repo, ...args], { stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}

const assertClean = repo => {
  if (git(repo, ['status', '--porcelain'])) {
    fail(`${path.basename(repo)} has local changes`)
  }
}

const currentBranch = repo => {
  const branch = git(repo, ['symbolic-ref', '--quiet', '--short', 'HEAD'])
  if (!branch) {
    fail(`${path.basename(repo)} is not on a branch`)
  }
  return branch
}

const assertRemoteBranchReady = (repo, remote, branch) => {
  if (!gitOk(repo, ['show-ref', '--verify', '--quiet', `refs/remotes/${remote}/${branch}`])) {
    fail(`${path.basename(repo)} is missing ${remote}/${branch}`)
  }
  const [left, right] = git(repo, ['rev-list', '--left-right', '--count', `${branch}...${remote}/${branch}`]).split(/\s+/)
  if (Number(right) !== 0) {
    fail(`${path.basename(repo)} is behind ${remote}/${branch}`)
  }
}

const main = () => {
  const options = parseArgs(process.argv.slice(2))
  const mainWorkspace = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
  const otherWorkspace = path.resolve(options.otherWorkspace)
  if (mainWorkspace === otherWorkspace) {
    fail('the two workspaces must be different')
  }
  const mainBranch = currentBranch(mainWorkspace)
  const otherBranch = currentBranch(otherWorkspace)
  assertClean(mainWorkspace)
  assertClean(otherWorkspace)
  const mainRemoteUrl = git(mainWorkspace, ['remote', 'get-url', options.remote])
  const otherRemoteUrl = git(otherWorkspace, ['remote', 'get-url', options.remote])
  if (mainRemoteUrl !== otherRemoteUrl) {
    fail(`remote ${options.remote} differs between the two workspaces`)
  }
  execFileSync('git', ['-C', mainWorkspace, 'fetch', options.remote], { stdio: 'inherit' })
  execFileSync('git', ['-C', otherWorkspace, 'fetch', options.remote], { stdio: 'inherit' })
  assertRemoteBranchReady(mainWorkspace, options.remote, mainBranch)
  assertRemoteBranchReady(otherWorkspace, options.remote, otherBranch)
  execFileSync('git', ['-C', mainWorkspace, 'pull', '--no-edit', otherWorkspace, otherBranch], { stdio: 'inherit' })
  execFileSync('git', ['-C', otherWorkspace, 'pull', '--no-edit', mainWorkspace, mainBranch], { stdio: 'inherit' })
  execFileSync('git', ['-C', mainWorkspace, 'push', options.remote, mainBranch], { stdio: 'inherit' })
  execFileSync('git', ['-C', otherWorkspace, 'push', options.remote, otherBranch], { stdio: 'inherit' })
}

main()
