# Flutter quality agent evaluations

This directory is the stable, payload-free adapter around the pinned
[`flutter/evals`](https://github.com/flutter/evals) Inspect AI runner and the
official [`flutter/agent-plugins`](https://github.com/flutter/agent-plugins)
skills. `corpus.json` is the internal schema: nine source fixtures are assigned
once across seven aggregate quality cases.

The required matrix is seven cases times `baseline`, `officialSkills`, and
`officialSkills+Dartitect`, with one repetition (21 evaluations). The manual or
scheduled trend matrix uses the same model/configuration with three repetitions
(63 evaluations). A run always uses the exact upstream SHAs declared in the
corpus and a Docker image pinned by digest.

Validate without API access or Docker:

```sh
dart run tool/check_agent_evals.dart
dart run tool/agent_evals/run.dart --dry-run --suite=required --repetitions=1
dart run tool/agent_evals/run.dart --dry-run --suite=trend --repetitions=3
```

The protected workflow supplies `OPENAI_API_KEY` and
`DARTITECT_CODEX_EVAL_IMAGE`. The image must contain Python 3, Inspect AI and
the dependencies of the pinned `dash_evals`; the runner imports the actual
pinned checkout rather than a bundled copy. The same digest is used for the
outer runner and Inspect's Docker sandbox. The sandbox has no network; model
traffic stays in the outer evaluation process.

Only the receipt path leaves the temporary run directory. It contains the
candidate SHA, upstream pins, model/configuration, counts, aggregate scores,
skill/tool usage, and digests. Logs and their transcripts, screenshots,
semantics, prompts, completions, and screen content are deleted before exit and
are never uploaded.
