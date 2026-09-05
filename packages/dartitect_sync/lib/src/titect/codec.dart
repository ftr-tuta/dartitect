import 'dart:convert';

import 'json.dart';

part 'documents.dart';

/// Explicit reader/writer for the closed `titect-sync/1` bundle.
///
/// Bounds default to the pinned Python profile. Transport bytes are bounded
/// before decoding. Payload schemas and cryptographic page verification remain
/// consumer-owned: the pinned bundle defines digest shape and item count, but
/// does not define bytes to hash. Capability negotiation is explicit.
final class TitectSyncCodec {
  /// Creates the profile codec with optional stricter transport/parser bounds.
  TitectSyncCodec({TitectJsonLimits? jsonLimits})
    : json = TitectJsonCodec(limits: jsonLimits) {
    final bounds = json.limits;
    final profile = TitectJsonLimits();
    if (bounds.maxBytes > profile.maxBytes ||
        bounds.maxDepth > profile.maxDepth ||
        bounds.maxItems > profile.maxItems ||
        bounds.maxStringScalars > profile.maxStringScalars) {
      throw ArgumentError('Titect sync bounds may only narrow the profile.');
    }
  }

  /// Exact protocol selector; no implicit version negotiation.
  static const protocol = 'titect-sync/1';

  /// Capabilities declared by the pinned bundle, not automatically enabled.
  static const capabilities = <String>{
    'delta',
    'integrity-sha-256',
    'mutations',
    'receipts',
    'snapshot',
    'trace-context',
  };

  /// Bounded numeric-preserving JSON boundary.
  final TitectJsonCodec json;

  /// Rejects requested capabilities outside the explicitly supported subset.
  void requireCapabilities(
    Iterable<String> requested, {
    required Set<String> supported,
  }) {
    var count = 0;
    final seen = <String>{};
    for (final capability in requested) {
      if (++count > 32) _fail(TitectWireProblem.limit);
      _id(capability, 64);
      if (!seen.add(capability)) _fail(TitectWireProblem.shape);
      if (!capabilities.contains(capability) ||
          !supported.contains(capability)) {
        _fail(TitectWireProblem.unsupported);
      }
    }
  }

  /// Reads a finite transport body and validates its closed document.
  Future<TitectSyncDocument> read(Stream<List<int>> chunks) async =>
      _document(await json.read(chunks));

  /// Decodes a finite byte sequence into one of eleven document types.
  TitectSyncDocument decode(List<int> bytes) => _document(json.decode(bytes));

  /// Constructs a document from consumer JSON, validating before publication.
  ///
  /// Use [TitectNumber] or [BigInt] for numbers outside the portable exact int
  /// range. Payloads are deeply copied into immutable bounded containers.
  TitectSyncDocument fromPayload(String kind, Map<String, Object?> payload) =>
      decode(
        json.encode({'protocol': protocol, 'kind': kind, 'payload': payload}),
      );

  /// Encodes a validated document without narrowing numbers or inspecting cursors.
  List<int> encode(TitectSyncDocument document) => json.encode({
    'protocol': protocol,
    'kind': document.kind,
    'payload': document._payload,
  });

