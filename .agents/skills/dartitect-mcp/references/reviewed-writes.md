# Reviewed writes

Start the server with `--allow-writes` only when a reviewed local mutation is
intended. The flag alone grants nothing. Apply requires all of:

1. server write opt-in;
2. a prior read-only preview;
3. an opaque plan ID that is unexpired and unused;
4. `confirmed: true` after user review;
5. client MCP approval;
6. complete root, state, and operation revalidation;
7. in-process serialization plus an exclusive filesystem lock.

Plans are single-use even after a failed attempt. Expiry, replay, stale state,
concurrency, path, permission, and I/O errors remain structured and sanitized.
Do not bypass the flow, broaden roots, or use MCP writes as CI automation.
