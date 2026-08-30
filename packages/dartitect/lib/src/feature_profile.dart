/// Stable behavioral profiles understood across Dartitect tooling and tests.
enum FeatureProfile {
  /// Device-local behavior with no transport or synchronization capability.
  local('local'),

  /// Remote authority without durable local persistence.
  online('online'),

  /// Remote authority with a durable local cache.
  cache('cache'),

  /// Locally queryable synchronized replica.
  replica('replica'),

  /// Replica plus durable offline mutation delivery.
  offlineFull('offline-full');

  const FeatureProfile(this.wireName);

  /// Stable CLI and configuration spelling.
  final String wireName;

  /// Parses a stable profile name.
  static FeatureProfile parse(String value) {
    for (final profile in values) {
      if (profile.wireName == value) return profile;
    }
    throw FormatException('Unknown feature profile "$value".');
  }
}
