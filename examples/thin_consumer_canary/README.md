# Thin consumer canary

This six-platform app is generated from the `offline-hybrid` preset and keeps
all four stable workflows opt-in: credentials, attachments, forms, and
queries. Its consumer-owned Dart files intentionally contain no Dartitect
bootstrap coordinator, provider owner, sync engine, mutation command, job
dispatcher, or diagnostics wiring.

The authoritative declarations live in `dartitect.json`; fully managed direct
composition lives only in `*.dartitect.g.dart` files.
Its only preview smoke is private under `lib/src/dev`, uses immutable synthetic
values, adds no runtime dependency, and cannot reach the generated graph or
provider adapters.
