import 'package:dartitect/dartitect.dart';
import 'package:dartitect_devtools/dartitect_devtools.dart';

void main() {
  final buffer = DartitectDiagnosticBuffer(capacity: 32);
  final registration = DartitectDevToolsRegistration.register(
    enabled: false,
    buffer: buffer,
    detail: DartitectDiagnosticDetail.topology,
  );

  registration.dispose();
  buffer.dispose();
}
