#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

dist="$project_root/web/dist"
case "$dist" in
  "$project_root"/web/dist) ;;
  *) echo "Refusing to replace unexpected output directory: $dist" >&2; exit 1 ;;
esac

moon build web/wasm --target wasm --release
rm -rf -- "$dist"
mkdir -p "$dist"
cp -R web/site/. "$dist/"
cp _build/wasm/release/build/web/wasm/wasm.wasm "$dist/photo_privacy.wasm"

echo "Web build ready: $project_root/web/dist"
