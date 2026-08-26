import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selector fan-out publishes only distinct selected values', () {
    for (final size in <int>[1, 10, 100, 1000]) {
      for (final changed in <int>[0, (size * 0.1).round(), size]) {
        final source = _FanOutModel(size);
        final selectors = List<ReactiveSelector<_FanOutModel, int>>.generate(
          size,
          (index) => ReactiveSelector<_FanOutModel, int>(
            source: source,
            select: (model) => model.values[index],
          ),
        );
        var callbacks = 0;
        void listener() => callbacks += 1;
        for (final selector in selectors) {
          selector.addListener(listener);
        }

        source.changeFirst(changed);

        expect(callbacks, changed, reason: 'size=$size changed=$changed');
        expect(
          selectors.fold<int>(
            0,
            (count, selector) => count + selector.notificationCount,
          ),
          changed,
        );
        expect(
          selectors.every((selector) => selector.selectionCount == 2),
          isTrue,
        );
        for (final selector in selectors.reversed) {
          selector.dispose();
        }
        expect(source.listenerCount, 0);
      }
    }
  });

  test('selector supports consumer equality and terminal disposal', () {
    final source = _TrackedValueNotifier<List<int>>(<int>[1]);
    final selector =
        ReactiveSelector<_TrackedValueNotifier<List<int>>, List<int>>(
          source: source,
          select: (value) => List<int>.of(value.value),
          equals: _sameInts,
        );
    var callbacks = 0;
    selector.addListener(() => callbacks += 1);

    source.value = <int>[1];
    source.value = <int>[1, 2];

    expect(callbacks, 1);
    expect(selector.value, <int>[1, 2]);
    selector.dispose();
    expect(source.listenerCount, 0);
    expect(() => selector.value, throwsStateError);
    source.dispose();
  });

  test('debounce publishes latest value and cancels timer on dispose', () {
    final timers = _FakeTimerFactory();
    final source = _TrackedValueNotifier<int>(0);
    final debounced = DebouncedReactiveValue<int>(
      source: source,
      delay: const Duration(milliseconds: 300),
      timerFactory: timers,
    );
    var callbacks = 0;
    debounced.addListener(() => callbacks += 1);

    source.value = 1;
    source.value = 2;
    expect(debounced.value, 0);
    expect(debounced.activeTimerCount, 1);
    expect(timers.activeCount, 1);
    timers.advance(const Duration(milliseconds: 299));
    expect(callbacks, 0);
    timers.advance(const Duration(milliseconds: 1));
    expect(debounced.value, 2);
    expect(callbacks, 1);
    expect(debounced.activeTimerCount, 0);

    source.value = 3;
    expect(debounced.flush(), isTrue);
    expect(debounced.value, 3);
    expect(callbacks, 2);
    source.value = 4;
    debounced.dispose();
    expect(timers.activeCount, 0);
    expect(source.listenerCount, 0);
    timers.advance(const Duration(seconds: 1));
    expect(callbacks, 2);
    source.dispose();
  });
}

final class _FanOutModel extends ChangeNotifier {
  _FanOutModel(int size) : values = List<int>.filled(size, 0);

  final List<int> values;
  var listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    listenerCount += 1;
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    listenerCount -= 1;
  }

  void changeFirst(int count) {
    for (var index = 0; index < count; index += 1) {
      values[index] += 1;
    }
    notifyListeners();
  }
}

final class _TrackedValueNotifier<T> extends ValueNotifier<T> {
  _TrackedValueNotifier(super.value);

  var listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    listenerCount += 1;
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    listenerCount -= 1;
  }
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _FakeTimerFactory implements ReactiveTimerFactory {
  final List<_FakeTimer> _timers = <_FakeTimer>[];
  Duration _elapsed = Duration.zero;

  int get activeCount => _timers.where((timer) => timer.isActive).length;

  @override
  ReactiveTimerHandle schedule(Duration duration, void Function() callback) {
    final timer = _FakeTimer(_elapsed + duration, callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    _elapsed += duration;
    final due = _timers
        .where((timer) => timer.isActive && timer.deadline <= _elapsed)
        .toList(growable: false);
    for (final timer in due) {
      timer.fire();
    }
  }
}

final class _FakeTimer implements ReactiveTimerHandle {
  _FakeTimer(this.deadline, this._callback);

  final Duration deadline;
  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}
