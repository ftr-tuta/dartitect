import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await DartitectCliRunner().run(arguments);
}
