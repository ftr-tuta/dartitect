part of 'codec.dart';

/// Injected page verification policy; owns no transport, session or persistence.
abstract interface class TitectSyncIntegrityPolicy {
  /// Explicit capability advertised during bootstrap.
  String get capability;

  /// Rejects a page before publication, respecting the reader's allocation bounds.
  void verify(Map<String, Object?> envelope, TitectJsonCodec json);
}

/// Consumer-owned session context; selection never falls back to another policy.
final class TitectSyncIntegritySelection {
  /// Retains legacy structural validation and requires an absent confirmation.
  const TitectSyncIntegritySelection.none() : _policy = null, capability = null;

  TitectSyncIntegritySelection._(TitectSyncIntegrityPolicy policy)
    : _policy = policy,
      capability = policy.capability;

  /// Selects exactly one requested policy using the bootstrap response header.
  factory TitectSyncIntegritySelection.select({
    required Iterable<String> requested,
    required String? acknowledgement,
    required Iterable<TitectSyncIntegrityPolicy> policies,
  }) {
    final registry = <String, TitectSyncIntegrityPolicy>{};
    for (final policy in policies) {
      if (registry.length >= 32) _fail(TitectWireProblem.limit);
      final capability = policy.capability;
      if (capability.isEmpty || registry.containsKey(capability)) {
        _fail(TitectWireProblem.unsupported);
      }
      registry[capability] = policy;
    }
    TitectSyncIntegrityPolicy? selected;
    var count = 0;
    for (final name in requested) {
      if (++count > 32) _fail(TitectWireProblem.limit);
      if (!name.startsWith('integrity-') || name == 'integrity-sha-256')
        continue;
      if (selected != null || !registry.containsKey(name)) {
        _fail(TitectWireProblem.unsupported);
      }
      selected = registry[name];
    }
    final selection = selected == null
        ? const TitectSyncIntegritySelection.none()
        : TitectSyncIntegritySelection._(selected);
    selection.acknowledge(acknowledgement);
    return selection;
  }

  /// Response header used at bootstrap and on every subsequent selected read.
  static const header = 'Titect-Sync-Integrity';

  final TitectSyncIntegrityPolicy? _policy;

  /// Persist this capability with the consumer session, then explicitly restore it.
  final String? capability;

  /// Rejects missing, unsolicited or changed confirmation and mutated policies.
  void acknowledge(String? responseHeader) {
    if (responseHeader != capability || _policy?.capability != capability) {
      _fail(TitectWireProblem.integrity);
    }
  }
}

/// Normative SHA-256 over the domain prefix and complete exact page envelope.
final class TitectExactJsonSha256Integrity
    implements TitectSyncIntegrityPolicy {
  /// Creates a stateless policy for explicit consumer selection.
  const TitectExactJsonSha256Integrity();

  /// Negotiated exact JSON SHA-256 capability.
  static const capabilityName = 'integrity-sha-256-exact-json-v1';

  @override
  String get capability => capabilityName;

  String _digest(Map<String, Object?> envelope, TitectJsonCodec json) {
    final payload = _object(envelope['payload']);
    return sha256.convert([
      ...utf8.encode('titect-sync/1\u0000$capabilityName\u0000'),
      ...json.encode({
        ...envelope,
        'payload': {
          for (final entry in payload.entries)
            if (entry.key != 'integrity') entry.key: entry.value,
        },
      }, sortKeys: true),
    ]).toString();
  }

  @override
  void verify(Map<String, Object?> envelope, TitectJsonCodec json) {
    if (envelope['protocol'] != TitectSyncCodec.protocol ||
        !const {'snapshot', 'delta'}.contains(envelope['kind'])) {
      _fail(TitectWireProblem.shape);
    }
    final payload = _object(envelope['payload']);
    final upserts = payload['upserts'];
    final tombstones = payload['tombstones'] ?? const <Object?>[];
    if (upserts is! List<Object?> || tombstones is! List<Object?>) {
      _fail(TitectWireProblem.shape);
    }
    final integrity = payload['integrity'];
    if (integrity is! Map<String, Object?> ||
        integrity.length != 3 ||
        !const {
          'algorithm',
          'digest',
          'item_count',
        }.containsAll(integrity.keys)) {
      _fail(TitectWireProblem.integrity);
    }
    final digest = integrity['digest'];
    final count = integrity['item_count'];
    if (integrity['algorithm'] != 'sha-256' ||
        digest is! String ||
        digest.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        count is! TitectNumber ||
        !count.isInteger ||
        count.toBigIntExact() !=
            BigInt.from(upserts.length + tombstones.length)) {
      _fail(TitectWireProblem.integrity);
    }
    final expected = _digest(envelope, json);
    var difference = 0;
    for (var i = 0; i < 64; i++) {
      difference |= digest.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    if (difference != 0) _fail(TitectWireProblem.integrity);
  }

  /// Seals a validated page; the provider owns negotiation and publication.
  TitectPage seal(TitectPage page, {required TitectSyncCodec codec}) =>
      codec.fromPayload(page.kind, {
        ...page._payload,
        'integrity': {
          'algorithm': 'sha-256',
          'digest': _digest({
            'protocol': TitectSyncCodec.protocol,
            'kind': page.kind,
            'payload': page._payload,
          }, codec.json),
          'item_count':
              page.upserts.length +
              (page is TitectDeltaPage ? page.tombstones.length : 0),
        },
      }) as TitectPage;
}
