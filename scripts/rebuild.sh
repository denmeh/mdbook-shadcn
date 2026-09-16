#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONF="$ROOT/upstream.conf"
WORK="$ROOT/work/mdbook"
PATCHES="$ROOT/patches"

if [[ ! -d "$WORK/.git" ]]; then
  echo "error: $WORK is missing; run ./scripts/apply.sh first" >&2
  exit 1
fi

sha=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  key="${line%%=*}"
  value="${line#*=}"
  case "$key" in
    sha) sha="$value" ;;
  esac
done <"$CONF"

if [[ -z "$sha" ]]; then
  echo "error: upstream.conf must set sha=" >&2
  exit 1
fi

if ! git -C "$WORK" cat-file -e "$sha^{commit}" 2>/dev/null; then
  echo "error: pinned sha $sha is not in $WORK" >&2
  exit 1
fi

mkdir -p "$PATCHES"
find "$PATCHES" -maxdepth 1 -name '*.patch' -delete

echo "Rebuilding patches from $sha"
git -C "$WORK" format-patch "$sha" -o "$PATCHES"
echo "Wrote patches to $PATCHES"
