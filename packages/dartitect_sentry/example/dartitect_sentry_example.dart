import 'package:dartitect_sentry/dartitect_sentry.dart';
import 'package:sentry/sentry.dart';

/// Creates an adapter around a Hub already initialized and owned by a consumer.
///
/// This example performs no network call and contains no DSN.
SentryLogSink attachDartitectLogs(Hub consumerOwnedHub) =>
    SentryLogSink(hub: consumerOwnedHub);
