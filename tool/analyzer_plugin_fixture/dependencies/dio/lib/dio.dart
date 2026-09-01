final class Dio {
  final Interceptors interceptors = Interceptors();
}

final class Interceptors {
  void add(Object interceptor) {}
}

final class LogInterceptor {
  const LogInterceptor();
}
