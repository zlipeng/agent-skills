#!/usr/bin/env bash
# registry.sh - maintain and query a "path-prefix -> swagger URL" registry.
#
# The registry lets the agent fetch a spec when the user provides only an API
# path (e.g. "/api/order/create") and no swagger URL: the longest registered
# prefix that is a prefix of the input path wins, and its URL is used.
#
# Storage: $SWAGGER_SKILL_CACHE/registry.json (default ~/.cache/swagger-skill/).
# The file is created on first write. It is plain JSON so users may edit it by
# hand; this script is the preferred interface.
#
# Usage:
#   registry.sh add    <prefix> <url> [--source manual|auto]
#   registry.sh remove <prefix>
#   registry.sh list   [--format table|json]
#   registry.sh lookup <path-or-prefix>
#   registry.sh path
#
# lookup output (key=value lines, easy for the agent to parse):
#   matched=true  prefix=/api/order  url=https://...        # hit
#   matched=false                                            # miss (exit 0)
#
# add/remove output: a short confirmation on stdout.

set -euo pipefail

CACHE_DIR="${SWAGGER_SKILL_CACHE:-$HOME/.cache/swagger-skill}"
REGISTRY="$CACHE_DIR/registry.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- helpers ----------

# Ensure the registry file exists with a valid skeleton. Safe to call always.
ensure_registry() {
  if [[ ! -s "$REGISTRY" ]]; then
    mkdir -p "$CACHE_DIR"
    jq -n '{version:1, entries:[]}' > "$REGISTRY"
  fi
}

# Atomically rewrite the registry by applying a jq filter on the current file.
# Usage: write_registry '<jq program>' [extra jq args...]
write_registry() {
  local prog="$1"; shift
  ensure_registry
  local tmp
  tmp="$(mktemp "$CACHE_DIR/.reg.XXXXXX")"
  if ! jq "$prog" "$@" "$REGISTRY" > "$tmp"; then
    rm -f "$tmp"
    echo "registry.sh: failed to update $REGISTRY" >&2
    exit 1
  fi
  mv "$tmp" "$REGISTRY"
}

# ---------- subcommands ----------

cmd_add() {
  local prefix="${1:-}" url="${2:-}" source="${3:-manual}"
  if [[ -z "$prefix" || -z "$url" ]]; then
    echo "usage: registry.sh add <prefix> <url> [--source manual|auto]" >&2
    exit 2
  fi
  case "$source" in
    manual|auto) ;;
    --source) source="${4:-manual}";;  # tolerate `--source X` form
    *) echo "registry.sh: invalid source '$source' (use manual|auto)" >&2; exit 2;;
  esac
  local now
  now="$(date -u +%FT%TZ)"
  # Upsert by prefix: drop any existing entry with the same prefix, then append.
  # `additional` params passed via --arg.
  write_registry '
    .entries = (.entries | map(select(.prefix != $p)))
      + [{prefix:$p, url:$u, source:$s, added_at:$t}]
    | .entries |= sort_by(.prefix)
  ' --arg p "$prefix" --arg u "$url" --arg s "$source" --arg t "$now"
  echo "added prefix=$prefix url=$url source=$source"
}

cmd_remove() {
  local prefix="${1:-}"
  if [[ -z "$prefix" ]]; then
    echo "usage: registry.sh remove <prefix>" >&2
    exit 2
  fi
  ensure_registry
  local had
  had="$(jq --arg p "$prefix" '[.entries[] | select(.prefix==$p)] | length' "$REGISTRY")"
  write_registry '.entries |= map(select(.prefix != $p))' --arg p "$prefix"
  if [[ "$had" == "0" ]]; then
    echo "removed prefix=$prefix (was not present)"
  else
    echo "removed prefix=$prefix"
  fi
}

cmd_list() {
  local format="table"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format) format="$2"; shift 2;;
      *) echo "registry.sh list: unknown arg: $1" >&2; exit 2;;
    esac
  done
  ensure_registry
  case "$format" in
    json)
      jq '.entries' "$REGISTRY"
      ;;
    table|*)
      jq -r '
        ["PREFIX","URL","SOURCE","ADDED_AT"],
        ["------","---","------","---------"],
        (.entries[] | [.prefix, .url, .source, .added_at])
        | @tsv
      ' "$REGISTRY" | column -t -s $'\t'
      ;;
  esac
}

# Lookup: longest registered prefix that is a prefix of the input.
# Input may be a full path ("/api/order/create") or a prefix ("/api/order").
cmd_lookup() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    echo "usage: registry.sh lookup <path-or-prefix>" >&2
    exit 2
  fi
  ensure_registry
  # Among entries whose $prefix is a prefix of $input, pick the longest prefix.
  local hit
  hit="$(jq -r --arg in "$input" '
    [.entries[] | select(.prefix as $p | $in | startswith($p))]
    | sort_by(.prefix) | reverse | .[0] // null
    | if . == null then "matched=false"
      else "matched=true\tprefix=\(.prefix)\turl=\(.url)"
      end
  ' "$REGISTRY")"
  if [[ "$hit" == "matched=false" ]]; then
    echo "matched=false"
    exit 0
  fi
  # Re-emit as key=value lines.
  printf 'matched=true\n'
  printf '%s\t' "$hit" | cut -f2- | tr '\t' '\n'
}

cmd_path() {
  ensure_registry
  echo "$REGISTRY"
}

# ---------- dispatch ----------

SUB="${1:-}"
shift || true
case "$SUB" in
  add)    cmd_add "$@";;
  remove) cmd_remove "$@";;
  list)   cmd_list "$@";;
  lookup) cmd_lookup "$@";;
  path)   cmd_path;;
  ""|-h|--help)
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    echo ""
    echo "Subcommands: add | remove | list | lookup | path"
    ;;
  *) echo "registry.sh: unknown subcommand '$SUB'" >&2; exit 2;;
esac
