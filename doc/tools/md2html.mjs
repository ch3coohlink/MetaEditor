import MarkdownIt from "markdown-it";

export function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function slugify(value) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[`~!@#$%^&*()+=[\]{};:'",.<>/?\\|]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-");
}

function renderToc(headings) {
  const items = headings.filter((heading) => heading.level >= 2 && heading.level <= 3);
  if (items.length === 0) {
    return "";
  }

  const entries = items
    .map((heading) => {
      const className = `toc-level-${heading.level}`;
      return `    <li class="${className}"><a href="#${heading.slug}">${escapeHtml(
        heading.title
      )}</a></li>`;
    })
    .join("\n");

  return `<nav class="toc" aria-label="Table of contents">
  <h2>目录</h2>
  <ol>
${entries}
  </ol>
</nav>`;
}

function buildMarkdownRenderer(headings) {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: true,
  });

  const defaultHeadingOpen =
    md.renderer.rules.heading_open ??
    ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));

  const defaultFence =
    md.renderer.rules.fence ??
    ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options, env));

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
    if (language === "mermaid") {
      return `<pre class="mermaid">${escapeHtml(token.content.trim())}</pre>\n`;
    }
    return defaultFence(tokens, idx, options, env, self);
  };

  return md;
}

export function renderMarkdownToBookParts(markdown, options = {}) {
  const headings = [];
  const md = buildMarkdownRenderer(headings);
  const contentHtml = md.render(markdown);
  const detectedTitle = headings[0]?.title?.trim();
  const title = options.title || detectedTitle || options.fallbackTitle || "Untitled";
  const tocHtml = renderToc(headings);
  return {
    title,
    headings,
    tocHtml,
    contentHtml,
  };
}
