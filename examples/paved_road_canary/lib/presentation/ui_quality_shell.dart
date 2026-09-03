import 'package:dartitect_flutter/dartitect_flutter_ui.dart';
import 'package:flutter/material.dart';

/// Consumer-owned Material shell used as responsive canary evidence.
final class CanaryUiShell extends StatefulWidget {
  const CanaryUiShell({required this.body, super.key});

  final Widget body;

  @override
  State<CanaryUiShell> createState() => _CanaryUiShellState();
}

final class _CanaryUiShellState extends State<CanaryUiShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) => DartitectResponsiveWindowBuilder(
    compact: (context, window) => Scaffold(
      appBar: AppBar(title: const Text('Dartitect UI canary')),
      body: widget.body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
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
          selectedIndex: _selectedIndex,
          onDestinationSelected: _select,
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
        Expanded(child: widget.body),
      ],
    ),
  );

  void _select(int value) {
    if (_selectedIndex == value) return;
    setState(() => _selectedIndex = value);
  }
}
