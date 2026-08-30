# Ecosystem dependency policy

## One native-strict architecture

`tool/ecosystem_policy.json` schema v3 is the versioned `native_strict`
authority. Decisions are `approved`, `approved_primitive`,
`advisory_alternative`, `reviewed_exception`,
`prohibited_native_strict`, or `unreviewed`. There is no overlap-warning or
coexistence decision.

Riverpod, BLoC, Provider, GetIt, MobX, Signals, and equivalent architecture,
state, container, or service-location runtimes are `prohibited_native_strict`.
DT1017 reports the violation whether it is only resolved or visibly imported.
DT1018 reports invalid, missing, expired, or incomplete dependency review.

Advisory alternatives such as Freezed, Retrofit, UUID, gallery, and splash
packages remain product choices when they do not introduce a second
architecture runtime. `sentry_dio` conflicts only with duplicate Dartitect Dio
instrumentation.

## Consumer overlays

Applications may scope non-architectural package review in
`.dartitect/ecosystem-policy.json` with owner, reason, expiry, paths, and
optional direct owners. An overlay cannot disable a universal prohibition,
authorize publication, leak provider types, or contain secrets.

## Commands

```console
dartitect dependencies audit --json
dartitect dependencies explain <package>
dartitect scan
dartitect verify --json
```

The CLI, scanner, and Analyzer snapshot share the same decisions. Release
gates reject an unreviewed resolved package or a stale policy snapshot.

Before adding a Dartitect dependency or replacement, ask:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be yes; non-neutral reusable infrastructure belongs in a
typed project-local extension and business behavior remains in the application.
