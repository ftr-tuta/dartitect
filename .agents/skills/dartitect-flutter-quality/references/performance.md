# Performance evidence

Collect first frame/useful state, FrameTiming build/raster p50/p95, frames over
budget, rebuilds, rows materialized, queue depth, first search result,
cancel/dispose, and residual subscriptions/watchers/timers/workers inside
canary support only. Do not add a public performance API.

Block zero-overflow, zero-framework-error, zero-late-publication,
zero-residual-resource, fewer than 100 rows materialized before scrolling
10,000 items, state preservation on resize, no heavy/provider work in
presentation, no network/plugin in previews or widget tests, and constrained
images.

Treat time and memory as informative until runner, Flutter version, build
mode, fixture, and measurement window match an equivalent baseline. Do not
turn one machine's measurements into portable release thresholds.
