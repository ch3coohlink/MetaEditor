#!/usr/bin/env bash
set -euo pipefail

name="${1-}"
if [[ -z "$name" ]]; then
  echo 'usage: ./run.sh <script> [args...]' >&2
  exit 1
fi

script="scripts/$name.js"
if [[ ! -f "$script" ]]; then
  echo "script not found: $script" >&2
  exit 1
fi

shift
node "$script" "$@"
