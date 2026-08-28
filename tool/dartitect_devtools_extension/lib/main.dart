import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

const _capabilitiesMethod = 'ext.dartitect.capabilities';
const _snapshotMethod = 'ext.dartitect.snapshot';

void main() =>
    runApp(const DevToolsExtension(child: DartitectReadOnlyInspector()));

class DartitectReadOnlyInspector extends StatelessWidget {
  const DartitectReadOnlyInspector({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const _InspectorPage(),
  );
}

class _InspectorPage extends StatefulWidget {
  const _InspectorPage();

  @override
  State<_InspectorPage> createState() => _InspectorPageState();
}

class _InspectorPageState extends State<_InspectorPage> {
  Map<String, Object?>? _capabilities;
  List<Map<String, Object?>> _events = const <Map<String, Object?>>[];
  bool _loading = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final capabilityResponse = await serviceManager
          .callServiceExtensionOnMainIsolate(_capabilitiesMethod);
      final snapshotResponse = await serviceManager
          .callServiceExtensionOnMainIsolate(_snapshotMethod);
      final capabilities = capabilityResponse.json;
      final snapshot = snapshotResponse.json;
      final rawEvents = snapshot?['events'];
      if (capabilities == null || rawEvents is! List<Object?>) {
        throw const FormatException('Invalid diagnostics response.');
      }
      if (!mounted) return;
      setState(() {
        _capabilities = capabilities.cast<String, Object?>();
        _events = rawEvents
            .whereType<Map<Object?, Object?>>()
            .map(
              (event) =>
                  event.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = 'Read-only diagnostics are unavailable for this isolate.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dartitect diagnostics'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh snapshot',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_loading) const LinearProgressIndicator(),
          if (_status case final status?)
            Padding(padding: const EdgeInsets.all(16), child: Text(status)),
          if (capabilities != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                children: <Widget>[
                  Text(
                    'Protocol ${capabilities['diagnosticsProtocolVersion']}',
                  ),
                  Text('Detail ${capabilities['detail']}'),
                  Text('Capacity ${capabilities['bufferCapacity']}'),
                  const Text('Read only'),
                ],
              ),
            ),
          Expanded(
            child: _events.isEmpty
                ? const Center(child: Text('No retained diagnostic events.'))
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${event['subjectKind']} · ${event['phase']}',
                        ),
                        subtitle: Text(
                          'generation ${event['generation']} · '
                          'revision ${event['revision']} · '
                          't+${event['monotonicMicros']}µs',
                        ),
                        trailing: Text('#${event['sequence']}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
