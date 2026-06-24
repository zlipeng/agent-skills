---
name: swagger-explorer
description: |
  Efficiently parse a Swagger/OpenAPI JSON spec — given either a direct api-docs URL or a Swagger UI URL — and look up specific endpoints without loading the whole document into context.
  TRIGGER when: the user gives a Swagger / OpenAPI / api-docs URL, OR a Swagger UI URL (containing `/swagger-ui/`, `urls.primaryName=`, or a `#/<tag>/<operationId>` hash), OR a cached id, and asks to list, search, or inspect endpoints — "解析 swagger" / "看一下这个接口" / "swagger UI 里这个接口的入参" / "find the login endpoint in this swagger" / "what does POST /order/create return".
  DO NOT TRIGGER for: hand-written API docs (Markdown / Postman / Apifox exports), questions about an OpenAPI spec already inlined in the repo, or generic "how do I call this API" questions where no spec URL is provided.
---

# Swagger Explorer

Parse large Swagger 2.0 / OpenAPI 3.x JSON specs without ever loading the full document into the agent context. Accepts both raw `api-docs` JSON URLs and Swagger UI URLs (auto-resolving the UI URL into its backing JSON via `/v3/api-docs/swagger-config` or `/swagger-resources`). Backed by `jq` and a local cache, so a 1900-endpoint, 2 MB spec answers a single-endpoint query in milliseconds and returns a few KB.

## When to use
- The user pastes a `*/api-docs` (or `*/v3/api-docs`, `*/v2/api-docs`) JSON URL and wants to know what's in it.
- The user pastes a Swagger UI URL — e.g. `…/swagger-ui/index.html?urls.primaryName=auth#/sc-role-controller/getApionAuthRoleList` — and wants the interface that page shows.
- The user asks for the request / response shape of a specific path (e.g. `/api/order/create`) or operationId (e.g. `getApionAuthRoleList`) from such a spec.
- The user is wiring up a frontend against an unfamiliar backend and needs to scan its endpoints by keyword, tag, or method.

Skip this skill when the spec is already a small inline file in the repo — just `Read` it.

## Architecture (one-liner)

```
input URL ──resolve.sh──► json_url (+ group / tag / operationId hints, if input was a UI URL)
                          │
                          ▼
                    fetch.sh ──► ~/.cache/swagger-skill/<sha1>.json          (full spec, on disk)
                                 ~/.cache/swagger-skill/<sha1>.index.json    (lightweight: paths + summary + tags + operationId)
                                 ~/.cache/swagger-skill/<sha1>.meta.json     (url, fetched_at)

list.sh   ──► reads index only                       (cheap browse)
search.sh ──► reads index only                       (cheap keyword filter)
get.sh    ──► reads full spec + $ref                 (one endpoint, inlined, ~few KB)
              also supports --op <operationId>       (resolves via the index)
```

The agent never `cat`s the cached `<id>.json` itself — always go through `get.sh`, which extracts and inlines just the requested operation.

## Workflow

### 0. (Optional) Inspect what a Swagger UI URL really points at

```bash
bash skills/swagger-explorer/scripts/resolve.sh '<ui-or-json-url>'
# →  json_url=<resolved api-docs URL>
#    group=<config name from urls.primaryName, if any>
#    tag=<from the URL hash, if any>
#    operation_id=<from the URL hash, if any>
#    source=ui|json
```

`fetch.sh` already calls `resolve.sh` internally, so step 0 is just for debugging. The resolver works for both Springdoc (OpenAPI 3.x, `/v3/api-docs/swagger-config`) and Springfox (Swagger 2.0, `/swagger-resources`) layouts.

### 1. Fetch (once per URL)

```bash
bash skills/swagger-explorer/scripts/fetch.sh <url>          # uses cache if <24h old
bash skills/swagger-explorer/scripts/fetch.sh <url> --refresh # force re-download
```

`<url>` can be either a JSON URL or a Swagger UI URL. Output is line-oriented `key=value` — parse `id=` (the handle for every other command), and when present, `tag=` / `operation_id=` (free hints carried over from a UI URL):

```
id=77f356f46eae21d33b4e187f4748f7a31beb1da9
file=/Users/.../.cache/swagger-skill/<id>.json
index=/Users/.../.cache/swagger-skill/<id>.index.json
version=swagger                # or "openapi"
title=plus-auth
path_count=602
cached=false                   # true if served from cache
source_url=https://.../swagger/auth/v2/api-docs
ui_url=https://.../swagger-ui/index.html?urls.primaryName=auth#/sc-role-controller/getApionAuthRoleList
group=auth                     # only when input was a UI URL with urls.primaryName
tag=sc-role-controller         # only when input URL had a #/<tag>/... fragment
operation_id=getApionAuthRoleList   # only when input URL had a #/<tag>/<op> fragment
```

Cache: `~/.cache/swagger-skill/` (override with `SWAGGER_SKILL_CACHE`). TTL: 24 h (`SWAGGER_SKILL_TTL`, seconds).

