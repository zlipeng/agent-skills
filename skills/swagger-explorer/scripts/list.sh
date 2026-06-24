#!/usr/bin/env bash
# list.sh — list endpoints from a cached Swagger/OpenAPI doc.
#
# Usage:
#   list.sh <id> [--tag <tag>] [--method <GET|POST|...>] [--limit N] [--format table|json|paths]
#
# Defaults: --format table, --limit 200.
# Reads ONLY the lightweight index, never the full spec, so this is safe to call
# even on multi-megabyte swagger files.

set -euo pipefail

ID="${1:-}"
shift || true

if [[ -z "$ID" ]]; then
  echo "usage: list.sh <id> [--tag T] [--method M] [--limit N] [--format table|json|paths]" >&2
  exit 2
fi

TAG=""
METHOD=""
LIMIT="200"
FORMAT="table"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)    TAG="$2"; shift 2;;
    --method) METHOD="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"; shift 2;;
    --limit)  LIMIT="$2"; shift 2;;
    --format) FORMAT="$2"; shift 2;;
    *) echo "list.sh: unknown arg: $1" >&2; exit 2;;
  esac
done

CACHE_DIR="${SWAGGER_SKILL_CACHE:-$HOME/.cache/swagger-skill}"
INDEX="$CACHE_DIR/$ID.index.json"

if [[ ! -s "$INDEX" ]]; then
  echo "list.sh: no cached index for id=$ID — run fetch.sh <url> first" >&2
  exit 1
fi

# Filter endpoints in jq, then format in the chosen output mode.
FILTERED="$(jq --arg tag "$TAG" --arg method "$METHOD" --argjson limit "$LIMIT" '
  .endpoints
  | map(select(
      ($tag == "" or (.tags | index($tag)))
      and ($method == "" or .method == $method)
    ))
  | .[0:$limit]
' "$INDEX")"

TOTAL="$(jq '.endpoints | length' "$INDEX")"
SHOWN="$(printf '%s' "$FILTERED" | jq 'length')"

case "$FORMAT" in
  json)
    printf '%s\n' "$FILTERED"
    ;;
  paths)
    printf '%s' "$FILTERED" | jq -r '.[] | "\(.method) \(.path)"'
    ;;
  table|*)
    printf '%s' "$FILTERED" | jq -r '
      ["METHOD","PATH","TAGS","SUMMARY"],
      ["------","----","----","-------"],
      (.[] | [
        .method,
        .path,
        ((.tags // []) | join(",")),
        (.summary | gsub("\n"; " ") | .[0:80])
      ])
      | @tsv
    ' | column -t -s $'\t'
    echo ""
    echo "shown=$SHOWN total=$TOTAL"
    ;;
esac
