# Business-neutral Flutter UI quality

Dartitect supplies presentation mechanics, not product presentation. The app
continues to own its themes, colors, typography, visible text, localization,
navigation, platform conventions, focus order, restoration, and composed
widgets. Use Material 3 controls directly. Use Flutter adaptive APIs or
Cupertino controls only where Flutter or an Apple convention makes the
difference meaningful.

This boundary follows Flutter's own adaptive guidance: abstract shared state,
measure the available space, then branch the layout. Flutter recommends
`MediaQuery.sizeOf` for the whole app window and `LayoutBuilder` for a local
region; it also warns against layout decisions based on a device category or
orientation. See Flutter's [general adaptive approach](https://docs.flutter.dev/ui/adaptive-responsive/general)
and [adaptive best practices](https://docs.flutter.dev/ui/adaptive-responsive/best-practices).

## Entrypoints and ownership

Import only the surface the feature uses:

| Need | Entrypoint | Consumer still owns |
| --- | --- | --- |
| Commands and ViewModels | `package:dartitect_flutter/dartitect_flutter.dart` | actions, copy, controls, navigation |
| Responsive layout | `package:dartitect_flutter/dartitect_flutter_ui.dart` | breakpoints when customized, branch composition, visual design |
| Forms | `package:dartitect_flutter/dartitect_flutter_forms.dart` | fields, validation copy, focus, submission UX |
| Queries | `package:dartitect_flutter/dartitect_flutter_queries.dart` | filters, empty/stale/error presentation |
| Reactive resources | `package:dartitect_flutter/dartitect_flutter_reactive.dart` | empty policy, retained-content UX, retry affordances |
| UI test matrix | `package:dartitect_flutter_testing/dartitect_flutter_testing.dart` | root widget, themes, locales, interactions, product assertions |

The builders borrow commands, controllers, and resources. They observe only
while the subtree's `TickerMode` is enabled, catch up with current state when
reactivated, and never dispose the borrowed authority. Keep ViewModels,
controllers, focus nodes, scroll controllers, selected destinations, and
restorable state above a responsive branch replacement.

## Responsive window and region layouts

`DartitectLayoutBreakpoints.material3` classifies width at 600 and 840 logical
pixels and height at 480 and 900. Width and height are classified separately;
an exact boundary belongs to the larger class. A custom breakpoint set must be
finite, non-negative, and ordered.

`DartitectResponsiveWindowBuilder` measures `MediaQuery.sizeOf`. It requires
compact, medium, and expanded callbacks and chooses one from the width class.
Each callback also receives the separate height class:

```dart
import 'package:dartitect_flutter/dartitect_flutter_ui.dart';
import 'package:flutter/material.dart';

Widget buildAppShell(BuildContext context, Widget body) {
  return DartitectResponsiveWindowBuilder(
    compact: (context, window) => Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        ],
      ),
    ),
    medium: (context, window) => _RailShell(body: body),
    expanded: (context, window) => _RailShell(body: body, extended: true),
  );
}
```

The literal label is abbreviated for the example; production copy and semantic
labels come from the consumer's localization. Flutter documents
`flutter_localizations`, delegates, supported locales, and app-owned localized
values in its [internationalization guide](https://docs.flutter.dev/ui/internationalization).

Use `DartitectResponsiveRegionBuilder` inside a bounded pane or component. It
uses `LayoutBuilder` and rejects an unbounded maximum width because no stable
region class could be selected. Neither responsive builder adds a `Scaffold`,
navigator, control, animation, or state-preservation mechanism.

## Exhaustive state rendering

Do not add another async wrapper around the existing authority:

| Authority | Builder | Required variants |
| --- | --- | --- |
| `DartitectCommand<T, F>` | `CommandStateBuilder<T, F>` | idle, running, success, expected failure, cancellation, crash |
| `DartitectFormController<T, F>` | `DartitectFormSnapshotBuilder<T, F>` | current immutable form snapshot |
| `DartitectQueryController<Q, T, F>` | `DartitectQueryStateBuilder<Q, T, F>` | initial, loading, empty, content, expected failure |
| `LiveResource<ResourceSnapshot<T, M>, F>` | `ResourcePresentationBuilder<T, F, M>` | waiting, content, empty, expected failure, crash |

Loading may retain stale query items. Resource failures may retain the last
known local snapshot. The consumer decides how that state is communicated and
whether retry is appropriate. Unexpected crashes stay distinct from typed
expected failures and retain their original stack.

Drain one-shot effects at a mounted View boundary. A ViewModel may emit a typed
effect, but it does not retain `BuildContext` or choose routes, snack bars,
dialogs, or platform intents.

## Controls, focus, and platform conventions

Prefer `FilledButton`, `TextButton`, `OutlinedButton`, `IconButton`, official
form controls, `NavigationBar`, and `NavigationRail` over gesture-built
controls. Official Flutter controls already carry keyboard, focus, semantics,
and platform behavior that a custom control would need to reconstruct. Flutter
describes which behavior adapts automatically and which product conventions
remain an app decision in [automatic platform adaptations](https://docs.flutter.dev/ui/adaptive-responsive/platform-adaptations).

Focus nodes are long-lived state objects: create and dispose them outside
`build`, keep them above layout replacement when focus must survive, and define
traversal/shortcuts for desktop and web flows. Flutter's [focus guide](https://docs.flutter.dev/ui/interactivity/focus)
covers ownership, traversal, focus scopes, and keyboard event propagation.

## Paired UI matrix and accessibility

`DartitectUiMatrix.standard` deliberately uses five paired scenarios rather
than a Cartesian product:

| Surface | Other coverage in the paired row |
| --- | --- |
| 360x640 | 100%, LTR, light, normal contrast/motion |
| 430x932 | 200%, RTL, dark, high contrast, reduced motion |
| 768x1024 | 100%, RTL, light, high contrast |
| 1024x768 | 200%, LTR, dark, reduced motion |
| 1440x900 | 100%, LTR, light, high contrast, reduced motion |

The consumer supplies the root, themes, locales, and optional scenario
exercise:

```dart
testDartitectUiMatrix(
  'orders shell',
  buildRoot: (scenario) => MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: scenario.brightness),
    home: const OrdersPage(),
  ),
  exercise: (tester, scenario) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(find.bySemanticsLabel('Create order'), findsOneWidget);
  },
);
```

The harness restores surface, platform, `MediaQuery`, accessibility features,
and semantics in `finally`, and fails on Flutter exceptions/overflows. Its
accessibility policy applies Flutter's official label, contrast, Android target,
and iOS target guidelines. Flutter documents those APIs and their scope in
[accessibility testing](https://docs.flutter.dev/ui/accessibility/accessibility-testing).
Focus order, keyboard activation, navigation, restoration, and domain actions
remain explicit consumer assertions.

## Audit, goldens, and privacy

Run both presentation checks in CI:

```console
dartitect ui audit --strict
dart analyze
```

`DT3001` and `DT3002` are objective errors for a low-level custom Material
button primitive and application orientation locking. `DT3101` through
`DT3106` are warnings for orientation/device sizing, broad `MediaQuery.of`, a
gesture action without evident semantics, visual color literals outside a theme
boundary, and an icon-only action without an observable label. `--strict`
makes warnings fail the command. CLI and analyzer use the same versioned parity
corpus. Reviewed suppressions use the existing narrow code/path, owner, reason,
and expiry contract.

Keep goldens only for shared compact, medium, and expanded layouts on a fixed
runner, font, and renderer. Semantics and behavior are the primary gate. No
Dartitect test, audit, or golden uploads screenshots, semantics, or screen
content to telemetry.

## Executable Flutter quality contract

The `ui-quality-v2` artifact turns seven practices into required evidence. A
technique is evidenced only when its applicable static, preview, runtime, test,
evaluation, canary, and platform observations are present:

| Technique | Blocking evidence |
| --- | --- |
| Constraint-driven responsiveness | constraint inspection, resize state preservation, bounded lazy rows, focus and scroll journeys |
| DevTools runtime work | real Flutter MCP discovery, widget/runtime inspection, and explicit missing-tool evidence |
| Reusable widgets and previews | preview discovery and compilation with immutable synthetic fixtures and pure callbacks |
| MVVM | ViewModel-owned state, commands and effects; route-owned Flutter lifecycle; generation-fenced search |
| Repositories | provider-neutral contract, exactly one composed store, local-first outbox behavior, offline/reconnect tests |
| Multi-platform behavior | keyboard, mouse, touch, adaptive capability projection, Chrome, and hosted platform builds |
| Tests | unit, widget, preview, integration, structural performance, and zero-residual-resource evidence |

Run the two local inspectors without writes:

```console
dartitect inspect flutter-quality
dartitect codex doctor --flutter
```

`fail` and `notEvidenced` are blocking. `warning` remains non-blocking unless
the enclosing strict gate promotes warnings. `notApplicable` is excluded from
aggregation and becomes the overall result only when no technique applies.

## Official Flutter tooling for Codex

Flutter integration comes from the official `dart-flutter@dart-flutter`
plugin. Installation remains an explicit user action:

```console
codex plugin add dart-flutter@dart-flutter
```

Start a new Codex session after installation. Dartitect discovers the plugin's
six Flutter skills by their names and discovers MCP tools at runtime through
the plugin's `dart mcp-server`. It never invents an unavailable tool. The setup
command synchronizes only the Dartitect catalog into the workspace:

```console
dartitect codex setup --flutter --dry-run
dartitect codex setup --flutter --apply
```

Setup is offline and never runs the plugin command, `npx`, dependency
installation, or a global configuration change. `.vscode/mcp.json`, when
present, is reported only as external editor configuration; it is not Codex
configuration and is never created or edited.

## Preview matrix and isolation

Annotate dev-only preview functions with `@DartitectPreviewMatrix()`. It emits
four ordered device scenarios: compact 360x640 light at 100%, compact 430x932
dark at 200%, medium 768x1024 light at 100%, and expanded 1440x900 light at
100%. RTL, contrast, reduced motion, semantics, focus, and keyboard checks stay
exclusively in `DartitectUiMatrix`; the preview matrix does not duplicate them.

A preview may construct only immutable synthetic view data and pure callbacks.
It cannot initialize application lifecycle, stores, adapters, plugins, native
I/O, FFI, network clients, or global state. Compile previews from a temporary
copy with `flutter widget-preview start --no-launch-previewer` so discovery
evidence does not modify the real tree.

## Runtime, performance, and evaluation evidence

The analyzer proves Flutter and Dartitect library/type identity before emitting
an error. The syntax-only CLI scanner uses at most warning severity when
identity cannot be established; `--strict` preserves the existing promotion
behavior. Runtime evidence records real MCP availability, constraints, Flutter
framework errors, late publication, and cleanup without storing screen content.

Structural invariants block the gate: zero overflow, framework error, late
publication, or residual subscriptions/watchers/timers/workers; fewer than 100
materialized rows before scrolling a 10,000-item fixture; state preserved on
resize; no heavy/provider work in presentation; no preview network/plugin
access; and constrained images. Frame build/raster percentiles and memory are
informative until runner, Flutter version, build mode, fixture, and observation
window match a recorded baseline.

The required exact-SHA agent-evaluation matrix compares baseline, official
Flutter skills, and official skills plus Dartitect. Its receipt is payload-free:
only the SHA, pins, model/configuration, counts, aggregate scores, tool/skill
usage, and digests are retained. Transcripts, screenshots, semantics, and
visible screen content are excluded.
