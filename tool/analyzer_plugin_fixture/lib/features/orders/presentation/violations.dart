import 'package:sentry/sentry.dart';

void violate() {
  print(SentryId.empty());
  try {
    throw StateError('fixture');
  } on StateError catch (_) {}
  final metadata = <String, Object?>{'authorization_token': 'fixture'};
  metadata.clear();
}
