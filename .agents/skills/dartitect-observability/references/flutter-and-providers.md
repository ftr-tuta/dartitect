# Flutter and providers

Install one `FlutterErrorBinding`. Chain the previous Flutter/platform handlers,
prevent recursion, and restore exactly those handlers on disposal. Keep
foreground capture separate from background-isolate reporting.

Provider SDK initialization, credentials, release/environment configuration,
consent, and shutdown belong to the consumer. Provider adapters borrow injected
SDK objects unless their registration explicitly owns them. For Sentry, borrow
the consumer-initialized Hub; never initialize, configure, or close it. Reject
duplicate capture or tracing such as simultaneous Dartitect Dio instrumentation
and `sentry_dio`.