  TitectSyncDocument _document(Object? value) {
    final envelope = _fields(value, {'protocol', 'kind', 'payload'});
    if (envelope['protocol'] != protocol) _fail(TitectWireProblem.unsupported);
    final kind = envelope['kind'];
    final payload = _object(envelope['payload']);
    switch (kind) {
      case 'session':
        _session(payload);
        return TitectSession._(payload);
      case 'dataset':
        _dataset(payload);
        return TitectDatasetDescriptor._(payload);
      case 'bootstrap_request':
        _fields(payload, {'client_id', 'dataset_ids', 'capabilities'});
        _id(payload['client_id']);
        final ids = _array(payload['dataset_ids'], 128, nonempty: true);
        _unique(ids);
        for (final id in ids) {
          _id(id);
        }
        final selected = _array(payload['capabilities'], 32);
        _unique(selected);
        for (final capability in selected) {
          _id(capability, 64);
        }
        // Unknown capability identifiers are legal wire values in /1. Explicit
        // adoption calls requireCapabilities before creating any resources.
        return TitectBootstrapRequest._(payload);
      case 'bootstrap_response':
        _fields(payload, {'session', 'datasets', 'limits'});
        _session(payload['session']);
        final datasets = _array(payload['datasets'], 128, nonempty: true);
        final identifiers = <Object?>[];
        for (final dataset in datasets) {
          _dataset(dataset);
          identifiers.add(_object(dataset)['dataset_id']);
        }
        _unique(identifiers);
        final limits = _fields(payload['limits'], {
          'max_document_bytes',
          'max_datasets',
          'max_items_per_page',
          'max_mutations',
          'max_opaque_id_bytes',
          'max_capabilities',
        });
        for (final value in limits.values) {
          _integer(value, positive: true);
        }
        return TitectBootstrapResponse._(payload);
      case 'snapshot' || 'delta':
        _fields(payload, {
          'dataset_id',
          'generation',
          'upserts',
          'next_cursor',
          'integrity',
          if (kind == 'delta') 'tombstones',
        });
        _id(payload['dataset_id']);
        _integer(payload['generation']);
        _optionalId(payload['next_cursor']);
        final upserts = _array(payload['upserts'], 1000);
        for (final raw in upserts) {
          final item = _fields(raw, {'item_id', 'revision', 'value'});
          _id(item['item_id']);
          _integer(item['revision']);
          // Upsert values also obey Python core's independent JSON bounds.
          TitectJsonCodec(limits: TitectJsonLimits(maxStringScalars: 16384))
              .encode(item['value']);
        }
        final tombstones = kind == 'delta'
            ? _array(payload['tombstones'], 1000 - upserts.length)
            : <Object?>[];
        for (final raw in tombstones) {
          final item = _fields(raw, {'item_id', 'revision', 'deleted_at'});
          _id(item['item_id']);
          _integer(item['revision']);
          _timestamp(item['deleted_at']);
        }
        final integrity = _fields(payload['integrity'], {
          'algorithm',
          'digest',
          'item_count',
        });
        if (integrity['algorithm'] != 'sha-256' ||
            integrity['digest'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$')
                .hasMatch(integrity['digest']! as String) ||
            _integer(integrity['item_count']) !=
                BigInt.from(upserts.length + tombstones.length)) {
          _fail(TitectWireProblem.integrity);
        }
        return kind == 'snapshot'
            ? TitectSnapshotPage._(payload)
            : TitectDeltaPage._(payload);
      case 'reset_required':
        _fields(payload, {'dataset_id', 'generation', 'reason'});
        _id(payload['dataset_id']);
        _integer(payload['generation']);
        _reason(payload['reason']);
        return TitectResetRequired._(payload);
      case 'generation_mismatch':
        _fields(payload, {'dataset_id', 'expected', 'actual'});
        _id(payload['dataset_id']);
        _integer(payload['expected']);
        _integer(payload['actual']);
        return TitectGenerationMismatch._(payload);
      case 'readiness':
        _fields(payload, {'ready', 'checked_at', 'reason', 'retry_after_ms'});
        _timestamp(payload['checked_at']);
        if (payload['ready'] is! bool) _fail(TitectWireProblem.shape);
        if (payload['ready'] == true) {
          if (payload['reason'] != null || payload['retry_after_ms'] != null)
            _fail(TitectWireProblem.integrity);
        } else {
          _reason(payload['reason']);
          if (payload['retry_after_ms'] != null)
            _integer(payload['retry_after_ms']);
        }
        return TitectReadiness._(payload);
      case 'mutation_outcome':
        _outcome(payload);
        return TitectMutationOutcome._(payload);
      case 'mutation_outcomes':
        _fields(payload, {'dataset_id', 'generation', 'outcomes'});
        _id(payload['dataset_id']);
        _integer(payload['generation']);
        final outcomes = _array(payload['outcomes'], 1000, nonempty: true);
        final ids = <Object?>[];
        for (final item in outcomes) {
          _outcome(item);
          ids.add(_object(item)['mutation_id']);
        }
        _unique(ids);
        return TitectMutationOutcomes._(payload);
      default:
        _fail(TitectWireProblem.unsupported);
    }
  }
}

Never _fail(TitectWireProblem problem) => throw TitectWireException(problem);

Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _fail(TitectWireProblem.shape);
Map<String, Object?> _fields(Object? value, Set<String> expected) {
  final result = _object(value);
  if (result.length != expected.length || !expected.containsAll(result.keys))
    _fail(TitectWireProblem.shape);
  return result;
}

List<Object?> _array(Object? value, int maximum, {bool nonempty = false}) {
  if (value is! List<Object?>) _fail(TitectWireProblem.shape);
  if (value.length > maximum || nonempty && value.isEmpty)
    _fail(TitectWireProblem.limit);
  return value;
}

void _unique(List<Object?> values) {
  if (values.toSet().length != values.length) _fail(TitectWireProblem.shape);
}

BigInt _integer(Object? value, {bool positive = false}) {
  if (value is! TitectNumber || !value.isInteger)
    _fail(TitectWireProblem.shape);
  final integer = value.toBigIntExact();
  if (integer < (positive ? BigInt.one : BigInt.zero))
    _fail(TitectWireProblem.shape);
  return integer;
}

// Python str.strip uses these Unicode whitespace scalars, including U+0085
// and U+001C..U+001F; Dart String.trim has a different set (notably U+FEFF).
bool _pythonSpace(int scalar) =>
    scalar >= 9 && scalar <= 13 ||
    scalar >= 28 && scalar <= 32 ||
    const {
      0x85,
      0xa0,
      0x1680,
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
    }.contains(scalar) ||
    scalar >= 0x2000 && scalar <= 0x200a;
bool _trimmed(String value) =>
    value.isNotEmpty &&
    !_pythonSpace(value.runes.first) &&
    !_pythonSpace(value.runes.last);
void _id(Object? value, [int maximum = 255]) {
  if (value is! String ||
      !_trimmed(value) ||
      value.runes.any((scalar) => scalar < 32))
    _fail(TitectWireProblem.shape);
  if (utf8.encode(value).length > maximum) _fail(TitectWireProblem.limit);
}

void _optionalId(Object? value) {
  if (value != null) _id(value);
}

void _reason(Object? value) {
  if (value is! String || !_trimmed(value)) _fail(TitectWireProblem.shape);
  if (utf8.encode(value).length > 1024) _fail(TitectWireProblem.limit);
}

DateTime _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$',
      ).hasMatch(value))
    _fail(TitectWireProblem.shape);
  final result = DateTime.tryParse(value);
  if (result == null || result.year == 0 || result.toIso8601String() != value)
    _fail(TitectWireProblem.integrity);
  return result;
}

