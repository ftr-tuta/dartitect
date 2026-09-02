# Architecture and previews

Use the route `Page -> ViewModel -> Repository -> store/outbox -> remote
service`. The Page owns route lifecycle, controllers, mounted navigation, and
effect delivery. The View observes one ViewModel. Reusable content, rows,
details, and diagnostics receive immutable values and callbacks, never
sessions, roots, providers, Stores, clients, or internal payloads.

A provider-neutral repository coordinates local-first behavior and selects
exactly one Memory, Drift, or ObjectBox store at composition. Never dual-write
or migrate engines implicitly. Fence restart-latest search generations and
publish only the current aggregate. Keep query, selection, scroll, and focus
above compact/medium/expanded branch replacement; use lazy builders and
row-scoped selectors.

Use `DartitectPreviewMatrix` only for device size, brightness, and text scale.
Keep RTL, contrast, reduced motion, semantics, focus, and keyboard in
`DartitectUiMatrix`. Preview functions live in permitted dev-only locations
and return widgets from immutable synthetic view data and pure callbacks.
They cannot reach native I/O, FFI, network, stores, adapters, plugins, global
initialization, or application lifecycle.
