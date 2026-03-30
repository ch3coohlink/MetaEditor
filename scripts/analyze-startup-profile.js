const fs = require('fs')
const os = require('os')
const path = require('path')
const zlib = require('zlib')

const parseArgs = () => {
  const args = process.argv.slice(2)
  const options = {
    profile: path.join(os.tmpdir(), 'metaeditor-start-silent-profile.json.gz'),
    symbols: null,
    threads: [],
    topStacks: 5,
    mode: 'hot',
    timelineLimit: 25,
  }
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--profile' && i + 1 < args.length) {
      options.profile = args[++i]
    } else if (arg === '--symbols' && i + 1 < args.length) {
      options.symbols = args[++i]
    } else if (arg === '--thread' && i + 1 < args.length) {
      options.threads.push(Number(args[++i]))
    } else if (arg === '--top-stacks' && i + 1 < args.length) {
      options.topStacks = Number(args[++i])
    } else if (arg === '--mode' && i + 1 < args.length) {
      options.mode = args[++i]
    } else if (arg === '--timeline-limit' && i + 1 < args.length) {
      options.timelineLimit = Number(args[++i])
    } else {
      throw Error(`unknown arg: ${arg}`)
    }
  }
  if (!options.symbols) {
    options.symbols = options.profile.replace(/\.json\.gz$/, '.json.syms.json')
  }
  return options
}

const loadJson = file => {
  const raw = fs.readFileSync(file)
  const text = file.endsWith('.gz') ? zlib.gunzipSync(raw).toString('utf8') : raw.toString('utf8')
  return JSON.parse(text)
}

const buildSymbolMaps = symbolsData => {
  const strings = symbolsData.string_table
  const maps = new Map()
  for (const entry of symbolsData.data) {
    const addrs = entry.known_addresses.map(v => v[0])
    const infos = entry.known_addresses.map(([base, tableIndex]) => {
      const record = entry.symbol_table[tableIndex]
      return { base, name: strings[record.symbol], size: record.size ?? 0 }
    })
    maps.set(entry.debug_name, { addrs, infos })
  }
  return maps
}

