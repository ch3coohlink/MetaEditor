import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { exec } from './common.js'

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
  const result = exec({ cwd: repo, stdio: silent ? 'pipe' : 'pipe' })`git -C ${repo} ${args}`
  if (result.error) {
    throw result.error
  }
  if ((result.status ?? 0) !== 0) {
    throw Error((result.stderr || result.stdout || 'git failed').trim())
  }
  return (result.stdout ?? '').trim()
}

const gitOk = (repo, args) => {
  try {
    const result = exec({ stdio: 'ignore' })`git -C ${repo} ${args}`
    if (result.error || result.status !== 0) {
      return false
    }
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
  exec`git -C ${mainWorkspace} fetch ${options.remote}`
  exec`git -C ${otherWorkspace} fetch ${options.remote}`
  assertRemoteBranchReady(mainWorkspace, options.remote, mainBranch)
  assertRemoteBranchReady(otherWorkspace, options.remote, otherBranch)
  exec`git -C ${mainWorkspace} pull --no-edit ${otherWorkspace} ${otherBranch}`
  exec`git -C ${otherWorkspace} pull --no-edit ${mainWorkspace} ${mainBranch}`
  exec`git -C ${mainWorkspace} push ${options.remote} ${mainBranch}`
  exec`git -C ${otherWorkspace} push ${options.remote} ${otherBranch}`
}

main()
