#!/usr/bin/env bash
set -euo pipefail

# Warren — Build .rbxm package
# Requires: rojo (https://github.com/rojo-rbx/rojo)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${SCRIPT_DIR}/Warren.rbxm"
PROJECT="${SCRIPT_DIR}/default.project.json"

# Check for rojo
if ! command -v rojo &>/dev/null; then
    echo "[!!] rojo not found — install with: aftman add rojo-rbx/rojo"
    exit 1
fi

echo "[..] Building Warren.rbxm..."
rojo build "${PROJECT}" -o "${OUTPUT}"

SIZE=$(stat -c%s "${OUTPUT}" 2>/dev/null || stat -f%z "${OUTPUT}" 2>/dev/null)
SIZE_KB=$((SIZE / 1024))
echo "[ok] Warren.rbxm built — ${SIZE_KB} KB"