const bisectRight = (arr, x) => {
  let lo = 0
  let hi = arr.length
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    if (x < arr[mid]) {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  return lo
}

const resolveSymbol = (symbolMaps, debugName, addr) => {
  const map = symbolMaps.get(debugName)
  if (!map) {
    return `${debugName}!0x${addr.toString(16)}`
  }
  const idx = bisectRight(map.addrs, addr) - 1
  if (idx < 0) {
    return `${debugName}!0x${addr.toString(16)}`
  }
  const { base, name } = map.infos[idx]
  const delta = addr - base
  return delta === 0 ? name : `${name}+0x${delta.toString(16)}`
}

const stackFrames = (thread, stackIndex) => {
  const frames = []
  let current = stackIndex
  while (current !== null) {
    frames.push(thread.stackTable.frame[current])
    current = thread.stackTable.prefix[current]
  }
  return frames.reverse()
}

const frameSymbol = (profile, thread, symbolMaps, frameIndex) => {
  const funcIndex = thread.frameTable.func[frameIndex]
  const resourceIndex = thread.funcTable.resource[funcIndex]
  const libIndex = resourceIndex == null ? null : thread.resourceTable.lib[resourceIndex]
  const debugName = libIndex == null || !profile.libs[libIndex]
    ? 'unknown'
    : profile.libs[libIndex].debugName
  const addr = thread.frameTable.address[frameIndex]
  return resolveSymbol(symbolMaps, debugName, addr)
}

const counterMostCommon = (values, weights, limit) => {
  const counts = new Map()
  for (let i = 0; i < values.length; i++) {
    const value = values[i]
    const weight = weights ? weights[i] : 1
    counts.set(value, (counts.get(value) ?? 0) + weight)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit)
}

const summarizeThreads = profile => {
  console.log('Threads by sample count:')
  const infos = profile.threads
    .map((thread, index) => ({
      index,
      thread,
      count: (thread.samples.weight ?? Array(thread.samples.length).fill(1))
        .reduce((a, b) => a + b, 0),
    }))
    .sort((a, b) => b.count - a.count)
  for (const { index, thread, count } of infos) {
    console.log(
      `  thread=${index} pid=${thread.pid} tid=${thread.tid} name=${thread.name} samples=${thread.samples.length} weight=${count}`
    )
  }
  return infos.map(v => v.index)
}

const summarizeHotThread = (profile, symbolMaps, threadIndex, topStacks) => {
  const thread = profile.threads[threadIndex]
  console.log(
    `Thread ${threadIndex} pid=${thread.pid} tid=${thread.tid} name=${thread.name} samples=${thread.samples.length}`
  )
  for (const [stackIndex, count] of counterMostCommon(
    thread.samples.stack,
    thread.samples.weight,
    topStacks
  )) {
    console.log(`  stack ${stackIndex} weight=${count}`)
    const frames = stackFrames(thread, stackIndex).slice(-12)
    for (const frameIndex of frames) {
      console.log(`    ${frameSymbol(profile, thread, symbolMaps, frameIndex)}`)
    }
  }
  console.log('')
}

const buildTopDownTree = (profile, symbolMaps, threadIndex) => {
  const thread = profile.threads[threadIndex]
  const root = { name: '<root>', weight: 0, children: new Map() }
  const weights = thread.samples.weight ?? Array(thread.samples.length).fill(1)
  for (let i = 0; i < thread.samples.stack.length; i++) {
    const stackIndex = thread.samples.stack[i]
    const weight = weights[i]
    let node = root
    node.weight += weight
    for (const frameIndex of stackFrames(thread, stackIndex)) {
      const symbol = frameSymbol(profile, thread, symbolMaps, frameIndex)
      if (!node.children.has(symbol)) {
        node.children.set(symbol, { name: symbol, weight: 0, children: new Map() })
      }
      node = node.children.get(symbol)
      node.weight += weight
    }
  }
  return root
}

const printTopDownTree = (node, totalWeight, depth, childLimit) => {
  const children = [...node.children.values()].sort((a, b) => b.weight - a.weight)
  for (const child of children.slice(0, childLimit)) {
    const pct = ((child.weight / totalWeight) * 100).toFixed(1)
    console.log(`${'  '.repeat(depth)}${pct}% ${child.name}`)
    if (depth < 7) {
      printTopDownTree(child, totalWeight, depth + 1, depth === 0 ? 8 : 6)
    }
  }
}

const summarizeTopDownThread = (profile, symbolMaps, threadIndex) => {
  const thread = profile.threads[threadIndex]
  const tree = buildTopDownTree(profile, symbolMaps, threadIndex)
  console.log(
    `Thread ${threadIndex} pid=${thread.pid} tid=${thread.tid} name=${thread.name} totalWeight=${tree.weight}`
  )
  printTopDownTree(tree, tree.weight, 0, 8)
  console.log('')
}

const sampleWeight = (thread, index) =>
  thread.samples.weight ? thread.samples.weight[index] : 1

const stackSymbols = (profile, thread, symbolMaps, stackIndex) =>
  stackFrames(thread, stackIndex).map(frameIndex => frameSymbol(profile, thread, symbolMaps, frameIndex))

const summarizeWaitThread = (profile, symbolMaps, threadIndex, timelineLimit) => {
  const thread = profile.threads[threadIndex]
  const target = 'M0MP411moonbitlang5async8internal11event__loop9EventLoop16wait__for__event(_M0TP411moonbitlang5async8internal11event__loop9EventLoop*)'
  const nextCounts = new Map()
  const prevCounts = new Map()
  const timeline = []

  for (let i = 0; i < thread.samples.stack.length; i++) {
    const stackIndex = thread.samples.stack[i]
    const symbols = stackSymbols(profile, thread, symbolMaps, stackIndex)
    const idx = symbols.indexOf(target)
    if (idx >= 0) {
      const prev = idx > 0 ? symbols[idx - 1] : '<root>'
      const next = idx + 1 < symbols.length ? symbols[idx + 1] : '<leaf>'
      const weight = sampleWeight(thread, i)
      prevCounts.set(prev, (prevCounts.get(prev) ?? 0) + weight)
      nextCounts.set(next, (nextCounts.get(next) ?? 0) + weight)
      timeline.push({
        time: thread.samples.time[i],
        weight,
        prev,
        next,
        tail: symbols.slice(Math.max(0, idx - 4), Math.min(symbols.length, idx + 4)),
      })
    }
  }

  const total = timeline.reduce((sum, item) => sum + item.weight, 0)
  console.log(
    `Thread ${threadIndex} pid=${thread.pid} tid=${thread.tid} name=${thread.name} waitSamples=${timeline.length} waitWeight=${total}`
  )
  console.log('  callers before wait_for_event:')
  for (const [name, weight] of [...prevCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8)) {
    console.log(`    ${((weight / total) * 100).toFixed(1)}% ${name}`)
  }
  console.log('  callees under wait_for_event:')
  for (const [name, weight] of [...nextCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8)) {
    console.log(`    ${((weight / total) * 100).toFixed(1)}% ${name}`)
  }
  console.log('  timeline around wait_for_event:')
  for (const item of timeline.slice(0, timelineLimit)) {
    console.log(
      `    t=${item.time.toFixed(3)} w=${item.weight} prev=${item.prev} next=${item.next}`
    )
    console.log(`      ${item.tail.join(' -> ')}`)
  }
  console.log('')
}

const main = () => {
  const options = parseArgs()
  const profile = loadJson(options.profile)
  const symbols = loadJson(options.symbols)
  const symbolMaps = buildSymbolMaps(symbols)

  console.log(`profile: ${options.profile}`)
  console.log(`symbols: ${options.symbols}`)
  console.log(`symbolicated: ${profile.meta?.symbolicated}`)
  console.log(`mode: ${options.mode}`)
  console.log('')

  const hottest = summarizeThreads(profile)
  console.log('')

  const targets = options.threads.length > 0 ? options.threads : hottest.slice(0, 4)
  for (const threadIndex of targets) {
    if (options.mode === 'topdown') {
      summarizeTopDownThread(profile, symbolMaps, threadIndex)
    } else if (options.mode === 'wait') {
      summarizeWaitThread(profile, symbolMaps, threadIndex, options.timelineLimit)
    } else {
      summarizeHotThread(profile, symbolMaps, threadIndex, options.topStacks)
    }
  }
}

main()