void _session(Object? value) {
  final session = _fields(value, {'session_id', 'created_at', 'expires_at'});
  _id(session['session_id']);
  if (!_timestamp(session['expires_at'])
      .isAfter(_timestamp(session['created_at'])))
    _fail(TitectWireProblem.integrity);
}

void _dataset(Object? value) {
  final dataset = _fields(value, {'dataset_id', 'generation', 'modes'});
  _id(dataset['dataset_id']);
  _integer(dataset['generation']);
  final modes = _array(dataset['modes'], 2, nonempty: true);
  _unique(modes);
  if (modes.any((mode) => mode != 'snapshot' && mode != 'delta'))
    _fail(TitectWireProblem.unsupported);
}

void _outcome(Object? value) {
  final outcome = _fields(value, {
    'mutation_id',
    'state',
    'revision',
    'receipt_id',
    'reason',
  });
  _id(outcome['mutation_id']);
  _optionalId(outcome['receipt_id']);
  if (outcome['state'] == 'applied') {
    _integer(outcome['revision']);
    if (outcome['reason'] != null) _fail(TitectWireProblem.integrity);
  } else {
    if (!const {'rejected', 'conflict', 'uncertain'}.contains(outcome['state']))
      _fail(TitectWireProblem.unsupported);
    if (outcome['revision'] != null) _fail(TitectWireProblem.integrity);
    _reason(outcome['reason']);
  }
}
