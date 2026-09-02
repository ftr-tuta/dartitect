# Sentry adapter

The consumer initializes and configures Sentry, supplies the DSN through its own
secure configuration, and closes the SDK. Dartitect adapters borrow an injected
Hub and never initialize, reconfigure, or close it.

Legacy adapters remain defensive and redact direct compatible-runtime input.
For `ObservabilityRuntime.withPrivacy`, use only
`SentryLogSink.sanitizedInput`, `SentryErrorReporter.sanitizedInput`, and
`SentryTracer.sanitizedInput`; prepared input is not redacted twice. Map only
approved bounded context/extra data, limit tags, and never create a `SentryUser`.
Avoid duplicate Flutter error, Dio, or tracing capture. Test through a fake Hub
with zero network, including destination failure and borrowed lifetime. Dispose
Dartitect adapters before the consumer closes the Hub.
