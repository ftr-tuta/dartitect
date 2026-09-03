# Tests and evidence

Test ViewModel transitions, generation cancellation, mounted effects, and the
common repository contract for Memory, Drift, and ObjectBox. Widget tests cover
all visible states, callback purity, diagnostics view data, responsive branch
replacement, selection, scroll, focus, keyboard, mouse, and touch. Integration
journeys cover smoke, resize, commands, offline/reconnect, search/toggle,
forced logout, and the 10,000-item fixture.

Compile discovered previews from a temporary copy with
`flutter widget-preview start --no-launch-previewer`. Run `dart analyze`,
`flutter analyze`, the strict Dartitect UI audit, focused and complete tests,
Chrome, and supported hosted builds. Prove previews and widget tests invoke no
network or plugin boundary.

The coordinated GitHub Actions graph must pass the exact merge candidate. Its
eight job identifiers cover nine hosted executions because Linux runs both the
Flutter floor and current stable cells. `CI / Required` fails closed if any
coordinated job fails, is cancelled, or is skipped.
