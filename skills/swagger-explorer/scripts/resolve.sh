#!/usr/bin/env bash
# resolve.sh — turn any Swagger URL (UI or raw JSON) into a concrete JSON
# spec URL, plus any tag / operationId hints encoded in the UI URL.
#
# Usage:
#   resolve.sh <url>
#
# Output (stdout, key=value lines):
#   json_url=<absolute URL of the api-docs JSON>
#   group=<config-name (e.g. "auth"), empty if not a multi-group UI>
#   tag=<tag from the UI hash, empty if absent>
#   operation_id=<operationId from the UI hash, empty if absent>
#   source=<json|ui>
#
# Heuristics:
#   - If the URL contains "/swagger-ui" OR a "urls.primaryName=" query OR a
#     "#/<tag>/<op>" hash, treat it as a Swagger UI URL.
#   - Otherwise treat the URL as already pointing at the JSON spec.
#
# UI URL resolution order (first hit wins):
#   1. Springdoc (OpenAPI 3.x):   <origin>/v3/api-docs/swagger-config
#   2. Springfox (Swagger 2.0):   <origin>/swagger-resources
#   3. Fallback heuristic:         <origin>/swagger/<group>/v2/api-docs
#                                  (only used when --fallback is given OR the
#                                   above endpoints all 404)

set -euo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "usage: resolve.sh <url>" >&2
  exit 2
fi

# ---------- tiny URL parser ----------
# We only need scheme://host[:port], the query string, and the fragment.
proto="${URL%%://*}"
rest="${URL#*://}"
hostpath="${rest%%\?*}"
hostpath="${hostpath%%\#*}"
host="${hostpath%%/*}"
ORIGIN="$proto://$host"

# Extract `urls.primaryName=...` from the query string (if any).
query=""
if [[ "$URL" == *"?"* ]]; then
  query="${URL#*\?}"
  # drop fragment if it followed the query
  query="${query%%\#*}"
fi
fragment=""
if [[ "$URL" == *"#"* ]]; then
  fragment="${URL#*\#}"
fi

# Pull a single query param (no urldecode beyond %2F → /).
qparam() {
  local key="$1" raw=""
  [[ -z "$query" ]] && return
  IFS='&' read -ra parts <<<"$query"
  for kv in "${parts[@]:-}"; do
    [[ -z "$kv" ]] && continue
    if [[ "$kv" == "$key="* ]]; then
      raw="${kv#$key=}"
      # minimal decoding sufficient for typical primaryName values
      raw="${raw//%2F/\/}"
      raw="${raw//%20/ }"
      printf '%s' "$raw"
      return
    fi
  done
}

GROUP="$(qparam urls.primaryName)"

# Parse fragment "#/<tag>/<operationId>" (Swagger UI hash format).
TAG=""
OP_ID=""
if [[ -n "$fragment" ]]; then
  # strip leading "/" if present
  frag="${fragment#/}"
  TAG="${frag%%/*}"
  rest_frag="${frag#*/}"
  if [[ "$rest_frag" != "$frag" ]]; then
    OP_ID="${rest_frag%%/*}"
  fi
fi

# Is this a UI URL?
is_ui=false
case "$URL" in
  *"/swagger-ui"*) is_ui=true ;;
esac
[[ -n "$GROUP" || -n "$TAG" ]] && is_ui=true

if ! $is_ui; then
  # Already a JSON URL — emit as-is.
  cat <<EOF
json_url=$URL
group=
tag=$TAG
operation_id=$OP_ID
source=json
EOF
  exit 0
fi

# ---------- UI URL: resolve via swagger-config / swagger-resources ----------

# Try Springdoc first (OpenAPI 3.x).
CONFIG_JSON=""
for cfg in "/v3/api-docs/swagger-config" "/swagger-resources"; do
  body="$(curl -fsSL --compressed --max-time 10 -H 'Accept: application/json' "$ORIGIN$cfg" 2>/dev/null || true)"
  if [[ -n "$body" ]] && printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    CONFIG_JSON="$body"
    CONFIG_PATH="$cfg"
    break
  fi
done

JSON_URL=""
if [[ -n "$CONFIG_JSON" ]]; then
  # Springdoc shape:   { "urls": [ { "name": "...", "url": "..." }, ... ] }
  # Springfox shape:   [ { "name": "...", "url": "...", "location": "..." }, ... ]
  if printf '%s' "$CONFIG_JSON" | jq -e 'type=="object" and has("urls")' >/dev/null 2>&1; then
    if [[ -n "$GROUP" ]]; then
      JSON_URL="$(printf '%s' "$CONFIG_JSON" | jq -r --arg g "$GROUP" '.urls[] | select(.name==$g) | .url' | head -n1)"
    fi
    if [[ -z "$JSON_URL" ]]; then
      # Single-group UI or no primaryName given — take the first entry.
      JSON_URL="$(printf '%s' "$CONFIG_JSON" | jq -r '.urls[0].url // empty')"
    fi
  elif printf '%s' "$CONFIG_JSON" | jq -e 'type=="array"' >/dev/null 2>&1; then
    if [[ -n "$GROUP" ]]; then
      JSON_URL="$(printf '%s' "$CONFIG_JSON" | jq -r --arg g "$GROUP" '.[] | select(.name==$g) | (.url // .location)' | head -n1)"
    fi
    if [[ -z "$JSON_URL" ]]; then
      JSON_URL="$(printf '%s' "$CONFIG_JSON" | jq -r '.[0] | (.url // .location) // empty')"
    fi
  fi
fi

# Last-ditch heuristic for sites that ship a custom UI shell but follow the
# common <origin>/swagger/<group>/v2/api-docs convention.
if [[ -z "$JSON_URL" && -n "$GROUP" ]]; then
  JSON_URL="/swagger/$GROUP/v2/api-docs"
fi

if [[ -z "$JSON_URL" ]]; then
  echo "resolve.sh: could not resolve a JSON spec URL from '$URL'" >&2
  echo "  tried /v3/api-docs/swagger-config and /swagger-resources on $ORIGIN" >&2
  exit 1
fi

# Make absolute.
case "$JSON_URL" in
  http://*|https://*) ABS="$JSON_URL" ;;
  /*)                 ABS="$ORIGIN$JSON_URL" ;;
  *)                  ABS="$ORIGIN/$JSON_URL" ;;
esac

cat <<EOF
json_url=$ABS
group=$GROUP
tag=$TAG
operation_id=$OP_ID
source=ui
EOF
