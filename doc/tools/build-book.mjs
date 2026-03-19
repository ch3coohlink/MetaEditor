import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import MarkdownIt from "markdown-it";
import hljs from "highlight.js";

const toolsDir = path.dirname(fileURLToPath(import.meta.url));

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function slugify(value) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[`~!@#$%^&*()+=[\]{};:'",.<>/?\\|]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-");
}

function renderToc(headings) {
  const items = headings.filter((heading) => heading.level >= 2 && heading.level <= 3);
  if (items.length === 0) return "";
  const entries = items
    .map((heading) => {
      const className = `toc-level-${heading.level}`;
      return `    <li class="${className}"><a href="#${heading.slug}"><span class="toc-title">${escapeHtml(
        heading.title
      )}</span><span class="toc-leader"></span><span class="toc-page"></span></a></li>`;
    })
    .join("\n");
  return `<nav class="toc" aria-label="Table of contents">\n  <h2>目录</h2>\n  <ol>\n${entries}\n  </ol>\n</nav>`;
}

function buildMarkdownRenderer(headings) {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: true,
    highlight: (str, lang) => {
      if (lang && hljs.getLanguage(lang)) {
        try {
          return `<pre class="hljs"><code>${hljs.highlight(str, { language: lang, ignoreIllegals: true }).value}</code></pre>`;
        } catch (_) {}
      }
      return `<pre class="hljs"><code>${md.utils.escapeHtml(str)}</code></pre>`;
    },
  });
  const defaultHeadingOpen = md.renderer.rules.heading_open ?? ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
  const usedSlugs = new Map();
  md.renderer.rules.heading_open = (tokens, idx, options, env, self) => {
    const titleToken = tokens[idx + 1];
    const level = Number.parseInt(tokens[idx].tag.slice(1), 10);
    const rawTitle = titleToken?.content ?? "";
    const baseSlug = slugify(rawTitle) || `section-${headings.length + 1}`;
    const count = usedSlugs.get(baseSlug) ?? 0;
    const slug = count === 0 ? baseSlug : `${baseSlug}-${count + 1}`;
    usedSlugs.set(baseSlug, count + 1);
    tokens[idx].attrSet("id", slug);
    headings.push({ level, title: rawTitle, slug });
    return defaultHeadingOpen(tokens, idx, options, env, self);
  };
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const language = (token.info || "").trim().split(/\s+/)[0];
    if (language === "mermaid") return `<pre class="mermaid">${escapeHtml(token.content.trim())}</pre>\n`;
    const highlighted = options.highlight(token.content, language, "");
    return highlighted + "\n";
  };
  return md;
}

function renderMarkdownToBookParts(markdown, options = {}) {
  const headings = [];
  const md = buildMarkdownRenderer(headings);
  const contentHtml = md.render(markdown);
  const detectedTitle = headings[0]?.title?.trim();
  const title = options.title || detectedTitle || options.fallbackTitle || "Untitled";
  const tocHtml = renderToc(headings);
  return { title, headings, tocHtml, contentHtml };
}

function printUsage() {
  console.log(`Usage:
  npm run doc:book:html -- <input.md> [--slug <slug>] [--title <title>]

Examples:
  npm run doc:book:html -- doc/legacy/css-roadmap.md
  npm run doc:book:html -- doc/legacy/css-roadmap.md --slug css-roadmap
  npm run doc:book:html -- doc/legacy/css-roadmap.md --title "MetaEditor CSS 引擎路线图"
`);
}

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printUsage();
    process.exit(argv.length === 0 ? 1 : 0);
  }
  const options = { input: "", slug: "", title: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!options.input && !arg.startsWith("--")) {
      options.input = arg;
      continue;
    }
    if (arg === "--slug") {
      options.slug = argv[i + 1] ?? "";
      i += 1;
      continue;
    }
    if (arg === "--title") {
      options.title = argv[i + 1] ?? "";
      i += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }
  if (!options.input) throw new Error("Missing input markdown path.");
  return options;
}

function fillTemplate(template, values) {
  return template
    .replaceAll("{{TITLE}}", escapeHtml(values.title))
    .replaceAll("{{SOURCE_PATH}}", escapeHtml(values.sourcePath))
    .replaceAll("{{TOC_HTML}}", values.tocHtml)
    .replaceAll("{{CONTENT_HTML}}", values.contentHtml)
    .replaceAll("{{THEME_CSS}}", values.themeCss);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const repoRoot = process.cwd();
  const inputPath = path.resolve(repoRoot, options.input);
  const markdown = await fs.readFile(inputPath, "utf8");
  const inputBaseName = path.basename(inputPath, path.extname(inputPath));
  const parts = renderMarkdownToBookParts(markdown, {
    title: options.title,
    fallbackTitle: inputBaseName,
  });

  const slug = options.slug || slugify(inputBaseName) || "book";
  const outputDir = path.resolve(toolsDir, "out", slug);
  const outputHtml = path.join(outputDir, "index.html");
  const templatePath = path.resolve(toolsDir, "book-template.html");
  const stylesheetPath = path.resolve(toolsDir, "book.css");
  const template = await fs.readFile(templatePath, "utf8");
  const themeCss = await fs.readFile(stylesheetPath, "utf8");

  const html = fillTemplate(template, {
    title: parts.title,
    sourcePath: path.relative(repoRoot, inputPath).replaceAll("\\", "/"),
    tocHtml: parts.tocHtml,
    contentHtml: parts.contentHtml,
    themeCss: themeCss,
  });

  await fs.mkdir(outputDir, { recursive: true });
  await fs.mkdir(path.join(outputDir, "assets"), { recursive: true });
  await fs.writeFile(outputHtml, html, "utf8");

  console.log(`Book slug: ${slug}`);
  console.log(`HTML: ${path.relative(repoRoot, outputHtml).replaceAll("\\", "/")}`);
  console.log(`PDF target: ${path.relative(repoRoot, path.join(outputDir, `${slug}.pdf`)).replaceAll("\\", "/")}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