### 2. Browse or search (index only — always cheap)

```bash
# List: filter by tag and/or method, paginate.
bash .../list.sh <id> [--tag <tag>] [--method GET|POST|...] [--limit 200] [--format table|json|paths]

# Search: case-insensitive substring against path / summary / operationId / tags.
bash .../search.sh <id> <keyword> [--limit 100] [--format table|json|paths]
```

Default `--format table` is human-readable. Use `--format paths` when you want a clean `METHOD path` list to pipe into the next step, or `--format json` when you want to do further filtering in your own jq.

### 3. Get one endpoint (full definition, `$ref`s inlined)

Two lookup modes — by path, or by operationId:

```bash
# By path:
bash .../get.sh <id> <path> [--method GET|POST|...] [--depth 3] [--raw]

# By operationId (preferred when input came from a Swagger UI URL,
# since the UI hash encodes operationId, not path):
bash .../get.sh <id> --op <operationId> [--depth 3] [--raw]
```

- Without `--method`: returns the whole path-item (every method on that path).
- `--depth N`: how many `$ref` hops to follow (default 3; raise it for deeply nested DTOs, lower it to keep output small).
- `--raw`: skip `$ref` resolution entirely.
- `--op` resolves the operationId via the lightweight index, then proceeds the same way as a path lookup. If multiple endpoints share the operationId (rare but legal), it returns an `{error: "operationId is ambiguous", matches: [...]}` so you can pick one.

Handles both Swagger 2.0 (`#/definitions/...`) and OpenAPI 3.x (`#/components/schemas/...`, `parameters`, `responses`, `requestBodies`). External `$ref`s (non-`#/...`) are left verbatim so the caller can spot them.

Output is one JSON object:

```json
{
  "path": "/api/order/create",
  "method": "POST",
  "definition": { /* operation object with $refs inlined */ }
}
```

If the path / method / operationId is missing, `definition` (or the top-level object) becomes `{"error": "...", "available": [...]}` — surface that to the user instead of pretending.

## End-to-end examples

### A) User pastes a raw JSON URL

User: *"看下 `https://api.example.com/v2/api-docs` 里 `/api/project/add` 的入参"*

```bash
# 1. Cache the spec, capture the id.
eval "$(bash .../scripts/fetch.sh https://api.example.com/v2/api-docs | grep '^id=')"
# → $id is now exported as a shell variable

# 2. Pull the one endpoint, with body schema inlined.
bash .../scripts/get.sh "$id" /api/project/add --method POST
```

### B) User pastes a Swagger UI URL

User: *"分析 `https://api.example.com/swagger-ui/index.html?urls.primaryName=auth#/sc-role-controller/getApionAuthRoleList`"*

```bash
# 1. fetch.sh detects it's a UI URL, resolves to the JSON URL, and surfaces
#    the operationId from the fragment.
out="$(bash .../scripts/fetch.sh 'https://api.example.com/swagger-ui/index.html?urls.primaryName=auth#/sc-role-controller/getApionAuthRoleList')"
id="$(printf '%s\n' "$out" | awk -F= '/^id=/{print $2}')"
op="$(printf '%s\n' "$out" | awk -F= '/^operation_id=/{print $2}')"

# 2. Look the operation up directly by operationId — no extra search needed.
bash .../scripts/get.sh "$id" --op "$op"
```

Report back to the user: parameters / request body / responses, in their language, citing the spec URL — **not** a paste of the entire JSON.

## Operational notes

- **Stay out of the cache files.** Never `Read` or `cat` `<id>.json` directly; it can be tens of MB. The whole point of this skill is to avoid that. Always go through `get.sh`.
- **`$ref` cycles.** `--depth` caps recursion; cyclic schemas are auto-stopped at the depth limit (the deepest layer remains as the raw `{$ref: ...}` object).
- **UI URL resolution failures.** If the host serves a custom Swagger UI shell that doesn't expose `/v3/api-docs/swagger-config` or `/swagger-resources`, `resolve.sh` falls back to `<origin>/swagger/<group>/v2/api-docs` when a `urls.primaryName=<group>` is present. If even that 404s, ask the user for the JSON URL directly.
- **YAML specs / non-JSON sources.** This skill only parses JSON. If a URL serves YAML, convert it first (`yq -o json` → save under the cache id) or ask the user for the JSON variant — most Springfox / SpringDoc / FastAPI endpoints already return JSON.
- **Authenticated swagger.** `fetch.sh` and `resolve.sh` are plain `curl`. If the spec is behind auth, ask the user to provide a header or a pre-downloaded file path instead of guessing credentials.
- **Refresh policy.** When the user says "接口好像变了" / "the spec was updated", re-run `fetch.sh --refresh` before answering.

## References

- See `references/jq-cookbook.md` for ready-made jq snippets (group by tag, count by method, find endpoints with no `operationId`, dump all referenced schemas, etc.).
- See `references/openapi-v2-v3.md` for the structural differences between Swagger 2.0 and OpenAPI 3.x that this skill smooths over.

