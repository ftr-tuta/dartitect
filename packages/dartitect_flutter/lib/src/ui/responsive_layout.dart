// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'package:flutter/widgets.dart';

/// One business-neutral class of available space.
enum DartitectSizeClass {
  /// Space below the first configured breakpoint.
  compact,

  /// Space from the first breakpoint up to the second breakpoint.
  medium,

  /// Space at or above the second configured breakpoint.
  expanded,
}

/// Width and height classes measured independently.
final class DartitectWindowClass {
  /// Creates one classified pair.
  const DartitectWindowClass({required this.width, required this.height});

  /// Class derived from available width.
  final DartitectSizeClass width;

  /// Class derived from available height.
  final DartitectSizeClass height;

  @override
  bool operator ==(Object other) =>
      other is DartitectWindowClass &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() =>
      'DartitectWindowClass(width: ${width.name}, height: ${height.name})';
}

/// Validated, consumer-configurable layout breakpoints.
///
/// Values exactly on a breakpoint belong to the larger class. Breakpoints
/// describe available space and never imply a device kind or orientation.
final class DartitectLayoutBreakpoints {
  /// Creates validated width and height breakpoints.
  factory DartitectLayoutBreakpoints({
    double mediumWidth = 600,
    double expandedWidth = 840,
    double mediumHeight = 480,
    double expandedHeight = 900,
  }) {
    _validatePair(mediumWidth, expandedWidth, 'width');
    _validatePair(mediumHeight, expandedHeight, 'height');
    return DartitectLayoutBreakpoints._(
      mediumWidth: mediumWidth,
      expandedWidth: expandedWidth,
      mediumHeight: mediumHeight,
      expandedHeight: expandedHeight,
    );
  }

  const DartitectLayoutBreakpoints._({
    required this.mediumWidth,
    required this.expandedWidth,
    required this.mediumHeight,
    required this.expandedHeight,
  });

  /// Material 3 window-size breakpoint preset.
  static const material3 = DartitectLayoutBreakpoints._(
    mediumWidth: 600,
    expandedWidth: 840,
    mediumHeight: 480,
    expandedHeight: 900,
  );

  /// First width assigned to [DartitectSizeClass.medium].
  final double mediumWidth;

  /// First width assigned to [DartitectSizeClass.expanded].
  final double expandedWidth;

  /// First height assigned to [DartitectSizeClass.medium].
  final double mediumHeight;

  /// First height assigned to [DartitectSizeClass.expanded].
  final double expandedHeight;

  /// Classifies [size] on both axes.
  DartitectWindowClass classify(Size size) {
    if (!size.width.isFinite || !size.height.isFinite) {
      throw ArgumentError.value(size, 'size', 'Both axes must be finite.');
    }
    if (size.width < 0 || size.height < 0) {
      throw ArgumentError.value(
        size,
        'size',
        'Both axes must be non-negative.',
      );
    }
    return DartitectWindowClass(
      width: classifyWidth(size.width),
      height: classifyHeight(size.height),
    );
  }

  /// Classifies one finite, non-negative width.
  DartitectSizeClass classifyWidth(double width) => _classify(
    width,
    medium: mediumWidth,
    expanded: expandedWidth,
    name: 'width',
  );

  /// Classifies one finite, non-negative height.
  DartitectSizeClass classifyHeight(double height) => _classify(
    height,
    medium: mediumHeight,
    expanded: expandedHeight,
    name: 'height',
  );

  static DartitectSizeClass _classify(
    double value, {
    required double medium,
    required double expanded,
    required String name,
  }) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and non-negative.',
      );
    }
    if (value < medium) return DartitectSizeClass.compact;
    if (value < expanded) return DartitectSizeClass.medium;
    return DartitectSizeClass.expanded;
  }

  static void _validatePair(double medium, double expanded, String axis) {
    if (!medium.isFinite || !expanded.isFinite) {
      throw ArgumentError('$axis breakpoints must be finite.');
    }
    if (medium < 0 || expanded < 0) {
      throw ArgumentError('$axis breakpoints must be non-negative.');
    }
    if (medium >= expanded) {
      throw ArgumentError(
        '$axis breakpoints must be strictly increasing: '
        '$medium must be less than $expanded.',
      );
    }
  }
}

/// Callback for one required responsive branch.
typedef DartitectResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  DartitectWindowClass windowClass,
);

/// Selects a width branch from the complete window size in [MediaQuery].
///
/// State, controllers, restoration, navigation, and visual decisions belong
/// above this widget. Switching branches has ordinary Flutter element-tree
/// semantics and does not preserve state implicitly.
final class DartitectResponsiveWindowBuilder extends StatelessWidget {
  /// Creates a complete three-branch window renderer.
  const DartitectResponsiveWindowBuilder({
    required this.compact,
    required this.medium,
    required this.expanded,
    this.breakpoints = DartitectLayoutBreakpoints.material3,
    super.key,
  });

  /// Renders when available width is compact.
  final DartitectResponsiveWidgetBuilder compact;

  /// Renders when available width is medium.
  final DartitectResponsiveWidgetBuilder medium;

  /// Renders when available width is expanded.
  final DartitectResponsiveWidgetBuilder expanded;

  /// Space classification policy.
  final DartitectLayoutBreakpoints breakpoints;

  @override
  Widget build(BuildContext context) {
    final windowClass = breakpoints.classify(MediaQuery.sizeOf(context));
    return switch (windowClass.width) {
      DartitectSizeClass.compact => compact(context, windowClass),
      DartitectSizeClass.medium => medium(context, windowClass),
      DartitectSizeClass.expanded => expanded(context, windowClass),
    };
  }
}

/// Selects a width branch from the constraints of one layout region.
///
/// The region must have a finite maximum width. A bounded height uses the
/// maximum height; an unbounded height uses its finite minimum height, or zero
/// when the region imposes no height bound.
final class DartitectResponsiveRegionBuilder extends StatelessWidget {
  /// Creates a complete three-branch region renderer.
  const DartitectResponsiveRegionBuilder({
    required this.compact,
    required this.medium,
    required this.expanded,
    this.breakpoints = DartitectLayoutBreakpoints.material3,
    super.key,
  });

  /// Renders when region width is compact.
  final DartitectResponsiveWidgetBuilder compact;

  /// Renders when region width is medium.
  final DartitectResponsiveWidgetBuilder medium;

  /// Renders when region width is expanded.
  final DartitectResponsiveWidgetBuilder expanded;

  /// Space classification policy.
  final DartitectLayoutBreakpoints breakpoints;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.maxWidth.isFinite) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'DartitectResponsiveRegionBuilder requires a finite width.',
          ),
          ErrorDescription(
            'Constrain the region before selecting a responsive branch.',
          ),
        ]);
      }
      final height = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : constraints.minHeight.isFinite
          ? constraints.minHeight
          : 0.0;
      final windowClass = breakpoints.classify(
        Size(constraints.maxWidth, height),
      );
      return switch (windowClass.width) {
        DartitectSizeClass.compact => compact(context, windowClass),
        DartitectSizeClass.medium => medium(context, windowClass),
        DartitectSizeClass.expanded => expanded(context, windowClass),
      };
    },
  );
}
