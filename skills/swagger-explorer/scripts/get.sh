#!/usr/bin/env bash
# get.sh — fetch a single endpoint's definition with $ref schemas inlined.
#
# Usage:
#   get.sh <id> <path> [--method <GET|POST|...>] [--depth N] [--raw]
#   get.sh <id> --op <operationId>       [--depth N] [--raw]
#
# Lookup modes:
#   - by path (default): looks up `paths[<path>]`. If --method is given, returns
#     just that operation; otherwise returns the whole path-item.
#   - by operationId (--op): scans every (path, method) for a matching
#     `operationId`. Useful when the user came from a Swagger UI URL whose
#     fragment encodes `#/<tag>/<operationId>` rather than a path.
#
# Other flags:
#   - --depth N: how many $ref hops to follow (default 3). Works for both
#     Swagger 2.0 ($/definitions/X) and OpenAPI 3.x
#     ($/components/schemas/X, parameters/X, responses/X, requestBodies/X).
#     External / remote $refs (no leading #) are left as-is.
#   - --raw: skip $ref inlining and return the endpoint exactly as in the spec.
#
# Output: JSON on stdout.

set -euo pipefail

ID="${1:-}"
shift || true

if [[ -z "$ID" ]]; then
  echo "usage: get.sh <id> <path> [--method M] [--depth N] [--raw]" >&2
  echo "       get.sh <id> --op <operationId> [--depth N] [--raw]" >&2
  exit 2
fi

ENDPOINT_PATH=""
OP_LOOKUP=""
# If the next arg isn't a flag, treat it as <path> for backwards compatibility.
if [[ $# -gt 0 && "$1" != --* ]]; then
  ENDPOINT_PATH="$1"
  shift
fi

METHOD=""
DEPTH="3"
RAW="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) METHOD="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; shift 2;;
    --depth)  DEPTH="$2"; shift 2;;
    --raw)    RAW="true"; shift;;
    --op)     OP_LOOKUP="$2"; shift 2;;
    *) echo "get.sh: unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$ENDPOINT_PATH" && -z "$OP_LOOKUP" ]]; then
  echo "get.sh: must provide either <path> or --op <operationId>" >&2
  exit 2
fi

CACHE_DIR="${SWAGGER_SKILL_CACHE:-$HOME/.cache/swagger-skill}"
FILE="$CACHE_DIR/$ID.json"

if [[ ! -s "$FILE" ]]; then
  echo "get.sh: no cached spec for id=$ID — run fetch.sh <url> first" >&2
  exit 1
fi

# If --op was given (and no explicit path), resolve operationId → (path, method)
# from the index so we can keep the main jq program path-driven.
if [[ -n "$OP_LOOKUP" && -z "$ENDPOINT_PATH" ]]; then
  INDEX="$CACHE_DIR/$ID.index.json"
  if [[ ! -s "$INDEX" ]]; then
    echo "get.sh: missing index for id=$ID — run fetch.sh again" >&2
    exit 1
  fi
  MATCH="$(jq -r --arg op "$OP_LOOKUP" '
    [.endpoints[] | select(.operationId == $op)] as $hits
    | if ($hits | length) == 0 then "NONE"
      elif ($hits | length) > 1 then
        "MANY\t" + (($hits | map(.method + " " + .path)) | join(" | "))
      else
        "ONE\t" + $hits[0].method + "\t" + $hits[0].path
      end
  ' "$INDEX")"
  case "$MATCH" in
    NONE)
      jq -n --arg op "$OP_LOOKUP" '{error:"operationId not found", operationId:$op}'
      exit 0
      ;;
    MANY*)
      jq -n --arg op "$OP_LOOKUP" --arg hits "${MATCH#MANY	}" \
        '{error:"operationId is ambiguous", operationId:$op, matches:($hits|split(" | "))}'
      exit 0
      ;;
    ONE*)
      rest="${MATCH#ONE	}"
      M_METHOD="${rest%%	*}"
      M_PATH="${rest#*	}"
      ENDPOINT_PATH="$M_PATH"
      METHOD="$(printf '%s' "$M_METHOD" | tr '[:upper:]' '[:lower:]')"
      ;;
  esac
fi

# jq program:
#   1. extract the path item (or one method on it)
#   2. recursively resolve every $ref encountered, up to $depth hops, by
#      looking the pointer up in the original $spec.
#
# $ref formats handled:
#   "#/definitions/X"            (Swagger 2.0)
#   "#/components/schemas/X"     (OpenAPI 3.x)
#   "#/components/parameters/X"
#   "#/components/responses/X"
#   "#/components/requestBodies/X"
# External / remote $refs (no leading #) are left as-is and surfaced verbatim.

jq --arg path "$ENDPOINT_PATH" \
   --arg method "$METHOD" \
   --argjson depth "$DEPTH" \
   --argjson raw "$([[ $RAW == true ]] && echo true || echo false)" '
  . as $spec
  |
  # ---- resolver: turn "#/a/b/c" into the value at $spec.a.b.c ----
  def resolve_ptr($ref):
    if ($ref | startswith("#/")) then
      ($ref | sub("^#/"; "") | split("/") | map(gsub("~1"; "/") | gsub("~0"; "~"))) as $parts
      | $spec | getpath($parts)
    else
      null   # external $ref — leave for the caller to handle
    end;

  # ---- recursive walker that inlines $refs up to $d levels deep ----
  def inline($d):
    if $d < 0 then .
    elif type == "object" then
      if has("$ref") and ((."$ref" | type) == "string") then
        resolve_ptr(."$ref") as $target
        | if $target == null then .                 # external ref
          else $target | inline($d - 1)
          end
      else
        with_entries(.value |= inline($d))
      end
    elif type == "array" then
      map(inline($d))
    else .
    end;

  # ---- pick the endpoint ----
  (.paths[$path] // null) as $item
  | if $item == null then
      {error: "path not found", path: $path}
    else
      ( if $method == "" then $item
        else ($item[$method] // {error:"method not found", method:$method, available:($item|keys)})
        end
      ) as $selected
      | {
          path: $path,
          method: (if $method == "" then null else ($method | ascii_upcase) end),
          definition: (if $raw then $selected else ($selected | inline($depth)) end)
        }
    end
' "$FILE"
