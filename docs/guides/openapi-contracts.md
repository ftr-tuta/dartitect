# Bounded OpenAPI 3.1 contracts

`dartitect contracts check|sync` consumes only JSON or YAML files below the
project root. Local `$ref` targets must remain below that root after canonical
path resolution. The command never performs a network request, resolves a URL,
loads executable code, or runs an OpenAPI security scheme.

## Workflow

```console
dartitect contracts check api/openapi.yaml --json
dartitect contracts check api/openapi.yaml \
  --baseline=api/openapi.previous.yaml --json
dartitect contracts sync api/openapi.yaml \
  --output=lib/contracts/api.contracts.dartitect.g.dart --dry-run
dartitect contracts sync api/openapi.yaml \
  --output=lib/contracts/api.contracts.dartitect.g.dart --apply
```

`check` validates and classifies the current contract without writing. `sync`
previews by default; `--apply` revalidates and transactionally converges one
manifest-owned `*.dartitect.g.dart` output. A baseline comparison reports
additive and breaking changes separately from invalid input.

## Supported closure

The bounded renderer accepts OpenAPI 3.1 objects, arrays, enums, `required`,
nullable unions, `allOf`, and discriminator-based `oneOf`. It supports
path/query/header parameters and JSON request/response bodies. Generated output
contains typed DTOs, bounded JSON codecs, route templates, endpoint
descriptors/clients, status mappings, and deterministic fixtures.

Unknown string formats remain `String` until the project supplies an explicit
mapping outside generated output. Recursive refs are detected and reported;
escaping refs and unsupported external refs fail closed.

## Deliberate exclusions

Streaming, callbacks, webhooks, multipart bodies, and automatic security-scheme
execution are outside this contract. Attachments use the Dartitect attachment
pipeline, and credentials use the credential-generation pipeline. The project
owns authentication policy, transport construction, replay/idempotency policy,
domain models, repositories, and every DTO-to-domain mapper. Dartitect never
infers a semantic domain mapping from an API schema.

Use `package:dartitect_cli/dartitect_contracts.dart` only from tooling. It is a
focused entrypoint, not a runtime umbrella.
