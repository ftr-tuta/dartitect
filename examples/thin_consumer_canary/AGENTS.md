# Dartitect architecture contract

- Validate with `flutter analyze`, `flutter test`, and `dart run dartitect_cli:dartitect inspect --json`.
- Use constructor injection and explicit composition roots.
- Domain must not import Flutter, data implementations, or adapters.
- Presentation and ViewModels must not import Dio or ObjectBox.
- Do not use service locators, architecture/state frameworks, or private `src/` imports.
- `ViewModelHost.create` owns its value; `ViewModelHost.value` borrows it.
- Keep routing and UI effects in Widgets.
- Before adding infrastructure, ask: É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?
- It belongs in Dartitect only when all three answers are yes; otherwise use a typed project-local extension or keep business behavior in the application.
