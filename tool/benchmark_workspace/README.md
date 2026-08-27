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

Environment schema v2 records the commit captured when an external benchmark
run is retained as candidate evidence. The checked-in dataset is intentionally
marked `REFERENCE_ONLY_REPRODUCTION_REQUIRED`: CI reproduces it on the exact
candidate SHA instead of treating a pre-commit local measurement as evidence.

Do not adjust a gate to make a run pass. Diagnose the scenario or algorithm,
then regenerate the entire artifact set on one otherwise-idle runner.
