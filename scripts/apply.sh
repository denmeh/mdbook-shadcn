#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONF="$ROOT/upstream.conf"
WORK="$ROOT/work/mdbook"
PATCHES="$ROOT/patches"
STAMP="$ROOT/work/.applied"

FORCE=0
STATUS_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --status) STATUS_ONLY=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: apply.sh [--status] [--force]

  (default)  Apply patches if the work tree is missing or out of date.
  --status   Show whether patches are already applied; do not change anything.
  --force    Wipe work/mdbook back to upstream and replay every patch.

Already-applied trees are left alone so local edits and unexported commits
are not deleted. Use --force only when you intend to throw that away.
EOF
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$CONF" ]]; then
  echo "error: missing $CONF" >&2
  exit 1
fi

repo=""
ref=""
sha=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  key="${line%%=*}"
  value="${line#*=}"
  case "$key" in
    repo) repo="$value" ;;
    ref) ref="$value" ;;
    sha) sha="$value" ;;
  esac
done <"$CONF"

if [[ -z "$repo" || -z "$sha" ]]; then
  echo "error: upstream.conf must set repo= and sha=" >&2
  exit 1
fi

shopt -s nullglob
patch_files=("$PATCHES"/*.patch)
shopt -u nullglob

patch_digest() {
  if ((${#patch_files[@]} == 0)); then
    printf 'none\n'
    return
  fi
  sha256sum "${patch_files[@]}" | sha256sum | awk '{print $1}'
}

DIGEST="$(patch_digest)"

work_ready() {
  [[ -d "$WORK/.git" ]] && git -C "$WORK" cat-file -e "$sha^{commit}" 2>/dev/null
}

is_ancestor() {
  git -C "$WORK" merge-base --is-ancestor "$sha" HEAD 2>/dev/null
}

applied_count() {
  if work_ready && is_ancestor; then
    git -C "$WORK" rev-list --count "$sha"..HEAD
  else
    printf '0\n'
  fi
}

stamp_matches() {
  [[ -f "$STAMP" ]] || return 1
  local stamped_sha stamped_digest
  stamped_sha=""
  stamped_digest=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      sha) stamped_sha="$value" ;;
      digest) stamped_digest="$value" ;;
    esac
  done <"$STAMP"
  [[ "$stamped_sha" == "$sha" && "$stamped_digest" == "$DIGEST" ]]
}

write_stamp() {
  mkdir -p "$ROOT/work"
  cat >"$STAMP" <<EOF
sha=$sha
digest=$DIGEST
EOF
}

print_status() {
  local count
  count="$(applied_count)"
  echo "upstream: ${ref:-?} ($sha)"
  echo "patch files: ${#patch_files[@]}"
  if ! work_ready; then
    echo "work tree: missing (run ./scripts/apply.sh)"
    return
  fi
  echo "commits on top of upstream: $count"
  if stamp_matches && is_ancestor; then
    echo "state: applied"
  elif is_ancestor && ((count == ${#patch_files[@]})); then
    echo "state: applied (no stamp yet, inferred from commit count)"
  elif is_ancestor && ((count > ${#patch_files[@]})); then
    echo "state: applied, plus $((count - ${#patch_files[@]})) unexported commit(s) — run ./scripts/rebuild.sh"
  else
    echo "state: not applied / out of date"
  fi
  if is_ancestor && ((count > 0)); then
    echo
    echo "applied:"
    git -C "$WORK" log --oneline --reverse "$sha"..HEAD
  fi
}

dirty_or_unexported() {
  if ! work_ready; then
    return 1
  fi
  if [[ -n "$(git -C "$WORK" status --porcelain)" ]]; then
    return 0
  fi
  local count
  count="$(applied_count)"
  ((count > ${#patch_files[@]}))
}

ensure_clone() {
  mkdir -p "$ROOT/work"
  if [[ ! -d "$WORK/.git" ]]; then
    echo "Cloning $repo into $WORK"
    git clone "$repo" "$WORK"
  fi
  git -C "$WORK" remote set-url origin "$repo"
  if ! git -C "$WORK" config user.email >/dev/null; then
    git -C "$WORK" config user.name "mdbook-shadcn"
    git -C "$WORK" config user.email "mdbook-shadcn@local"
  fi
}

if ((STATUS_ONLY)); then
  print_status
  exit 0
fi

ensure_clone

if ((FORCE == 0)) && work_ready && is_ancestor && stamp_matches; then
  echo "Patches already applied; nothing to do."
  print_status
  echo
  echo "Use ./scripts/apply.sh --force to wipe the work tree and replay."
  exit 0
fi

# Infer "already applied" from commit count only when there is no stamp yet.
# If a stamp exists but does not match, patches or the pin changed and we must replay.
if ((FORCE == 0)) && [[ ! -f "$STAMP" ]] && work_ready && is_ancestor && ((${#patch_files[@]} == $(applied_count))); then
  write_stamp
  echo "Patches already applied; recorded stamp."
  print_status
  echo
  echo "Use ./scripts/apply.sh --force to wipe the work tree and replay."
  exit 0
fi

if ((FORCE == 0)) && dirty_or_unexported; then
  echo "error: work/mdbook has uncommitted changes or unexported commits." >&2
  echo "Commit and run ./scripts/rebuild.sh, or re-run with --force (destroys local work)." >&2
  print_status
  exit 1
fi

echo "Fetching $repo"
git -C "$WORK" fetch --tags origin

echo "Checking out ${ref:-$sha} ($sha)"
git -C "$WORK" checkout --detach "$sha"
git -C "$WORK" reset --hard "$sha"
git -C "$WORK" clean -fd -e target

if ((${#patch_files[@]} == 0)); then
  write_stamp
  echo "No patches to apply."
  exit 0
fi

echo "Applying ${#patch_files[@]} patch(es)"
git -C "$WORK" am --3way "${patch_files[@]}"
write_stamp
echo "Patches applied."
print_status
