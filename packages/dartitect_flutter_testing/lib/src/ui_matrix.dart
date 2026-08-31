import 'package:dartitect_flutter/dartitect_flutter_ui.dart';
import 'package:flutter/widgets.dart';

/// One paired UI environment, intentionally not a Cartesian-product row.
@immutable
final class DartitectUiScenario {
  /// Creates one immutable UI scenario.
  const DartitectUiScenario({
    required this.name,
    required this.size,
    required this.textScaleFactor,
    required this.textDirection,
    required this.brightness,
    required this.highContrast,
    required this.reducedMotion,
    required this.platform,
  });

  /// Stable test-name suffix.
  final String name;

  /// Logical surface size.
  final Size size;

  /// Linear system text scale.
  final double textScaleFactor;

  /// Ambient text direction. The consumer should select a matching locale.
  final TextDirection textDirection;

  /// Ambient platform brightness.
  final Brightness brightness;

  /// Whether high-contrast accessibility is enabled.
  final bool highContrast;

  /// Whether reduced motion and disabled animations are enabled.
  final bool reducedMotion;

  /// Flutter target platform used by adaptive controls and tap-target policy.
  final TargetPlatform platform;

  /// Classifies this surface with [breakpoints].
  DartitectWindowClass windowClass({
    DartitectLayoutBreakpoints breakpoints =
        DartitectLayoutBreakpoints.material3,
  }) => breakpoints.classify(size);
}

/// A finite, deliberately paired set of UI scenarios.
final class DartitectUiMatrix {
  /// Creates a non-empty matrix with unique scenario names.
  DartitectUiMatrix(Iterable<DartitectUiScenario> scenarios)
    : scenarios = List<DartitectUiScenario>.unmodifiable(scenarios) {
    if (this.scenarios.isEmpty) {
      throw ArgumentError.value(scenarios, 'scenarios', 'Must not be empty.');
    }
    final names = <String>{};
    for (final scenario in this.scenarios) {
      if (scenario.name.trim().isEmpty || !names.add(scenario.name)) {
        throw ArgumentError.value(
          scenario.name,
          'scenarios',
          'Names must be non-empty and unique.',
        );
      }
      if (!scenario.size.width.isFinite ||
          !scenario.size.height.isFinite ||
          scenario.size.width <= 0 ||
          scenario.size.height <= 0) {
        throw ArgumentError.value(
          scenario.size,
          'scenarios',
          'Sizes must be finite and positive.',
        );
      }
      if (!scenario.textScaleFactor.isFinite || scenario.textScaleFactor <= 0) {
        throw ArgumentError.value(
          scenario.textScaleFactor,
          'scenarios',
          'Text scale must be finite and positive.',
        );
      }
    }
  }

  /// Standard five-row paired matrix.
  ///
  /// The rows cover all requested surfaces and both values of text scale,
  /// direction, brightness, contrast, and motion without multiplying them.
  static final standard = DartitectUiMatrix(const <DartitectUiScenario>[
    DartitectUiScenario(
      name: 'compact-360-light-ltr',
      size: Size(360, 640),
      textScaleFactor: 1,
      textDirection: TextDirection.ltr,
      brightness: Brightness.light,
      highContrast: false,
      reducedMotion: false,
      platform: TargetPlatform.android,
    ),
    DartitectUiScenario(
      name: 'compact-430-dark-rtl-a11y',
      size: Size(430, 932),
      textScaleFactor: 2,
      textDirection: TextDirection.rtl,
      brightness: Brightness.dark,
      highContrast: true,
      reducedMotion: true,
      platform: TargetPlatform.iOS,
    ),
    DartitectUiScenario(
      name: 'medium-portrait-light-rtl',
      size: Size(768, 1024),
      textScaleFactor: 1,
      textDirection: TextDirection.rtl,
      brightness: Brightness.light,
      highContrast: true,
      reducedMotion: false,
      platform: TargetPlatform.android,
    ),
    DartitectUiScenario(
      name: 'expanded-landscape-dark-ltr',
      size: Size(1024, 768),
      textScaleFactor: 2,
      textDirection: TextDirection.ltr,
      brightness: Brightness.dark,
      highContrast: false,
      reducedMotion: true,
      platform: TargetPlatform.macOS,
    ),
    DartitectUiScenario(
      name: 'expanded-desktop-light-ltr-a11y',
      size: Size(1440, 900),
      textScaleFactor: 1,
      textDirection: TextDirection.ltr,
      brightness: Brightness.light,
      highContrast: true,
      reducedMotion: true,
      platform: TargetPlatform.windows,
    ),
  ]);

  /// Ordered scenario rows.
  final List<DartitectUiScenario> scenarios;
}
