# Families and collections

`ResourceFamily<K, T, F>` shares equal keys only inside one explicit family.
Acquire and release a `FamilyLease` per retained consumer. Bound idle entries by
positive TTL, count, and weight. Never evict active leases, observers, or hot
resources. Remove an entry from the index before asynchronous disposal so a
reacquisition creates a new generation.

`LiveCollection<K, T>` keeps stable item nodes and publishes membership, order,
length, and item changes separately. Select `replaceAll`, `diffByKey`, or
`versionedByKey` explicitly. Validate keys and the entire projection before one
atomic publication. Duplicate keys, projection crashes, cancellation, or stale
background completion preserve the prior snapshot. Removed nodes retain a
tombstone only while listeners or configured warm retention require it.
