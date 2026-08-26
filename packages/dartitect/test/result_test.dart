import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  String describe(Result<int, FormatException> result) => switch (result) {
    Ok<dynamic>(:final value) => 'ok:${value as int}',
    Err<Object>(:final failure, :final stackTrace) =>
      'err:${(failure as FormatException).message}:${stackTrace == StackTrace.empty}',
  };

  test('supports exhaustive matching for success and typed failure', () {
    expect(describe(const Ok<int>(42)), 'ok:42');
    expect(
      describe(
        Err<FormatException>(const FormatException('broken'), StackTrace.empty),
      ),
      'err:broken:true',
    );
  });

  test('preserves the exact typed failure and stack trace', () {
    final failure = ArgumentError('bad input');
    final stackTrace = StackTrace.current;
    final result = Err<ArgumentError>(failure, stackTrace);

    expect(result.failure, same(failure));
    expect(result.stackTrace, same(stackTrace));
  });

  test('map transforms only a success', () {
    final success = const Ok<int>(3).map((value) => '$value!');
    final failure = Err<FormatException>(
      const FormatException('bad'),
      StackTrace.empty,
    ).map((Never value) => value);

    expect(success, isA<Ok<String>>());
    expect((success as Ok<String>).value, '3!');
    expect(failure, isA<Err<FormatException>>());
  });

  test('mapFailure transforms only a failure and keeps its stack', () {
    final stackTrace = StackTrace.current;
    final result = Err<FormatException>(
      const FormatException('bad'),
      stackTrace,
    ).mapFailure((failure) => StateError(failure.message));

    expect(result, isA<Err<StateError>>());
    expect((result as Err<StateError>).failure.message, 'bad');
    expect(result.stackTrace, same(stackTrace));
    expect(const Ok<int>(1).mapFailure(StateError.new), isA<Ok<int>>());
  });

  test('flatMap and fold preserve explicit control flow', () {
    Result<int, FormatException> parse(String source) {
      final value = int.tryParse(source);
      return value == null
          ? Err<FormatException>(
              FormatException('not an integer: $source'),
              StackTrace.current,
            )
          : Ok<int>(value);
    }

    final Result<String, FormatException> successInput = const Ok<String>('4');
    final Result<String, FormatException> failureInput = const Ok<String>('x');
    final success = successInput.flatMap(parse);
    final failure = failureInput.flatMap(parse);

    expect(success.fold((value) => value * 2, (_, _) => -1), 8);
    expect(failure.fold((value) => value, (_, _) => -1), -1);
  });
}
