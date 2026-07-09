#!/usr/bin/env bash
# fetch.sh — download a Swagger/OpenAPI JSON doc, cache it, and build a lightweight index.
#
# Usage:
#   fetch.sh <url> [--refresh]
#   fetch.sh --path <api-path> [--refresh]   # resolve URL via the registry
#
# <url> may be either:
#   - a direct api-docs JSON URL                  (e.g. .../v2/api-docs)
#   - a Swagger UI URL                            (e.g. .../swagger-ui/index.html?urls.primaryName=auth#/<tag>/<op>)
# In the UI case, fetch.sh delegates to resolve.sh to discover the real JSON
# URL via /v3/api-docs/swagger-config or /swagger-resources, and surfaces any
# tag / operationId hints from the URL fragment in its output.
#
# When --path <api-path> is given instead of a URL, fetch.sh looks up the
# longest registered path-prefix in the registry (registry.sh lookup) and uses
# that entry's URL. This serves the "user gave only an API path, no swagger
# URL" case. On a successful fetch, the discovered prefix -> URL mapping is
# also (re)registered automatically (unless SWAGGER_SKILL_AUTOREGISTER=0).
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
#   registry_matched=true    # only set when the URL came from registry lookup
#   registry_prefix=<prefix> # only set when the URL came from registry lookup
#
# The cache lives at ~/.cache/swagger-skill/<sha1(json_url)>.{json,index.json}.
# Default TTL: 24h. Pass --refresh to force a re-download.

set -euo pipefail

INPUT_URL=""
REFRESH=""
REGISTRY_PATH=""

# Parse args. Supported forms:
#   fetch.sh <url> [--refresh]
#   fetch.sh --path <api-path> [--refresh]   # resolve URL via registry.sh lookup
while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh) REFRESH="--refresh"; shift;;
    --path)    REGISTRY_PATH="$2"; shift 2;;
    *)         INPUT_URL="$1"; shift;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If no URL was given, try to resolve one from the registry by API path prefix.
REGISTRY_PREFIX=""
if [[ -z "$INPUT_URL" ]]; then
  if [[ -z "$REGISTRY_PATH" ]]; then
    echo "usage: fetch.sh <url> [--refresh]" >&2
    echo "       fetch.sh --path <api-path> [--refresh]   # resolve URL via registry" >&2
    exit 2
  fi
  LOOKUP_OUT="$(bash "$SCRIPT_DIR/registry.sh" lookup "$REGISTRY_PATH")"
  MATCHED="$(printf '%s\n' "$LOOKUP_OUT" | awk -F= '/^matched=/{print $2}')"
  if [[ "$MATCHED" != "true" ]]; then
    echo "fetch.sh: no registry entry matches path '$REGISTRY_PATH'" >&2
    echo "  register one with: registry.sh add <prefix> <swagger-url>" >&2
    exit 1
  fi
  INPUT_URL="$(printf '%s\n' "$LOOKUP_OUT" | awk -F= '/^url=/{print substr($0, index($0,"=")+1)}')"
  REGISTRY_PREFIX="$(printf '%s\n' "$LOOKUP_OUT" | awk -F= '/^prefix=/{print $2}')"
fi

# Resolve UI URLs -> JSON URL (no-op for direct JSON URLs).
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

# Auto-register the spec's common path-prefix -> URL mapping, so future calls
# that only give an API path can resolve via registry.sh. We derive the prefix
# as the longest common prefix of the spec's endpoint paths, truncated to the
# last "/". Skip if the prefix is too short (fewer than 2 path segments, e.g.
# "/" or "/api") to avoid over-broad registrations.
AUTOREGISTER="${SWAGGER_SKILL_AUTOREGISTER:-1}"
if [[ "$AUTOREGISTER" == "1" ]]; then
  DERIVED_PREFIX="$(jq -r '
    [.endpoints[].path] as $paths
    | (if ($paths | length) == 0 then ""
       else
         ($paths | sort)[0] as $first
         | ($paths | sort)[-1] as $last
         | reduce range(0; ($first | length)) as $i (
             ""; . + (if ($first[$i:$i+1] == $last[$i:$i+1]) then $first[$i:$i+1] else "" end)
           )
         | sub("/[^/]*$"; "")   # truncate to last "/"
       end)
  ' "$INDEX" 2>/dev/null || true)"
  SEGMENT_COUNT="$(printf '%s' "$DERIVED_PREFIX" | awk -F/ '{print NF}')"
  # e.g. "/api/order" -> split by "/" gives ["", "api", "order"] -> NF=3
  if [[ -n "$DERIVED_PREFIX" && "$SEGMENT_COUNT" -ge 3 ]]; then
    # Check for an existing entry with this prefix; never overwrite a manual one.
    EXISTING="$(bash "$SCRIPT_DIR/registry.sh" lookup "$DERIVED_PREFIX/" 2>/dev/null || true)"
    EXISTING_PREFIX="$(printf '%s\n' "$EXISTING" | awk -F= '/^prefix=/{print $2}')"
    EXISTING_URL="$(printf '%s\n' "$EXISTING" | awk -F= '/^url=/{print substr($0, index($0,"=")+1)}')"
    if [[ -z "$EXISTING_PREFIX" ]]; then
      bash "$SCRIPT_DIR/registry.sh" add "$DERIVED_PREFIX" "$INPUT_URL" --source auto >/dev/null 2>&1 || true
      REGISTRY_PREFIX="$DERIVED_PREFIX"
    elif [[ "$EXISTING_URL" != "$URL" && "$EXISTING_PREFIX" == "$DERIVED_PREFIX" ]]; then
      # Same prefix, different URL - do not clobber; only note it.
      echo "fetch.sh: registry already has prefix='$DERIVED_PREFIX' -> '$EXISTING_URL' (not overwritten)" >&2
    fi
  fi
fi

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

# Surface registry-hit info when the URL came from a registry lookup or was
# auto-registered this run.
if [[ -n "$REGISTRY_PREFIX" ]]; then
  echo "registry_matched=true"
  echo "registry_prefix=$REGISTRY_PREFIX"
fi

# Surface UI-only fields when they apply, so downstream callers can chain
# `get.sh --op <operation_id>` without re-parsing the original URL.
if [[ "$SOURCE" == "ui" ]]; then
  echo "ui_url=$INPUT_URL"
  [[ -n "$GROUP" ]] && echo "group=$GROUP" || true
fi
[[ -n "$TAG"   ]] && echo "tag=$TAG"             || true
[[ -n "$OP_ID" ]] && echo "operation_id=$OP_ID"  || true
