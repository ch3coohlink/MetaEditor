import { spawn } from "node:child_process";
import process from "node:process";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const toolsDir = path.dirname(fileURLToPath(import.meta.url));

function resolveBrowserPath() {
  const envPath = process.env.BOOK_BROWSER || process.env.VIVLIOSTYLE_BROWSER;
  if (envPath && fs.existsSync(envPath)) {
    return envPath;
  }

  const candidates = [
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  ];

  return candidates.find((candidate) => fs.existsSync(candidate)) || "";
}

function sanitizeProxyEnv(env) {
  const nextEnv = { ...env };
  const proxyKeys = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"];
  for (const key of proxyKeys) {
    if (nextEnv[key] !== undefined) {
      delete nextEnv[key];
    }
  }
  return nextEnv;
}

function patchBundledViewer() {
  const viewerIndexPath = path.resolve(toolsDir, "node_modules/@vivliostyle/viewer/lib/index.html");
  if (!fs.existsSync(viewerIndexPath)) {
    return;
  }

  const original = fs.readFileSync(viewerIndexPath, "utf8");
  const remoteScript = '<script src="https://wicg.github.io/visual-viewport/polyfill/visualViewport.js"></script>';
  if (!original.includes(remoteScript)) {
    return;
  }

  const replacement = `<script>
      if (typeof window.visualViewport === "undefined") {
        window.visualViewport = {
          width: window.innerWidth,
          height: window.innerHeight,
          offsetLeft: 0,
          offsetTop: 0,
          pageLeft: 0,
          pageTop: 0,
          scale: 1,
          addEventListener() {},
          removeEventListener() {},
        };
      }
    </script>`;

  fs.writeFileSync(viewerIndexPath, original.replace(remoteScript, replacement), "utf8");
}

async function main() {
  const args = process.argv.slice(2);
  const browserPath = resolveBrowserPath();
  const cliPath = path.resolve(toolsDir, "node_modules/.bin/vivliostyle.cmd");
  const forwardedArgs = [...args];
  patchBundledViewer();

  if (
    browserPath &&
    !forwardedArgs.includes("--executable-browser") &&
    !forwardedArgs.includes("--browser")
  ) {
    forwardedArgs.push("--executable-browser", browserPath);
  }

  const child = spawn("cmd.exe", ["/c", cliPath, ...forwardedArgs], {
    stdio: "inherit",
    shell: false,
    env: sanitizeProxyEnv(process.env),
  });

  child.on("exit", (code) => {
    process.exitCode = code ?? 1;
  });
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
