import 'package:dartitect_workmanager/dartitect_workmanager.dart';

void main() {
  final capability = DartitectWorkmanagerCapability.forPlatform(
    DartitectWorkmanagerPlatform.android,
  );
  final envelope = DartitectWorkmanagerEnvelope(
    jobId: 'catalog-refresh-42',
    definition: 'catalog-refresh',
    deadline: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    payload: const <String, Object?>{'dataset': 'catalog'},
  );

  assert(capability.supported && envelope.definition == 'catalog-refresh');
}
