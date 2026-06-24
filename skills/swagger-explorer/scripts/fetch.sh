#!/usr/bin/env bash
# fetch.sh — download a Swagger/OpenAPI JSON doc, cache it, and build a lightweight index.
#
# Usage:
#   fetch.sh <url> [--refresh]
#
# <url> may be either:
#   - a direct api-docs JSON URL                  (e.g. .../v2/api-docs)
#   - a Swagger UI URL                            (e.g. .../swagger-ui/index.html?urls.primaryName=auth#/<tag>/<op>)
# In the UI case, fetch.sh delegates to resolve.sh to discover the real JSON
# URL via /v3/api-docs/swagger-config or /swagger-resources, and surfaces any
# tag / operationId hints from the URL fragment in its output.
#
# Output (stdout, one key=value per line — easy for the agent to parse):
#   id=<sha1>
#   file=<absolute path to cached full spec>
#   index=<absolute path to lightweight index>
#   version=<swagger|openapi>
#   title=<API title>
#   path_count=<number>
#   cached=<true|false>   # whether this run used an existing cache
#   source_url=<the JSON URL that was actually downloaded>
#   ui_url=<original UI URL, only set when input was a UI URL>
#   group=<config name from urls.primaryName, only set for UI URLs>
#   tag=<hash tag, only set if present in input URL>
#   operation_id=<hash operationId, only set if present in input URL>
#
# The cache lives at ~/.cache/swagger-skill/<sha1(json_url)>.{json,index.json}.
# Default TTL: 24h. Pass --refresh to force a re-download.

set -euo pipefail

INPUT_URL="${1:-}"
REFRESH="${2:-}"

if [[ -z "$INPUT_URL" ]]; then
  echo "usage: fetch.sh <url> [--refresh]" >&2
  exit 2
fi

# Resolve UI URLs → JSON URL (no-op for direct JSON URLs).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_OUT="$(bash "$SCRIPT_DIR/resolve.sh" "$INPUT_URL")"

URL="$(printf '%s\n' "$RESOLVE_OUT" | awk -F= '/^json_url=/{print substr($0, index($0,"=")+1)}')"
SOURCE="$(printf '%s\n' "$RESOLVE_OUT" | awk -F= '/^source=/{print $2}')"
GROUP="$(printf '%s\n' "$RESOLVE_OUT" | awk -F= '/^group=/{print $2}')"
TAG="$(printf '%s\n' "$RESOLVE_OUT" | awk -F= '/^tag=/{print $2}')"
OP_ID="$(printf '%s\n' "$RESOLVE_OUT" | awk -F= '/^operation_id=/{print $2}')"

if [[ -z "$URL" ]]; then
  echo "fetch.sh: resolve.sh did not return a json_url for '$INPUT_URL'" >&2
  exit 1
fi

CACHE_DIR="${SWAGGER_SKILL_CACHE:-$HOME/.cache/swagger-skill}"
mkdir -p "$CACHE_DIR"

# sha1 of the URL → stable cache id
if command -v shasum >/dev/null 2>&1; then
  ID="$(printf '%s' "$URL" | shasum -a 1 | awk '{print $1}')"
else
  ID="$(printf '%s' "$URL" | sha1sum | awk '{print $1}')"
fi

FILE="$CACHE_DIR/$ID.json"
INDEX="$CACHE_DIR/$ID.index.json"
META="$CACHE_DIR/$ID.meta.json"
TTL_SECONDS="${SWAGGER_SKILL_TTL:-86400}"

needs_refresh() {
  [[ "$REFRESH" == "--refresh" ]] && return 0
  [[ ! -s "$FILE" ]] && return 0
  [[ ! -s "$INDEX" ]] && return 0
  # mtime-based TTL (portable between GNU and BSD stat)
  local mtime now age
  if stat -f %m "$FILE" >/dev/null 2>&1; then
    mtime="$(stat -f %m "$FILE")"
  else
    mtime="$(stat -c %Y "$FILE")"
  fi
  now="$(date +%s)"
  age=$(( now - mtime ))
  (( age > TTL_SECONDS ))
}

CACHED="true"
if needs_refresh; then
  CACHED="false"
  # Use a temp file so a failed download doesn't corrupt the cache.
  TMP="$(mktemp "$CACHE_DIR/.dl.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  if ! curl -fsSL --compressed -H 'Accept: application/json' "$URL" -o "$TMP"; then
    echo "fetch.sh: download failed for $URL" >&2
    exit 1
  fi
  # Validate it's JSON before committing to the cache.
  if ! jq -e . "$TMP" >/dev/null 2>&1; then
    echo "fetch.sh: response is not valid JSON" >&2
    exit 1
  fi
  mv "$TMP" "$FILE"
  trap - EXIT
fi

# (Re)build the lightweight index every time we materialize the full file.
# The index contains: spec version, info, server/host, and a flat array of
# { method, path, summary, tags, operationId } — enough to browse without
# loading the full spec.
if [[ ! -s "$INDEX" || "$CACHED" == "false" ]]; then
  jq '
    def is_method: . == "get" or . == "post" or . == "put" or . == "delete"
                 or . == "patch" or . == "options" or . == "head";
    {
      version: (if has("openapi") then "openapi" else "swagger" end),
      spec_version: (.openapi // .swagger // "unknown"),
      title: (.info.title // ""),
      api_version: (.info.version // ""),
      host: (.host // (.servers[0].url? // "")),
      basePath: (.basePath // ""),
      tag_count: ((.tags // []) | length),
      tags: ([(.tags // [])[] | {name, description: (.description // "")}]),
      path_count: (.paths | length),
      endpoints: [
        .paths as $p
        | $p | to_entries[] as $pe
        | $pe.value | to_entries[]
        | select(.key | ascii_downcase | is_method)
        | {
            method: (.key | ascii_upcase),
            path: $pe.key,
            summary: (.value.summary // ""),
            operationId: (.value.operationId // ""),
            tags: (.value.tags // []),
            deprecated: (.value.deprecated // false)
          }
      ]
    }
  ' "$FILE" > "$INDEX"
fi

# Stash a tiny meta record so other scripts can find the source URL by id.
jq -n --arg url "$URL" --arg id "$ID" \
      --arg fetched_at "$(date -u +%FT%TZ)" \
  '{id:$id, url:$url, fetched_at:$fetched_at}' > "$META"

VERSION="$(jq -r '.version' "$INDEX")"
TITLE="$(jq -r '.title' "$INDEX")"
PATH_COUNT="$(jq -r '.path_count' "$INDEX")"

cat <<EOF
id=$ID
file=$FILE
index=$INDEX
version=$VERSION
title=$TITLE
path_count=$PATH_COUNT
cached=$CACHED
source_url=$URL
EOF

# Surface UI-only fields when they apply, so downstream callers can chain
# `get.sh --op <operation_id>` without re-parsing the original URL.
if [[ "$SOURCE" == "ui" ]]; then
  echo "ui_url=$INPUT_URL"
  [[ -n "$GROUP" ]] && echo "group=$GROUP" || true
fi
[[ -n "$TAG"   ]] && echo "tag=$TAG"             || true
[[ -n "$OP_ID" ]] && echo "operation_id=$OP_ID"  || true
