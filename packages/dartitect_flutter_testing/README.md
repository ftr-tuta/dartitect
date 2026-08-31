# dartitect_flutter_testing

## Purpose

Dev-only Flutter UI scenario, accessibility, and cleanup harnesses for
Dartitect consumers. The package owns no themes, locales, text, navigation,
screens, controls, or goldens.

## When to use

Add this package as a development dependency when a Flutter consumer needs a
small, repeatable responsive and accessibility matrix around its real app root.
Use the exercise callback for product-specific focus, keyboard, navigation,
action, and state assertions.

## When not to use

Do not add it to production dependencies, use it as an application shell, or
delegate theme, localization, navigation, control choice, and golden policy to
the SDK. Do not expand the standard matrix into a platform-by-screen Cartesian
product without a product-specific reason.

## Platforms and entrypoints

Import
`package:dartitect_flutter_testing/dartitect_flutter_testing.dart` from Flutter
widget tests. The package depends only on `dartitect_flutter`, the Flutter SDK,
and `flutter_test`; its suite runs on the Flutter test VM and Chrome.

## Mental model and data flow

`DartitectUiMatrix` supplies a bounded list of paired environments. For each
`DartitectUiScenario`, `DartitectUiHarness` configures the Flutter test view,
target platform, `MediaQuery`, accessibility features, and semantics. The
consumer builds the complete root and exercises it. The harness then evaluates
Flutter's official label, contrast, and tap-target guidelines and restores all
overrides in `finally`.

The standard rows cover `360x640`, `430x932`, `768x1024`, `1024x768`, and
`1440x900`, normal and 200% text, LTR and RTL, light and dark brightness, high
contrast, and reduced motion without constructing every combination.

## Minimal workflow

```dart
testDartitectUiMatrix(
  'app shell',
  buildRoot: (scenario) => MaterialApp(
    theme: lightTheme,
    darkTheme: darkTheme,
    locale: localeFor(scenario.textDirection),
    home: const AppShell(),
  ),
  exercise: (tester, scenario) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  },
);
```

## Public API tour

- `DartitectUiScenario` records one paired surface and classifies it with the
  consumer-selected `DartitectLayoutBreakpoints`.
- `DartitectUiMatrix` validates a non-empty set of unique, finite scenarios and
  exposes the five-row `standard` matrix.
- `DartitectAccessibilityPolicy` selects Flutter's official label, contrast,
  and supported platform tap-target checks.
- `DartitectUiHarness` installs, verifies, and restores one test environment.
- `testDartitectUiMatrix` registers one widget test for each selected row.

## Ownership and lifecycle

The consumer owns the widget root, themes, locales, state, controllers,
navigation, and every product assertion. The harness borrows the test binding
and restores physical size, pixel ratio, text scale, brightness, accessibility
features, target platform, mounted root, and semantics before returning.

## Failure, cancellation, and concurrency

Flutter exceptions and render overflows fail the current row. Failed official
accessibility guidelines retain the scenario name and reason. The harness has
no asynchronous state envelope, cancellation policy, network behavior, shared
global test state, or implicit retry; consumers test those behaviors through
their existing commands, forms, queries, resources, and effects.

## Prohibited uses and limitations

- No screenshot, semantics tree, or screen content is transmitted.
- No SDK-owned color, typography, string, locale, navigation, design system,
  control, focus order, keyboard shortcut, or product golden.
- No claim that the five paired rows replace consumer-specific device,
  interaction, route, input-method, or native integration coverage.
- No hidden state preservation across responsive layout branches.

## Testing

Run `flutter test packages/dartitect_flutter_testing` for the VM boundary and
`flutter test --platform chrome` inside the package for the web engine boundary.
Consumer suites should add explicit focus, keyboard, action, navigation, and
localized semantics assertions, plus only the shared-layout goldens they need.

## Related packages and guides

Use `dartitect_flutter_ui.dart` for space-based layout classification and the
forms, queries, and reactive entrypoints for exhaustive borrowed state
presentation. Read the [UI quality guide](../../docs/guides/ui-quality.md) and
[reactive runtime guide](../../docs/guides/reactive-runtime.md).

## Availability

The workspace contains the `1.0.0-rc.10` source candidate. Add it only from a
matching tagged GitHub Release and compatible cohort coordinates in that
Release's notes. If no compatible Release exists, there is no supported
consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
