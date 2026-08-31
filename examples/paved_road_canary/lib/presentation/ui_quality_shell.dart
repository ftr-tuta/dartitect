import 'package:dartitect_flutter/dartitect_flutter_ui.dart';
import 'package:flutter/material.dart';

/// Consumer-owned Material shell used as responsive canary evidence.
final class CanaryUiShell extends StatelessWidget {
  const CanaryUiShell({required this.body, super.key});

  final Widget body;

  @override
  Widget build(BuildContext context) => DartitectResponsiveWindowBuilder(
    compact: (context, window) => Scaffold(
      appBar: AppBar(title: const Text('Dartitect UI canary')),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    ),
    medium: (context, window) => _rail(extended: false),
    expanded: (context, window) => _rail(extended: true),
  );

  Widget _rail({required bool extended}) => Scaffold(
    appBar: AppBar(title: const Text('Dartitect UI canary')),
    body: Row(
      children: <Widget>[
        NavigationRail(
          extended: extended,
          selectedIndex: 0,
          destinations: const <NavigationRailDestination>[
            NavigationRailDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: Text('Overview'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: Text('Settings'),
            ),
          ],
        ),
        Expanded(child: body),
      ],
    ),
  );
}
