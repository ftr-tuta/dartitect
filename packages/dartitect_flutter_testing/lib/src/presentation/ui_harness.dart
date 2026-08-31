// flutter_test is deliberately part of this dev-only package's public API.
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui_matrix.dart';

/// Consumer root factory for one configured scenario.
typedef DartitectUiRootBuilder = Widget Function(DartitectUiScenario scenario);

/// Optional scenario-specific interaction and assertion callback.
typedef DartitectUiExercise = FutureOr<void> Function(
  WidgetTester tester,
  DartitectUiScenario scenario,
);

/// Accessibility checks applied after each scenario exercise.
@immutable
final class DartitectAccessibilityPolicy {
  /// Creates a policy backed by Flutter's official accessibility guidelines.
  const DartitectAccessibilityPolicy({
    this.requireLabels = true,
    this.requireTextContrast = true,
    this.requireMinimumTapTargets = true,
  });

  /// Checks observable labels on tappable semantics nodes.
  final bool requireLabels;

  /// Checks WCAG text contrast through Flutter's renderer.
  final bool requireTextContrast;

  /// Checks the official target size for the configured platform convention.
  final bool requireMinimumTapTargets;

  Iterable<AccessibilityGuideline> _guidelines(TargetPlatform platform) sync* {
    if (requireLabels) yield labeledTapTargetGuideline;
    if (requireTextContrast) yield textContrastGuideline;
    if (requireMinimumTapTargets) {
      switch (platform) {
        case TargetPlatform.iOS:
          yield iOSTapTargetGuideline;
          break;
        case TargetPlatform.android || TargetPlatform.fuchsia:
          yield androidTapTargetGuideline;
          break;
        case TargetPlatform.linux ||
            TargetPlatform.macOS ||
            TargetPlatform.windows:
          // Flutter exposes no desktop-specific minimum target guideline.
          break;
      }
    }
  }
}

/// Configures, verifies, and restores one Flutter UI test environment.
final class DartitectUiHarness {
  /// Creates a harness with an explicit accessibility policy.
  const DartitectUiHarness({
    this.accessibilityPolicy = const DartitectAccessibilityPolicy(),
  });

  /// Checks applied after the consumer exercise.
  final DartitectAccessibilityPolicy accessibilityPolicy;

  /// Pumps and verifies one [scenario].
  ///
  /// Themes, locales, navigation, text, and the root widget are supplied by
  /// [buildRoot]. Focus, keyboard, and product actions remain in [exercise].
  Future<void> run(
    WidgetTester tester, {
    required DartitectUiScenario scenario,
    required DartitectUiRootBuilder buildRoot,
    DartitectUiExercise? exercise,
  }) async {
    final priorPlatform = debugDefaultTargetPlatformOverride;
    SemanticsHandle? semantics;
    Object? pendingFailure;
    StackTrace? pendingStack;
    try {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = scenario.size;
      tester.platformDispatcher
        ..textScaleFactorTestValue = scenario.textScaleFactor
        ..platformBrightnessTestValue = scenario.brightness
        ..accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
          accessibleNavigation: scenario.reducedMotion,
          disableAnimations: scenario.reducedMotion,
          reduceMotion: scenario.reducedMotion,
          highContrast: scenario.highContrast,
        );
      debugDefaultTargetPlatformOverride = scenario.platform;
      semantics = tester.ensureSemantics();

      final mediaQuery = MediaQueryData.fromView(tester.view).copyWith(
        textScaler: TextScaler.linear(scenario.textScaleFactor),
        highContrast: scenario.highContrast,
        disableAnimations: scenario.reducedMotion,
        accessibleNavigation: scenario.reducedMotion,
      );
      await tester.pumpWidget(
        MediaQuery(
          data: mediaQuery,
          child: Directionality(
            textDirection: scenario.textDirection,
            child: buildRoot(scenario),
          ),
        ),
      );
      await tester.pump();
      _throwPendingFrameworkException(tester, scenario);

      await exercise?.call(tester, scenario);
      await tester.pump();
      _throwPendingFrameworkException(tester, scenario);

      for (final guideline in accessibilityPolicy._guidelines(
        scenario.platform,
      )) {
        final evaluation = await guideline.evaluate(tester);
        if (!evaluation.passed) {
          throw TestFailure(
            '${scenario.name} failed ${guideline.description}: '
            '${evaluation.reason ?? 'no reason supplied'}',
          );
        }
      }
    } catch (error, stackTrace) {
      pendingFailure = error;
      pendingStack = stackTrace;
    } finally {
      semantics?.dispose();
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } catch (error, stackTrace) {
        pendingFailure ??= error;
        pendingStack ??= stackTrace;
      }
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
      tester.platformDispatcher
        ..clearTextScaleFactorTestValue()
        ..clearPlatformBrightnessTestValue()
        ..clearAccessibilityFeaturesTestValue();
      debugDefaultTargetPlatformOverride = priorPlatform;
    }
    if (pendingFailure != null) {
      Error.throwWithStackTrace(pendingFailure, pendingStack!);
    }
  }

  static void _throwPendingFrameworkException(
    WidgetTester tester,
    DartitectUiScenario scenario,
  ) {
    final exception = tester.takeException();
    if (exception != null) {
      throw TestFailure(
        '${scenario.name} produced a Flutter exception or overflow: '
        '$exception',
      );
    }
  }
}

/// Registers one widget test for every paired UI scenario.
void testDartitectUiMatrix(
  String description, {
  required DartitectUiRootBuilder buildRoot,
  DartitectUiMatrix? matrix,
  DartitectUiHarness harness = const DartitectUiHarness(),
  DartitectUiExercise? exercise,
}) {
  final selected = matrix ?? DartitectUiMatrix.standard;
  for (final scenario in selected.scenarios) {
    testWidgets('$description [${scenario.name}]', (tester) async {
      await harness.run(
        tester,
        scenario: scenario,
        buildRoot: buildRoot,
        exercise: exercise,
      );
    });
  }
}
