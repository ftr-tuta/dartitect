# Tooling tests

Use temporary roots and injected process/filesystem boundaries. Cover read-only
commands, dry-run/apply separation, unknown config rejection, strict findings,
expiring suppressions, stale plans, conflicts, recovery journals, symlink/path escape,
permissions, Unicode and spaces, and idempotent managed-skill sync.

Run consumer-tax schema-2 fixtures for local through offline-full. Require zero
semantic `architectureTax`; scale `generatedTax` by declared axes; reject
string-based architecture tests and structural-only fakes; never charge
consumer domain/UI `productCode`. Analyzer/build timings ratchet only on the
same CI runner.

Native setup tests remain offline by injecting download, archive, host, temp
root, and atomic replacement. Cover supported mappings, pinned hashes, corrupt
or truncated archives, missing exact members, unsupported hosts, read-only
destinations, cache revalidation, and cleanup. MCP protocol tests also cover
expiry, replay, concurrency/lock, output sanitization, and clean shutdown.
