import 'package:dartitect/dartitect.dart';

/// Representative application-facing use compiled outside the SDK package.
Result<int, StateError> applicationResult(int value) => Ok<int>(value);

/// Representative extension method use from the application entrypoint.
int applicationValue(Result<int, StateError> result) =>
    result.fold((value) => value, (_, _) => -1);

/// Representative lifecycle ownership compiled from a consumer package.
ResourceOwner applicationOwner() => ResourceOwner(label: 'fixture');
