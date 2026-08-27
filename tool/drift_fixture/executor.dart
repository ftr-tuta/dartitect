export 'executor_stub.dart'
    if (dart.library.ffi) 'executor_native.dart'
    if (dart.library.js_interop) 'executor_web.dart';
