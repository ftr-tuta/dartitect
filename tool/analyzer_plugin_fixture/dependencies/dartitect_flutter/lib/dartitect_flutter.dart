import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

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

final class ViewModelHost<T> extends Widget {
  const ViewModelHost.create({required T Function() create});

  const ViewModelHost.value({required T value});
}

abstract class DartitectViewModel implements AsyncDisposable {}

class SessionState<S extends Object> {
  const SessionState();
}

final class SessionStateController<S extends Object> {
  const SessionStateController();
}
