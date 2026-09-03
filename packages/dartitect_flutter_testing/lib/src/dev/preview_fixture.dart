import 'package:flutter/material.dart';

import '../preview_matrix.dart';

/// Immutable synthetic data used only by the private preview fixture.
final class PreviewTaskViewData {
  /// Creates fixture data.
  const PreviewTaskViewData({required this.title, required this.completed});

  /// Synthetic title.
  final String title;

  /// Synthetic completion state.
  final bool completed;
}

/// Value/callback-only reusable widget used by the private preview fixture.
final class PreviewTaskTile extends StatelessWidget {
  /// Creates a reusable tile.
  const PreviewTaskTile({
    required this.data,
    required this.onToggle,
    super.key,
  });

  /// Immutable values projected for presentation.
  final PreviewTaskViewData data;

  /// Pure consumer callback.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(data.title),
    leading: Checkbox(value: data.completed, onChanged: (_) => onToggle()),
  );
}

/// Discovers four Dartitect device previews without runtime providers or I/O.
@DartitectPreviewMatrix()
Widget dartitectPreviewFixture() => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: const Scaffold(
    body: PreviewTaskTile(
      data: PreviewTaskViewData(title: 'Synthetic task', completed: false),
      onToggle: _pureNoOp,
    ),
  ),
);

void _pureNoOp() {}
