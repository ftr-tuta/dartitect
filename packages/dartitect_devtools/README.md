# dartitect_devtools

`dartitect_devtools` is an optional, explicitly activated, read-only bridge
from Dartitect diagnostics protocol v2 to isolate-local VM service extensions.
It exposes only capabilities, bounded snapshots, and bounded event deltas. It
has no retry, cancellation, clearing, or other mutation RPC.

Register it only from a development entrypoint:

```dart
final registration = DartitectDevToolsRegistration.register(
  enabled: true,
  buffer: diagnosticBuffer,
  detail: DartitectDiagnosticDetail.topology,
);
```

Product-mode builds never register the handlers. Disposal clears the complete
owned diagnostic buffer.
