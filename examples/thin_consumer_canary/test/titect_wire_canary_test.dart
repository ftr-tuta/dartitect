import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional Titect entrypoint preserves exact downstream wire values', () {
    final codec = TitectSyncCodec();
    final document = codec.fromPayload('dataset', {
      'dataset_id': 'consumer-items',
      'generation': BigInt.parse('9007199254740993'),
      'modes': ['delta'],
    });
    final decoded =
        codec.decode(codec.encode(document)) as TitectDatasetDescriptor;
    expect(decoded.generation.toString(), '9007199254740993');
    codec.requireCapabilities(['delta'], supported: {'delta'});
  });
}
