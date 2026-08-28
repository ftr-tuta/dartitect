import 'dart:async';
import 'dart:io';

/// Internal shared lock for all Dartitect mutations in one project root.
abstract final class GenerationProjectLock {
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  /// Serializes [action] in-process and across processes at [root].
  static Future<T> synchronized<T>(
    Directory root,
    Future<T> Function() action,
  ) async {
    final absolute = root.absolute;
    final key = absolute.path;
    final previous = _tails[key] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = release.future;
    _tails[key] = tail;
    await previous;
    final file = File(_join(key, '.dartitect/project.lock'));
    RandomAccessFile? lock;
    try {
      await file.parent.create(recursive: true);
      lock = await file.open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      return await action();
    } finally {
      try {
        if (lock != null) {
          await lock.unlock();
          await lock.close();
        }
      } finally {
        release.complete();
        if (identical(_tails[key], tail)) unawaited(_tails.remove(key));
      }
    }
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}
