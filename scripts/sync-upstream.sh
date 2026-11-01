#!/usr/bin/env bash
# Keep pstack-rex in step with upstream pstack (cursor/plugins).
#
#   scripts/sync-upstream.sh [SHA]   merge upstream from the pinned commit to SHA (default: upstream main)
#   scripts/sync-upstream.sh --layer print the Rex layer: every change from upstream at the pin to skills/
#   scripts/sync-upstream.sh --status list upstream commits since the pin that touch the mapped paths
#
# UPSTREAM holds the pin (`sha=`) and the path map (`map=<upstream path> <repo path>`, longest prefix wins).
# A sync is a three-way merge per file, with `git merge-file`: base is upstream at the pin, ours is the
# file in this repo, theirs is upstream at SHA. Files the port never touched fast-forward, and only lines
# both sides changed conflict. New upstream files are added, files upstream deleted are deleted when the
# port left them alone. Every other case is listed for a human. Then the pin moves to SHA and the Rex
# checker runs over the skills that changed, because new upstream text can name a Cursor mechanism
# (REX-NATIVE.md says how to translate it). Exit 1 means conflicts or checker findings are left.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PIN_FILE=$ROOT/UPSTREAM
CACHE=${PSTACK_REX_UPSTREAM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/pstack-rex/plugins}

repo_url=$(sed -n 's/^repo=//p' "$PIN_FILE")
pin=$(sed -n 's/^sha=//p' "$PIN_FILE")
MAPS=$(sed -n 's/^map=//p' "$PIN_FILE")
[ -n "$repo_url" ] && [ -n "$pin" ] && [ -n "$MAPS" ] || { echo "UPSTREAM needs repo=, sha= and map= lines" >&2; exit 2; }

fetch() {
  if [ ! -d "$CACHE/.git" ]; then
    mkdir -p "$(dirname "$CACHE")"
    git clone --quiet --no-checkout "$repo_url" "$CACHE"
  fi
  git -C "$CACHE" fetch --quiet origin
}

upstream_paths() { printf '%s\n' "$MAPS" | awk '{print $1}'; }

to_repo() { # upstream path -> repo path, by the longest matching map prefix
  printf '%s\n' "$MAPS" | awk -v p="$1" '
    { if (index(p, $1) == 1 && length($1) > best) { best = length($1); out = $2 substr(p, length($1) + 1) } }
    END { if (best) print out }'
}

list_files() { # sha -> upstream files under the mapped paths
  local path
  for path in $(upstream_paths); do git -C "$CACHE" ls-tree -r --name-only "$1" -- "$path"; done | sort -u
}

blob() { git -C "$CACHE" show "$1:$2"; }

cmd_layer() {
  fetch
  local tmp f r
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/upstream" "$tmp/rex"
  for f in $(list_files "$pin"); do
    r=$(to_repo "$f")
    mkdir -p "$tmp/upstream/$(dirname "$r")"
    blob "$pin" "$f" >"$tmp/upstream/$r"
  done
  # Only what git would track: ignored files such as node_modules are not part of the layer
  (cd "$ROOT" && git ls-files --cached --others --exclude-standard -- skills) | while IFS= read -r r; do
    [ -f "$ROOT/$r" ] || continue
    mkdir -p "$tmp/rex/$(dirname "$r")"
    cp "$ROOT/$r" "$tmp/rex/$r"
  done
  # Rex additions show as new files, upstream files the port removed as deletions
  (cd "$tmp" && git diff --no-index --stat=200 -- upstream rex) || true
  (cd "$tmp" && git diff --no-index -- upstream rex) || true
}

cmd_status() {
  fetch
  git -C "$CACHE" log --oneline "$pin..origin/HEAD" -- $(upstream_paths)
}

cmd_sync() {
  local target=${1:-}
  fetch
  [ -n "$target" ] || target=$(git -C "$CACHE" rev-parse origin/HEAD)
  target=$(git -C "$CACHE" rev-parse --verify "$target^{commit}")
  if [ "$target" = "$pin" ]; then echo "already at $pin"; return 0; fi
  echo "sync $pin..$target"
  git -C "$CACHE" log --oneline "$pin..$target" -- $(upstream_paths) | sed 's/^/  /'

  local tmp f r ours conflicts=0 touched="" notes=""
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  for f in $( { list_files "$pin"; list_files "$target"; } | sort -u); do
    r=$(to_repo "$f")
    [ -n "$r" ] || continue
    ours=$ROOT/$r
    local in_base=0 in_theirs=0
    git -C "$CACHE" cat-file -e "$pin:$f" 2>/dev/null && in_base=1
    git -C "$CACHE" cat-file -e "$target:$f" 2>/dev/null && in_theirs=1
    if [ $in_base = 1 ] && [ $in_theirs = 1 ]; then
      [ "$(git -C "$CACHE" rev-parse "$pin:$f")" = "$(git -C "$CACHE" rev-parse "$target:$f")" ] && continue
      if [ ! -e "$ours" ]; then notes="$notes\n  upstream changed $f, which the port removed ($r)"; continue; fi
      blob "$pin" "$f" >"$tmp/base"
      blob "$target" "$f" >"$tmp/theirs"
      if git merge-file -L ours -L "upstream@${pin:0:7}" -L "upstream@${target:0:7}" "$ours" "$tmp/base" "$tmp/theirs"; then
        echo "  merged    $r"
      else
        echo "  CONFLICT  $r"
        conflicts=$((conflicts + 1))
      fi
    elif [ $in_theirs = 1 ]; then
      if [ -e "$ours" ]; then
        : >"$tmp/empty"
        blob "$target" "$f" >"$tmp/theirs"
        git merge-file -L ours -L empty -L "upstream@${target:0:7}" "$ours" "$tmp/empty" "$tmp/theirs" || true
        echo "  CONFLICT  $r (added on both sides)"
        conflicts=$((conflicts + 1))
      else
        mkdir -p "$(dirname "$ours")"
        blob "$target" "$f" >"$ours"
        echo "  added     $r"
      fi
    else
      [ -e "$ours" ] || continue
      blob "$pin" "$f" >"$tmp/base"
      if cmp -s "$tmp/base" "$ours"; then
        rm "$ours"
        echo "  deleted   $r"
      else
        notes="$notes\n  upstream deleted $f, which the port changed: decide by hand ($r)"
      fi
    fi
    case $r in skills/*) touched="$touched $(printf '%s' "$r" | cut -d/ -f2)" ;; esac
  done

  sed -i.bak "s/^sha=.*/sha=$target/" "$PIN_FILE" && rm -f "$PIN_FILE.bak"
  echo "pinned UPSTREAM to $target"
  [ -n "$notes" ] && printf "needs a human:$notes\n"

  local checked=0
  touched=$(printf '%s\n' $touched | sort -u | tr '\n' ' ')
  if [ -n "${touched// /}" ]; then
    echo "checking:$touched"
    node "$ROOT/scripts/check-rex-native.mjs" $touched || checked=1
  fi
  if [ $conflicts -gt 0 ] || [ $checked = 1 ] || [ -n "$notes" ]; then
    echo "next: resolve conflict markers, translate checker findings per REX-NATIVE.md, run the script tests, commit"
    return 1
  fi
  echo "next: run the script tests (bun test in skills/poteto-mode/scripts) and commit"
}

case ${1:-} in
  --layer) cmd_layer ;;
  --status) cmd_status ;;
  -h | --help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  -*) echo "unknown option $1" >&2; exit 2 ;;
  *) cmd_sync "${1:-}" ;;
esac
