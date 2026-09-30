#!/bin/sh
# Usage: drive.sh [PAGE] [OUT_DIR]   e.g. drive.sh /app/accounts/1/contacts /tmp/shots
# Screenshot lands at $OUT_DIR/shot.png (default /tmp/chatwoot-shots/shot.png).
set -e
SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
OUT_DIR=${2:-/tmp/chatwoot-shots}
mkdir -p "$OUT_DIR"
docker run --rm --network host \
  -e PAGE="${1:-/app/accounts/1/dashboard}" -e OUT=/out/shot.png \
  -v "$SKILL_DIR":/driver:ro -v "$OUT_DIR":/out -v chatwoot-pw-deps:/deps \
  mcr.microsoft.com/playwright:v1.55.0-noble \
  sh -c 'cd /deps && { [ -d node_modules/playwright ] || npm i -s playwright@1.55.0 >/dev/null 2>&1; } && cp /driver/driver.mjs . && node driver.mjs'
