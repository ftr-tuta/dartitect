# Tooling tests

Use temporary roots and injected process/filesystem boundaries. Cover read-only
commands, dry-run/apply separation, unknown config rejection, reviewed baseline
fingerprints, stale plans, conflicts, recovery journals, symlink/path escape,
permissions, Unicode and spaces, and idempotent managed-skill sync.

Native setup tests remain offline by injecting download, archive, host, temp
root, and atomic replacement. Cover supported mappings, pinned hashes, corrupt
or truncated archives, missing exact members, unsupported hosts, read-only
destinations, cache revalidation, and cleanup. MCP protocol tests also cover
expiry, replay, concurrency/lock, output sanitization, and clean shutdown.
