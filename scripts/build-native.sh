#!/usr/bin/env sh
set -eu

PACKAGE="${1:-service}"
MODE="${2:-}"

if ! command -v clang >/dev/null 2>&1; then
  echo 'clang not found in PATH' >&2
  exit 1
fi

export CC=clang

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo '[native] clang version'
clang --version

echo "[native] moon build --target native $PACKAGE"
moon build --target native "$PACKAGE"

if [ "$MODE" = '--test' ]; then
  echo "[native] moon test --target native $PACKAGE"
  moon test --target native "$PACKAGE"
fi
