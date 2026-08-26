# Sentry adapter

The consumer initializes and configures Sentry, supplies the DSN through its own
secure configuration, and closes the SDK. Dartitect adapters borrow an injected
Hub and never initialize, reconfigure, or close it.

Map only sanitized logs, errors, spans, mechanisms, fingerprints, and allowlisted
attributes. Avoid duplicate Flutter error, Dio, or tracing capture. Test through
a fake Hub with zero network, including destination failure and borrowed
lifetime. Dispose Dartitect sinks/reporters/tracers before the consumer closes
the Hub.
