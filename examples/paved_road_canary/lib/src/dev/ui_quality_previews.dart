// Preview annotations are deliberately dev-only and never runtime-reachable.
// ignore_for_file: depend_on_referenced_packages

import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart';
import 'package:flutter/material.dart';

import '../../presentation/ui_quality_shell.dart';

/// Discovers responsive shell and exhaustive synthetic command-state previews.
@DartitectPreviewMatrix()
Widget pavedRoadQualityPreview() =>
    const MaterialApp(home: CanaryUiShell(body: _PreviewCommandStates()));

final class _PreviewCommandStates extends StatelessWidget {
  const _PreviewCommandStates();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: const <Widget>[
      _PreviewStateCard(label: 'Command idle', icon: Icons.pause_circle),
      _PreviewStateCard(label: 'Command running', icon: Icons.sync),
      _PreviewStateCard(label: 'Command success', icon: Icons.check_circle),
      _PreviewStateCard(label: 'Expected failure', icon: Icons.info),
      _PreviewStateCard(label: 'Command cancelled', icon: Icons.cancel),
      _PreviewStateCard(label: 'Unexpected crash', icon: Icons.error),
    ],
  );
}

final class _PreviewStateCard extends StatelessWidget {
  const _PreviewStateCard({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(leading: Icon(icon), title: Text(label)),
  );
}
