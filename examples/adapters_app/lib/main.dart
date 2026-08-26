import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import 'features/catalog/catalog_page.dart';
import 'runtime/adapters_runtime.dart';

/// Starts the optional-adapters reference application.
void main() => runApp(const AdaptersApp());

/// Root widget that owns and disposes the adapter runtime.
final class AdaptersApp extends StatefulWidget {
  /// Creates the adapters application.
  const AdaptersApp({super.key});

  @override
  State<AdaptersApp> createState() => _AdaptersAppState();
}

final class _AdaptersAppState extends State<AdaptersApp> {
  late final AdaptersRuntime runtime;
  late final FlutterErrorBinding errorBinding;

  @override
  void initState() {
    super.initState();
    runtime = AdaptersRuntime.create();
    errorBinding = FlutterErrorBinding.install(
      reporter: runtime.flutterCrashReporter,
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Optional adapters')),
      body: Column(
        children: <Widget>[
          Text(runtime.databaseCapability),
          Expanded(child: CatalogPage(viewModel: runtime.catalog)),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    errorBinding.dispose();
    unawaited(runtime.disposeAsync());
    super.dispose();
  }
}
