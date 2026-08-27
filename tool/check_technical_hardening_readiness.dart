import 'dart:convert';
import 'dart:io';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final value = jsonDecode(
    File('${root.path}/tool/technical_hardening_readiness.json')
        .readAsStringSync(),
  );
  final errors = <String>[];
  if (value is! Map<String, Object?>) {
    errors.add('Technical hardening readiness must be one JSON object.');
  } else {
    final authority = value['formalAuthority'];
    final role = value['humanRole'];
    final cells = value['nativeMatrix'];
    if (value['schemaVersion'] != 2 ||
        value['status'] != 'ACTIONS_READINESS_PENDING' ||
        authority is! Map<String, Object?> ||
        authority['workflow'] != 'CI' ||
        authority['requiredCheck'] != 'CI / Required' ||
        authority['branch'] != 'main' ||
        authority['artifact'] != 'actions-readiness-v1' ||
        authority['retentionDays'] != 90 ||
        role is! Map<String, Object?> ||
        role['technicalEvidence'] != false ||
        role['publicationTrigger'] != true ||
        cells is! List<Object?> ||
        cells.join(',') !=
            'android-media-floor-build,android-media-current-emulator,'
                'ios-media-floor-build,ios-privacy-floor-build,'
                'ios-current-simulator' ||
        value['localValidationCanDeclareReadiness'] != false) {
      errors.add(
        'Technical hardening must delegate readiness only to Actions.',
      );
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Technical hardening policy is fail-closed pending actions-readiness-v1.',
  );
}
