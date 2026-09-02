export 'foundation.dart';

class Widget {
  const Widget();
}

class BuildContext {
  bool get mounted => true;
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget();

  Widget build(BuildContext context);
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget();

  State<StatefulWidget> createState();
}

abstract class State<T extends StatefulWidget> {
  BuildContext get context => BuildContext();
  bool get mounted => true;

  Widget build(BuildContext context);

  void setState(void Function() callback) => callback();

  void dispose() {}
}

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

class Text extends Widget {
  const Text(this.data);

  final String data;
}

class Column extends Widget {
  const Column({required this.children});

  final List<Widget> children;
}

class ScrollController {
  void dispose() {}
}

class TextEditingController {
  void dispose() {}
}

class ListView extends Widget {
  const ListView({this.children = const <Widget>[]});

  const ListView.builder({required int itemCount, required Object itemBuilder})
    : children = const <Widget>[];

  final List<Widget> children;
}

class GridView extends Widget {
  const GridView.builder({required int itemCount, required Object itemBuilder});
}

class SingleChildScrollView extends Widget {
  const SingleChildScrollView({required this.child});

  final Widget child;
}

class ListenableBuilder extends Widget {
  const ListenableBuilder({
    required Object listenable,
    required Widget Function(BuildContext, Widget?) builder,
    Widget? child,
  });
}

class Image extends Widget {
  const Image.network(String source, {double? width, double? height});
}

abstract final class Navigator {
  static Object of(BuildContext context) => Object();
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
