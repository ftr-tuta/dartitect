// GENERATED CODE - DO NOT EDIT BY HAND.
// ignore_for_file: public_member_api_docs

import 'package:dartitect_workmanager/dartitect_workmanager.dart';

/// Versioned headless envelope factory for the OfflineFullSession3 feature.
abstract final class OfflineFullSession3WorkmanagerJob {
  static DartitectWorkmanagerEnvelope create({
    required String jobId,
    required DateTime deadline,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => DartitectWorkmanagerEnvelope(
    jobId: jobId,
    definition: 'offline_full_session_3',
    deadline: deadline,
    payload: payload,
  );
}
