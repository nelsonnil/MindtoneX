#!/usr/bin/env bash
# Sincroniza media/MagicCall, docs/magic-call-poc y MagicCall.zip en el Project Agent Store.
# Copia espejo con rsync (sin rm -rf: el store es FUSE y otro agente puede estar leyendo),
# zip atómico y verificación final con diff. No lances dos sincronizaciones a la vez.
set -euo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STORE="${1:-/cursor/stores/bc-2e8d8979-5707-4d1d-88d4-83c9aab4bf2d}"
ITEMS=(.gitignore project.yml README.md MagicCall MagicCall.xcodeproj)

mirror() {
  local dest="$1"
  mkdir -p "$dest"
  for item in "${ITEMS[@]}"; do
    if [ -d "$WS/$item" ]; then
      rsync -r --delete --checksum --no-perms --no-times --omit-dir-times \
        --exclude='.DS_Store' --exclude='xcuserdata' "$WS/$item/" "$dest/$item/"
    else
      cp -f "$WS/$item" "$dest/$item"
    fi
  done
}

verify() {
  local dest="$1"
  diff -rq -x '.DS_Store' -x xcuserdata "$WS/MagicCall" "$dest/MagicCall"
  diff -rq -x '.DS_Store' -x xcuserdata "$WS/MagicCall.xcodeproj" "$dest/MagicCall.xcodeproj"
  for f in .gitignore project.yml README.md; do diff -q "$WS/$f" "$dest/$f"; done
}

mirror "$STORE/media/MagicCall"
mirror "$STORE/docs/magic-call-poc"

tmp="$(mktemp -d)"
mkdir -p "$tmp/MagicCall"
tar cf - -C "$WS" --exclude='.DS_Store' --exclude='xcuserdata' "${ITEMS[@]}" | tar xf - -C "$tmp/MagicCall"
( cd "$tmp" && zip -qr "$tmp/MagicCall.zip" MagicCall -x '*.DS_Store' -x '*/xcuserdata/*' )
cp "$tmp/MagicCall.zip" "$STORE/media/MagicCall.zip.new"
mv -f "$STORE/media/MagicCall.zip.new" "$STORE/media/MagicCall.zip"
rm -rf "$tmp"

verify "$STORE/media/MagicCall"
verify "$STORE/docs/magic-call-poc"
build="$(grep -m1 'CURRENT_PROJECT_VERSION' "$WS/project.yml" | tr -dc '0-9')"
zipped="$(unzip -p "$STORE/media/MagicCall.zip" MagicCall/project.yml | grep -m1 'CURRENT_PROJECT_VERSION' | tr -dc '0-9')"
[ "$build" = "$zipped" ]
echo "Synced store MagicCall layout and zip (build $build, verified)."
