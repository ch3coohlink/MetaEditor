import { defineConfig } from "@vivliostyle/cli";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(toolsDir, "../..");
const entry = process.env.BOOK_ENTRY || path.resolve(toolsDir, "out/css-roadmap/index.html");
const output = process.env.BOOK_OUTPUT || path.resolve(toolsDir, "out/css-roadmap/css-roadmap.pdf");
const title = process.env.BOOK_TITLE || "MetaEditor CSS 引擎路线图";

export default defineConfig({
  entry,
  title,
  language: "zh-CN",
  size: "A4",
  singleDoc: true,
  workspaceDir: repoRoot,
  output: [
    {
      path: output,
      format: "pdf",
    },
  ],
});
