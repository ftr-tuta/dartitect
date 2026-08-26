# Custom provider

Implement an application-owned or small reusable adapter against Dartitect's
public contracts. Keep provider imports in infrastructure and accept provider
objects/configuration through constructor injection.

A reusable adapter needs an isolated optional package, explicit ownership,
minimal/redacted telemetry, deterministic no-network tests, a real SDK boundary
test, supported-platform documentation, dependency/version rationale, compatible
license, and supply-chain review. Do not add a generic abstraction that hides
provider constraints or changes the domain contract.
