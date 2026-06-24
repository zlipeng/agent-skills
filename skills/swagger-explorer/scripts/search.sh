#!/usr/bin/env bash
# search.sh — find endpoints by keyword (path / summary / operationId / tag).
#
# Usage:
#   search.sh <id> <keyword> [--limit N] [--format table|json|paths]
#
# Case-insensitive substring match against path, summary, operationId, and tags.
# Only reads the lightweight index — safe for huge specs.

set -euo pipefail

ID="${1:-}"
KEYWORD="${2:-}"
shift 2 || true

if [[ -z "$ID" || -z "$KEYWORD" ]]; then
  echo "usage: search.sh <id> <keyword> [--limit N] [--format table|json|paths]" >&2
  exit 2
fi

LIMIT="100"
FORMAT="table"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)  LIMIT="$2"; shift 2;;
    --format) FORMAT="$2"; shift 2;;
    *) echo "search.sh: unknown arg: $1" >&2; exit 2;;
  esac
done

CACHE_DIR="${SWAGGER_SKILL_CACHE:-$HOME/.cache/swagger-skill}"
INDEX="$CACHE_DIR/$ID.index.json"

if [[ ! -s "$INDEX" ]]; then
  echo "search.sh: no cached index for id=$ID — run fetch.sh <url> first" >&2
  exit 1
fi

FILTERED="$(jq --arg q "$KEYWORD" --argjson limit "$LIMIT" '
  ($q | ascii_downcase) as $needle
  | .endpoints
  | map(select(
      ((.path           // "") | ascii_downcase | contains($needle)) or
      ((.summary        // "") | ascii_downcase | contains($needle)) or
      ((.operationId    // "") | ascii_downcase | contains($needle)) or
      (((.tags // []) | map(ascii_downcase) | any(contains($needle))))
    ))
  | .[0:$limit]
' "$INDEX")"

HITS="$(printf '%s' "$FILTERED" | jq 'length')"

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
    echo "hits=$HITS keyword=$KEYWORD"
    ;;
esac
