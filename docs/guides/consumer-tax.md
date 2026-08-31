# Consumer-tax ratchets

`dartitect inspect --consumer-tax --json` emits schema 2 and is a read-only
gate for projects created with Dartitect. It separates architecture plumbing,
generated scale, tests, and product code instead of treating all source lines
as one budget.

The report has four independent sections:

- `architectureTax`: semantically resolved manual plumbing; its mandatory
  limit is zero;
- `generatedTax`: additive budgets by target, context, transport, scheduler,
  observability provider, profile, capability, endpoint, and extension;
- `testTax`: rejects string-scanned architecture tests and purely structural
  fakes while leaving domain fixtures visible; and
- `productCode`: domain and UI files/lines are reported but never block.

Analyzer AST and resolved identity are authoritative. Regex is only a diagnosed
fallback. CI may provide actual analyzer and build timings in
`.dartitect/consumer-tax-metrics.json` schema 1:

```json
{
  "schemaVersion": 1,
  "analysisMillis": 4200,
  "buildMillis": 38000
}
```

Timing evidence is observed but never synthesized by the read-only command.
The generated-project matrix records it around the real analyzer and build/test
processes before invoking the gate.

Every profile permits zero manual architecture plumbing. Provider owners,
engines, listener/admission loops, and disposal ordering belong in generated
graphs. A context factory may construct the exact provider owner selected for
that context; this is an explicit boundary, not architecture tax.

Config v3 is the opt-in authority for dependency closure. An empty/local shell
cannot resolve Dio, Drift, sync, or Workmanager packages. Transport, storage,
dataset sync, and scheduler dependencies become eligible only when the matching
typed config block selects them. Direct Dartitect runtime dependencies unused
by any `lib/` import also fail.

Generated `*.dartitect.g.dart` files are measured for size and dependency use,
but generated plumbing does not count as consumer-authored tax. The
reproducible `tool/change_tax.dart` study applies 12 changes to temporary
copies, records manual/generated diffs and generation/analyzer/build durations,
and requires a zero architecture-tax delta. Timing regressions are compared
only on the same CI runner with a 20% ratchet; local timings are evidence-only.
