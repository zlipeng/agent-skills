# Swagger 2.0 vs OpenAPI 3.x — what this skill smooths over

`fetch.sh` detects the spec version (`.openapi` present → `openapi`; `.swagger` present → `swagger`) and records it in the index as `.version`. The other scripts mostly don't care, but if you need to write custom jq against the cached `<id>.json`, here are the differences that bite.

## Top-level shape

| Concern | Swagger 2.0 | OpenAPI 3.x |
|---|---|---|
| Version marker | `"swagger": "2.0"` | `"openapi": "3.x.y"` |
| Server / host | `host`, `basePath`, `schemes[]` | `servers: [{url, variables}]` |
| Consumes / produces (global) | `consumes`, `produces` | per-operation `requestBody.content` and `responses[*].content` |

## Where schemas live

| Kind | Swagger 2.0 pointer | OpenAPI 3.x pointer |
|---|---|---|
| Model schemas | `#/definitions/<Name>` | `#/components/schemas/<Name>` |
| Reusable params | `#/parameters/<Name>` | `#/components/parameters/<Name>` |
| Reusable responses | `#/responses/<Name>` | `#/components/responses/<Name>` |
| Request bodies | (no separate object — params with `in: body`) | `#/components/requestBodies/<Name>` |
| Security schemes | `securityDefinitions` | `#/components/securitySchemes/...` |

`get.sh` resolves all of the above by traversing the JSON pointer literally, so it works for both formats without a version switch.

## Request bodies

- **Swagger 2.0:** the body is a `parameters[]` entry with `in: "body"` and a `schema`. Form/multipart fields are individual `in: "formData"` parameters.
- **OpenAPI 3.x:** there is a dedicated `requestBody` object; its `content` maps media types to schemas.

When summarizing for the user, normalize to: *"this endpoint takes `<media type>` body shaped like `<schema>`"*.

## Responses

- **Swagger 2.0:** `responses[<code>].schema`, plus a global `produces`.
- **OpenAPI 3.x:** `responses[<code>].content[<media>].schema`.

Always extract the schema for `200`/`201`/`default` and ignore the media-type wrapping when the user just asks "what does it return".

## Path parameters

Identical in both: `{name}` in the path string and a matching `parameters[]` entry with `in: "path"`.

## What this skill deliberately ignores

- **YAML inputs** — convert to JSON first (`yq -o json input.yaml`).
- **External `$ref`s** (refs without a leading `#/`). `get.sh` leaves them verbatim so the agent can flag them; resolving cross-document refs would require fetching more URLs and bypassing the cache.
- **`allOf` / `oneOf` / `anyOf` flattening.** The inliner preserves these as-is — they're meaningful for clients and shouldn't be silently merged.
