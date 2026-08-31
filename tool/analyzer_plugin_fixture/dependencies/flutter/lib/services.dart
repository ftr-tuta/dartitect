enum DeviceOrientation {
  portraitUp,
  portraitDown,
  landscapeLeft,
  landscapeRight,
}

abstract final class SystemChrome {
  static void setPreferredOrientations(List<DeviceOrientation> orientations) {}
}
