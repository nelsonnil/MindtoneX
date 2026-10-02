#!/usr/bin/env bash
# Sincroniza media/MagicCall, docs/magic-call-poc y MagicCall.zip en el Project Agent Store.
set -euo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STORE="${1:-/cursor/stores/bc-2e8d8979-5707-4d1d-88d4-83c9aab4bf2d}"

sync_repo_layout() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  tar cf - -C "$WS" \
    --exclude='.DS_Store' \
    --exclude='**/xcuserdata' \
    --exclude='**/xcuserdata/**' \
    .gitignore project.yml README.md MagicCall MagicCall.xcodeproj \
    | tar xf - -C "$dest"
}

sync_repo_layout "$STORE/media/MagicCall"
sync_repo_layout "$STORE/docs/magic-call-poc"

tmp="$(mktemp -d)"
mkdir -p "$tmp/MagicCall"
tar cf - -C "$STORE/media/MagicCall" . | tar xf - -C "$tmp/MagicCall"
rm -f "$STORE/media/MagicCall.zip"
( cd "$tmp" && zip -qr "$STORE/media/MagicCall.zip" MagicCall -x '*.DS_Store' -x '*/xcuserdata/*' )
rm -rf "$tmp"
echo "Synced store MagicCall layout and zip."
