import 'package:flutter/material.dart';

enum CapabilityState {
  supported,
  unsupported,
  permissionRequired,
  permissionDenied,
  temporarilyUnavailable,
  providerFailure,
}

String projectCapability(CapabilityState state) => switch (state) {
  CapabilityState.supported => 'Ready',
  CapabilityState.permissionDenied => 'Denied',
  _ => 'Unavailable',
};

final class CapabilityApp extends StatelessWidget {
  const CapabilityApp({super.key, required this.state});

  final CapabilityState state;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(projectCapability(state)))),
  );
}

void main() =>
    runApp(const CapabilityApp(state: CapabilityState.temporarilyUnavailable));
