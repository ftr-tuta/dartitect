# Competitive benchmark workspace

This unpublished workspace pins `flutter_riverpod`, `flutter_bloc`, and
`bloc_concurrency` for same-process comparisons. None is a Dartitect runtime
dependency.

Run `flutter pub get`, then `dart run bin/orchestrate_benchmarks.dart`. The
orchestrator starts and resumes one paused Flutter test so `dart:ui` and the VM
service share the same runner. It uses deterministic randomized scenario order,
warm-up passes, and repeated samples, then writes raw JSON, an environment
manifest, and an AsciiDoc report under `artifacts/`.
From the repository root, `dart run tool/check_benchmark_artifacts.dart`
replays every statistical, work-counter, incremental-update, and leak gate
without rerunning timings.

Environment schema v2 records the commit captured when the benchmark ran, its
canonical equivalent after any history rewrite, and their unchanged tree. A
new run records the same commit in both fields; migrating provenance never
changes the measurement timestamp or represents a new execution.

Do not adjust a gate to make a run pass. Diagnose the scenario or algorithm,
then regenerate the entire artifact set on one otherwise-idle runner.
