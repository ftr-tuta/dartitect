export 'widgets.dart';

import 'widgets.dart';

class RawMaterialButton extends Widget {
  const RawMaterialButton({this.onPressed});

  final void Function()? onPressed;
}

class IconButton extends Widget {
  const IconButton({this.onPressed, this.tooltip, required this.icon});

  final void Function()? onPressed;
  final String? tooltip;
  final Widget icon;
}

class Icon extends Widget {
  const Icon(this.icon, {this.semanticLabel});

  final Object icon;
  final String? semanticLabel;
}

abstract final class Icons {
  static const add = 'add';
}

abstract final class Colors {
  static const Object red = Object();
  static const Object indigo = Object();
}

class ThemeData {
  ThemeData({this.colorSchemeSeed});

  final Object? colorSchemeSeed;
}

class Container extends Widget {
  const Container({this.color});

  final Object? color;
}
