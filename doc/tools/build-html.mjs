import fs from "node:fs/promises"
import fsSync from "node:fs"
import http from "node:http"
import path from "node:path"
import process from "node:process"
import { fileURLToPath } from "node:url"
import MarkdownIt from "markdown-it"
import hljs from "highlight.js"
import { chromium } from "playwright-core"

const toolsDir = path.dirname(fileURLToPath(import.meta.url))

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

function slugify(value) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[`~!@#$%^&*()+=[\]{};:'",.<>/?\\|]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
}

function renderToc(headings) {
  const items = headings.filter((heading) => heading.level >= 2 && heading.level <= 3)
  if (items.length === 0) return ""
  const entries = items
    .map((heading) => {
      const className = `toc-level-${heading.level}`
      return `    <li class="${className}"><a href="#${heading.slug}"><span class="toc-title">${escapeHtml(
        heading.title
      )}</span><span class="toc-leader"></span><span class="toc-page"></span></a></li>`
    })
    .join("\n")
  return `<nav class="toc" aria-label="Table of contents">\n  <h2>目录</h2>\n  <ol>\n${entries}\n  </ol>\n</nav>`
}

function buildMarkdownRenderer(headings) {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: true,
    highlight: (str, lang) => {
      if (lang && hljs.getLanguage(lang)) {
        try {
          return `<pre class="hljs"><code>${hljs.highlight(str, { language: lang, ignoreIllegals: true }).value}</code></pre>`
        } catch (_) { }
      }
      return `<pre class="hljs"><code>${md.utils.escapeHtml(str)}</code></pre>`
    },
  })
  const defaultHeadingOpen = md.renderer.rules.heading_open ?? ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options))
  const usedSlugs = new Map()
  md.renderer.rules.heading_open = (tokens, idx, options, env, self) => {
    const titleToken = tokens[idx + 1]
    const level = Number.parseInt(tokens[idx].tag.slice(1), 10)
    const rawTitle = titleToken?.content ?? ""
    const baseSlug = slugify(rawTitle) || `section-${headings.length + 1}`
    const count = usedSlugs.get(baseSlug) ?? 0
    const slug = count === 0 ? baseSlug : `${baseSlug}-${count + 1}`
    usedSlugs.set(baseSlug, count + 1)
    tokens[idx].attrSet("id", slug)
    headings.push({ level, title: rawTitle, slug })
    return defaultHeadingOpen(tokens, idx, options, env, self)
  }
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const token = tokens[idx]
    const language = (token.info || "").trim().split(/\s+/)[0]
    if (language === "mermaid") return `<pre class="mermaid">${escapeHtml(token.content.trim())}</pre>\n`
    const highlighted = options.highlight(token.content, language, "")
    return highlighted + "\n"
  }
  return md
}

function renderMarkdownToBookParts(markdown, options = {}) {
  const headings = []
  const md = buildMarkdownRenderer(headings)
  const contentHtml = md.render(markdown)
  const detectedTitle = headings[0]?.title?.trim()
  const title = options.title || detectedTitle || options.fallbackTitle || "Untitled"
  const tocHtml = renderToc(headings)
  return { title, headings, tocHtml, contentHtml }
}

function printUsage() {
  console.log(`Usage:
  npm run book:html -- <input.md> [--slug <slug>] [--title <title>]

Examples:
  npm run book:html -- ../legacy/css-roadmap.md
  npm run book:html -- ../legacy/css-roadmap.md --slug css-roadmap
  npm run book:html -- ../legacy/css-roadmap.md --title "MetaEditor CSS 引擎路线图"
`)
}

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printUsage()
    process.exit(argv.length === 0 ? 1 : 0)
  }
  const options = { input: "", slug: "", title: "" }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (!options.input && !arg.startsWith("--")) {
      options.input = arg
      continue
    }
    if (arg === "--slug") {
      options.slug = argv[i + 1] ?? ""
      i += 1
      continue
    }
    if (arg === "--title") {
      options.title = argv[i + 1] ?? ""
      i += 1
      continue
    }
    throw new Error(`Unknown argument: ${arg}`)
  }
  if (!options.input) throw new Error("Missing input markdown path.")
  return options
}

function fillTemplate(template, values) {
  return template
    .replaceAll("{{TITLE}}", escapeHtml(values.title))
    .replaceAll("{{SOURCE_PATH}}", escapeHtml(values.sourcePath))
    .replaceAll("{{TOC_HTML}}", values.tocHtml)
    .replaceAll("{{CONTENT_HTML}}", values.contentHtml)
    .replaceAll("{{THEME_CSS}}", values.themeCss)
}

function resolveBrowserPath() {
  const envPath = process.env.BOOK_BROWSER || process.env.VIVLIOSTYLE_BROWSER
  if (envPath) {
    return envPath
  }

  const candidates = [
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  ]

  return candidates.find((candidate) => fsSync.existsSync(candidate)) || ""
}

function createStaticServer(rootDir) {
  return http.createServer(async (request, response) => {
    const requestPath = decodeURIComponent((request.url ?? "/").split("?")[0])
    const relativePath = requestPath === "/" ? "index.html" : requestPath.replace(/^\/+/, "")
    const filePath = path.join(rootDir, relativePath)

    try {
      const data = await fs.readFile(filePath)
      const ext = path.extname(filePath).toLowerCase()
      const contentType =
        ext === ".html"
          ? "text/html; charset=utf-8"
          : ext === ".css"
            ? "text/css; charset=utf-8"
            : "text/plain; charset=utf-8"
      response.writeHead(200, { "Content-Type": contentType })
      response.end(data)
    } catch {
      response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" })
      response.end("Not found")
    }
  })
}

async function prerenderMermaid(outputDir, outputHtml) {
  if (process.env.BOOK_SKIP_PRERENDER === "1") {
    return { skipped: true, rendered: 0, total: 0, warnings: [] }
  }

  const html = await fs.readFile(outputHtml, "utf8")
  if (!html.includes('class="mermaid"')) {
    return { skipped: true, rendered: 0, total: 0, warnings: [] }
  }

  const browserPath = resolveBrowserPath()
  if (!browserPath) {
    throw new Error("Could not find a browser for Mermaid prerender. Set BOOK_BROWSER.")
  }

  const server = createStaticServer(outputDir)
  const port = await new Promise((resolve, reject) => {
    server.once("error", reject)
    server.listen(0, "127.0.0.1", () => {
      const address = server.address()
      if (!address || typeof address === "string") {
        reject(new Error("Failed to start local preview server."))
        return
      }
      resolve(address.port)
    })
  })

  const browser = await chromium.launch({
    executablePath: browserPath,
    headless: true,
  })
  const page = await browser.newPage()
  const consoleMessages = []
  const pageErrors = []
  page.on("console", (message) => {
    consoleMessages.push(`${message.type()}: ${message.text()}`)
  })
  page.on("pageerror", (error) => {
    pageErrors.push(error.stack || String(error))
  })

  try {
    await page.goto(`http://127.0.0.1:${port}/`, {
      waitUntil: "domcontentloaded",
      timeout: 120000,
    })
    await page.waitForFunction(() => window.__BOOK_MERMAID_STATUS?.ready === true, {
      timeout: 30000,
    })

    const result = await page.evaluate(() => {
      const status = window.__BOOK_MERMAID_STATUS ?? {
        total: 0,
        rendered: 0,
        errors: [],
      }
      const loader = document.querySelector("[data-mermaid-loader]")
      if (loader) {
        loader.remove()
      }
      return {
        total: status.total ?? 0,
        rendered: status.rendered ?? document.querySelectorAll("pre.mermaid svg").length,
        errors: Array.isArray(status.errors) ? status.errors : [],
        html: `<!doctype html>\n${document.documentElement.outerHTML}`,
      }
    })

    const nonNoiseMessages = consoleMessages.filter(
      (message) =>
        !message.includes("visualViewport.js") &&
        !message.includes("Failed to load resource: the server responded with a status of 404")
    )

    if (pageErrors.length > 0 || result.errors.length > 0 || result.rendered !== result.total) {
      const details = [
        `Mermaid prerender failed: rendered ${result.rendered}/${result.total}.`,
        ...result.errors,
        ...pageErrors,
        ...nonNoiseMessages,
      ]
      throw new Error(details.join("\n"))
    }

    await fs.writeFile(outputHtml, result.html, "utf8")
    return {
      skipped: false,
      rendered: result.rendered,
      total: result.total,
      warnings: consoleMessages.filter((message) => message.includes("visualViewport.js")),
    }
  } finally {
    await page.close()
    await browser.close()
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())))
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2))
  const repoRoot = process.cwd()
  const inputPath = path.resolve(repoRoot, options.input)
  const markdown = await fs.readFile(inputPath, "utf8")
  const inputBaseName = path.basename(inputPath, path.extname(inputPath))
  const parts = renderMarkdownToBookParts(markdown, {
    title: options.title,
    fallbackTitle: inputBaseName,
  })

  const slug = options.slug || slugify(inputBaseName) || "book"
  const outputDir = path.resolve(toolsDir, "out", slug)
  const outputHtml = path.join(outputDir, "index.html")
  const templatePath = path.resolve(toolsDir, "book-template.html")
  const stylesheetPath = path.resolve(toolsDir, "book.css")
  const template = await fs.readFile(templatePath, "utf8")
  const themeCss = await fs.readFile(stylesheetPath, "utf8")

  const html = fillTemplate(template, {
    title: parts.title,
    sourcePath: path.relative(repoRoot, inputPath).replaceAll("\\", "/"),
    tocHtml: parts.tocHtml,
    contentHtml: parts.contentHtml,
    themeCss: themeCss,
  })

  await fs.mkdir(outputDir, { recursive: true })
  await fs.writeFile(outputHtml, html, "utf8")
  const mermaidResult = await prerenderMermaid(outputDir, outputHtml)

  console.log(`Book slug: ${slug}`)
  console.log(`HTML: ${path.relative(repoRoot, outputHtml).replaceAll("\\", "/")}`)
  console.log(`PDF target: ${path.relative(repoRoot, path.join(outputDir, `${slug}.pdf`)).replaceAll("\\", "/")}`)
  if (!mermaidResult.skipped) {
    console.log(`Mermaid prerender: ${mermaidResult.rendered}/${mermaidResult.total}`)
    for (const warning of mermaidResult.warnings) {
      console.warn(`Mermaid warning: ${warning}`)
    }
  }
}

main().catch((error) => {
  console.error(error.message)
  process.exitCode = 1
})
