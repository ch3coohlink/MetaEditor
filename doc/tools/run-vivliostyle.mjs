import { spawn } from "node:child_process";
import process from "node:process";
import path from "node:path";
import fs from "node:fs";

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
  for (const key of ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"]) {
    const value = nextEnv[key];
    if (typeof value === "string" && value.startsWith("socks://")) {
      delete nextEnv[key];
    }
  }
  return nextEnv;
}

const args = process.argv.slice(2);
const browserPath = resolveBrowserPath();
const cliPath = path.resolve(process.cwd(), "node_modules/.bin/vivliostyle.cmd");
const forwardedArgs = [...args];

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
