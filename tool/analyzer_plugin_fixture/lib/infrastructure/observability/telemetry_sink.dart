import 'package:sentry/sentry.dart';

Future<void> reportTelemetry(Scope scope) async {
  await scope.setContexts('authentication', <String, Object?>{
    'authorization_token': 'must-be-redacted',
  });
}
