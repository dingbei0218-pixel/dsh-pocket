#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test: mock DeepSeek SSE -> dsh CLI -> tool call -> final answer.
# Requires: Swift 6+, Node 18+.

PORT="${PORT:-18081}"
WORKDIR="$(mktemp -d)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
  if [[ -n "${MOCK_PID:-}" ]]; then
    kill "$MOCK_PID" 2>/dev/null || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$WORKDIR/ws" "$WORKDIR/sessions"
printf 'hello from mock\n' > "$WORKDIR/ws/hello.txt"

node "$ROOT/scripts/mock-deepseek.mjs" "$PORT" &
MOCK_PID=$!
sleep 1

cd "$ROOT"
DEEPSEEK_API_KEY=test swift run dsh run "read hello.txt and tell me what it says" \
  -C "$WORKDIR/ws" \
  --base-url "http://127.0.0.1:$PORT" \
  --preset danger \
  --root "$WORKDIR/sessions"

echo
echo "--- sessions ---"
DEEPSEEK_API_KEY=test swift run dsh sessions --root "$WORKDIR/sessions"
