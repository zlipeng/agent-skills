# jq cookbook for swagger-explorer

These run against the cached **index** (`<id>.index.json`, small) unless noted. The full spec lives at `<id>.json` — only touch it for `$ref` resolution.

Find the cache files:

```bash
CACHE_DIR="${SWAGGER_SKILL_CACHE:-$HOME/.cache/swagger-skill}"
INDEX="$CACHE_DIR/<id>.index.json"
FILE="$CACHE_DIR/<id>.json"
```

## Counts

Endpoints per HTTP method:

```bash
jq '.endpoints | group_by(.method) | map({method: .[0].method, count: length})' "$INDEX"
```

Endpoints per tag:

```bash
jq '
  .endpoints
  | map({tag: (.tags // ["(untagged)"])[]?, path: .path})
  | group_by(.tag)
  | map({tag: .[0].tag, count: length})
  | sort_by(-.count)
' "$INDEX"
```

Deprecated endpoints:

```bash
jq '.endpoints | map(select(.deprecated)) | .[] | "\(.method) \(.path)"' -r "$INDEX"
```

## Hygiene

Endpoints with no `operationId` (annoying for client codegen):

```bash
jq -r '.endpoints[] | select(.operationId == "") | "\(.method) \(.path)"' "$INDEX"
```

Endpoints with no summary:

```bash
jq -r '.endpoints[] | select(.summary == "") | "\(.method) \(.path)"' "$INDEX"
```

## Path-pattern filtering

Only `GET`s under `/api/order/...`:

```bash
jq -r '
  .endpoints[]
  | select(.method == "GET" and (.path | startswith("/api/order/")))
  | "\(.method) \(.path)"
' "$INDEX"
```

Endpoints whose path has a path parameter:

```bash
jq -r '.endpoints[] | select(.path | test("\\{[^}]+\\}")) | "\(.method) \(.path)"' "$INDEX"
```

## Schema dumps (uses the full spec)

List every definition name (Swagger 2.0):

```bash
jq -r '.definitions | keys[]' "$FILE"
```

List every schema name (OpenAPI 3.x):

```bash
jq -r '.components.schemas | keys[]' "$FILE"
```

Find every endpoint that references a given DTO (Swagger 2.0 example):

```bash
DTO=ProjectAddDTO
jq -r --arg dto "$DTO" '
  .paths
  | to_entries[] as $pe
  | $pe.value
  | to_entries[]
  | select(.value | tostring | contains("#/definitions/" + $dto))
  | "\(.key|ascii_upcase) \($pe.key)"
' "$FILE"
```

(For OpenAPI 3.x, swap `#/definitions/` for `#/components/schemas/`.)

## One-off endpoint inspection without `get.sh`

If you need raw access (e.g. for debugging `get.sh`):

```bash
jq '.paths["/api/project/add"]' "$FILE"
```

Don't paste this output back to the user verbatim — it may include unresolved `$ref`s and irrelevant operations. Prefer `get.sh`.
