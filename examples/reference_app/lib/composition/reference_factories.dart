// ignore_for_file: public_member_api_docs

import 'package:dartitect/dartitect.dart';

import '../app/app_runtime.dart';

@DartitectApplicationContextFactory('reference_runtime')
final class ReferenceRuntimeFactory {
  const ReferenceRuntimeFactory();

  Future<AppRuntime> open() => AppRuntime.create();

  Future<void> dispose(AppRuntime runtime) => runtime.disposeAsync();
}

final class ReferenceTransport {
  const ReferenceTransport();
}

@DartitectTransportContextFactory('reference_transport')
final class ReferenceTransportFactory {
  const ReferenceTransportFactory();

  ReferenceTransport open() => const ReferenceTransport();

  void dispose(ReferenceTransport transport) {}
}
