import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { escapeHtml, renderMarkdownToBookParts, slugify } from "./md2html.mjs";
import { fileURLToPath } from "node:url";

const toolsDir = path.dirname(fileURLToPath(import.meta.url));

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

  const options = {
    input: "",
    slug: "",
    title: "",
  };

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

  if (!options.input) {
    throw new Error("Missing input markdown path.");
  }

  return options;
}

function fillTemplate(template, values) {
  return template
    .replaceAll("{{TITLE}}", escapeHtml(values.title))
    .replaceAll("{{SOURCE_PATH}}", escapeHtml(values.sourcePath))
    .replaceAll("{{TOC_HTML}}", values.tocHtml)
    .replaceAll("{{CONTENT_HTML}}", values.contentHtml)
    .replaceAll("{{STYLESHEET_HREF}}", values.stylesheetHref);
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

  const html = fillTemplate(template, {
    title: parts.title,
    sourcePath: path.relative(repoRoot, inputPath).replaceAll("\\", "/"),
    tocHtml: parts.tocHtml,
    contentHtml: parts.contentHtml,
    stylesheetHref: path.relative(outputDir, stylesheetPath).replaceAll("\\", "/"),
  });

  await fs.mkdir(outputDir, { recursive: true });
  await fs.mkdir(path.join(outputDir, "assets"), { recursive: true });
  await fs.writeFile(outputHtml, html, "utf8");

  console.log(`Book slug: ${slug}`);
  console.log(`HTML: ${path.relative(repoRoot, outputHtml).replaceAll("\\", "/")}`);
  console.log(
    `PDF target: ${path.relative(repoRoot, path.join(outputDir, `${slug}.pdf`)).replaceAll("\\", "/")}`
  );
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
