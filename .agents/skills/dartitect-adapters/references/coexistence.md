# Drift and ObjectBox coexistence

Use separate bounded contexts, repositories, schemas, files/directories, and
database owners. ViewModels depend only on application/domain contracts. Keep
one writer per dataset or partition and dispose observations, sync runs, and
repositories before either engine.

Do not dual-write, bridge engines, share a schema, or imply a cross-engine
transaction. A change of engine is an explicit, resumable application
migration with validation and compensation. Prove coexistence with both real
generators and both real databases open simultaneously.
