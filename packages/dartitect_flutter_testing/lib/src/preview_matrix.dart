import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

import 'ui_matrix.dart';

const _dartitectPreviewGroup = 'Dartitect';

/// Four device-oriented Flutter previews for Dartitect consumer widgets.
///
/// Accessibility, directionality, contrast, motion, semantics, focus, and
/// keyboard coverage remain the responsibility of [DartitectUiMatrix].
final class DartitectPreviewMatrix extends MultiPreview {
  /// Creates the constant multi-preview annotation.
  const DartitectPreviewMatrix();

  @override
  // Flutter requires a field initializer for constant MultiPreview annotations.
  // ignore: avoid_field_initializers_in_const_classes
  final List<Preview> previews = const <Preview>[
    Preview(
      group: _dartitectPreviewGroup,
      name: 'compact',
      size: Size(360, 640),
      brightness: Brightness.light,
      textScaleFactor: 1,
    ),
    Preview(
      group: _dartitectPreviewGroup,
      name: 'compact-200-percent',
      size: Size(430, 932),
      brightness: Brightness.dark,
      textScaleFactor: 2,
    ),
    Preview(
      group: _dartitectPreviewGroup,
      name: 'medium',
      size: Size(768, 1024),
      brightness: Brightness.light,
      textScaleFactor: 1,
    ),
    Preview(
      group: _dartitectPreviewGroup,
      name: 'expanded',
      size: Size(1440, 900),
      brightness: Brightness.light,
      textScaleFactor: 1,
    ),
  ];
}
