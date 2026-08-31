class Widget {
  const Widget();
}

class BuildContext {}

enum Orientation { portrait, landscape }

class Size {
  const Size(this.width, this.height);

  final double width;
  final double height;
}

class SizedBox extends Widget {
  const SizedBox({this.width, this.child});

  final double? width;
  final Widget? child;
}

class OrientationBuilder extends Widget {
  const OrientationBuilder({required this.builder});

  final Widget Function(BuildContext, Orientation) builder;
}

class MediaQuery {
  static Object of(BuildContext context) => Object();

  static Size sizeOf(BuildContext context) => const Size(0, 0);
}

class GestureDetector extends Widget {
  const GestureDetector({this.onTap, required this.child});

  final void Function()? onTap;
  final Widget child;
}

class Semantics extends Widget {
  const Semantics({this.label, this.button, required this.child});

  final String? label;
  final bool? button;
  final Widget child;
}
