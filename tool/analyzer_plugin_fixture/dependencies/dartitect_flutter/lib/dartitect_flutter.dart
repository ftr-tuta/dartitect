import 'package:dartitect/dartitect.dart';

final class ApplicationHost<T> {
  const ApplicationHost.value({required BootstrapCoordinator<T> value});
}

final class SessionRuntimeController<R, D> implements AsyncDisposable {
  @override
  Future<void> disposeAsync() async {}
}

final class SessionHost<R, D> {
  const SessionHost.value({required SessionRuntimeController<R, D> value});
}

final class ViewModelHost<T> {
  const ViewModelHost.value({required T value});
}
