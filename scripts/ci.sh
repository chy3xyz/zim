#!/usr/bin/env bash
# ZIM CI gate — one command, fail-fast on any step.
#
# zigmodu's `zmodu ci` expects a `src/tools` layout for fmt/deadcode, so zim
# runs its own gate: build → tests → fmt → zmodu audit → zmodu deadcode.
#
# Usage: scripts/ci.sh [--zmodu /path/to/zmodu]
set -euo pipefail

cd "$(dirname "$0")/../src"

ZM="${ZM:-}"
if [ -z "$ZM" ]; then
  # Prefer a locally-built zmodu (v0.15.3+ has audit/deadcode), else PATH.
  if [ -x ../.zmodu-build/bin/zmodu ]; then
    ZM=../.zmodu-build/bin/zmodu
  else
    ZM=zmodu
  fi
fi

echo "== [1/5] zig build"
zig build

echo "== [2/5] zig build test"
zig build test > /dev/null 2>&1 || { echo "test step failed"; exit 1; }

echo "== [3/5] zig fmt --check"
zig fmt --check build.zig main.zig core.zig tests.zig modules/ proto/

echo "== [4/6] zmodu audit"
"$ZM" audit .

echo "== [5/6] zmodu deadcode"
"$ZM" deadcode .

echo "== [6/6] smoke: boot + /health"
# Catches startup-only crashes (e.g. libpq result UAF surfaced at boot) that
# unit tests never reach.
./zig-out/bin/zim > /tmp/zim-ci-smoke.log 2>&1 &
ZIM_PID=$!
for _ in $(seq 1 20); do
  if curl -sf http://localhost:10000/health > /dev/null 2>&1; then break; fi
  sleep 0.5
done
if ! curl -sf http://localhost:10000/health > /dev/null 2>&1; then
  echo "smoke failed — server did not become healthy"
  kill "$ZIM_PID" 2>/dev/null || true
  exit 1
fi
kill "$ZIM_PID" 2>/dev/null || true
wait "$ZIM_PID" 2>/dev/null || true

echo "== CI PASS (all gates green)"
