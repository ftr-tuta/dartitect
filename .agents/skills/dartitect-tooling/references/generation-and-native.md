# Generation and native setup

Stage generated content outside the destination, validate it, refuse
consumer-owned collisions, record a journal, and replace only the declared
target. Recover the old data on interruption. Generated-once files become
consumer-owned; fully generated files need an ownership manifest before update.
For project-service changes, the semantic manifest excludes unrelated assets;
the OS lock spans revalidation through all journal cleanup.

Native fixture setup accepts only reviewed host/artifact mappings, verifies a
pinned hash before extracting one exact member, installs through same-directory
staging, and revalidates ignored cache markers. Keep download, archive, host,
temporary-root, and atomic replacement injectable for offline tests. Never run
provider code generation by hand or edit its output.
