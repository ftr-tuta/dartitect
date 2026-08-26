import 'package:dartitect/dartitect.dart';
import 'package:dartitect/src/id_generator.dart';
import 'package:test/test.dart';

void main() {
  test('deterministic bytes produce RFC 9562 version and variant bits', () {
    expect(
      formatUuidV4RandomBytes(List<int>.generate(16, (index) => index)),
      '00010203-0405-4607-8809-0a0b0c0d0e0f',
    );
    expect(
      formatUuidV4RandomBytes(List<int>.filled(16, 0xff)),
      'ffffffff-ffff-4fff-bfff-ffffffffffff',
    );
  });

  test(
    'secure generator returns unique lowercase canonical UUID v4 values',
    () {
      final generator = SecureUuidV4Generator();
      final values = <String>{
        for (var index = 0; index < 64; index += 1) generator.nextId(),
      };
      expect(values, hasLength(64));
      expect(
        values,
        everyElement(
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        ),
      );
    },
  );
}
