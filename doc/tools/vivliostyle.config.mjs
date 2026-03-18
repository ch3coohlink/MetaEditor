import { defineConfig } from "@vivliostyle/cli";

const repoRoot = process.cwd();
const entry = process.env.BOOK_ENTRY || "doc/tools/out/css-roadmap/index.html";
const output = process.env.BOOK_OUTPUT || "doc/tools/out/css-roadmap/css-roadmap.pdf";
const title = process.env.BOOK_TITLE || "MetaEditor CSS 引擎路线图";

export default defineConfig({
  entry,
  title,
  language: "zh-CN",
  size: "A4",
  workspaceDir: repoRoot,
  output: [
    {
      path: output,
      format: "pdf",
    },
  ],
});
