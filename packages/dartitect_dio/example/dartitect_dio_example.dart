import 'package:dartitect_dio/dartitect_dio.dart';

/// Creates and deterministically closes an owned Dio client without networking.
void main() {
  const capture = DioObservabilityCapturePolicy.metadataOnly();
  assert(capture.mode == DioObservabilityCaptureMode.metadataOnly);
  final owner = DioOwner.create();
  try {
    assert(owner.ownsClient);
    assert(!owner.isDisposed);
  } finally {
    owner.dispose();
  }
}
