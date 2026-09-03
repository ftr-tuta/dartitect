enum TargetPlatform { android, iOS, linux, macOS, windows, fuchsia }

const defaultTargetPlatform = TargetPlatform.android;
const kIsWeb = false;

class ChangeNotifier {
  void dispose() {}
}

class ValueNotifier<T> extends ChangeNotifier {
  ValueNotifier(this.value);

  T value;
}
