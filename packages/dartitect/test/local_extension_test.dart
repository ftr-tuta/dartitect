import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('local extension contract builds and disposes its concrete binding', () {
    final extension = _TestExtension();
    final binding = extension.build();

    expect(binding.disposed, isFalse);
    extension.dispose(binding);
    expect(binding.disposed, isTrue);
  });
}

final class _TestBinding {
  var disposed = false;
}

final class _TestExtension implements DartitectLocalExtension<_TestBinding> {
  @override
  _TestBinding build() => _TestBinding();

  @override
  void dispose(_TestBinding binding) => binding.disposed = true;
}
