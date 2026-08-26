import 'dart:async';

import 'package:dartitect/dartitect.dart';

Future<void> main() async {
  final owner = ResourceOwner(label: 'AppRuntime');
  owner.own(StreamController<void>(), (controller) => controller.close());

  final Result<int, StateError> result = const Ok<int>(42);
  final message = switch (result) {
    Ok<dynamic>(:final value) => 'value: ${value as int}',
    Err<Object>(:final failure) => 'failure: $failure',
  };
  // ignore: avoid_print
  print(message);

  await owner.disposeAsync();
}
