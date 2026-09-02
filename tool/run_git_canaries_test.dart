import 'package:test/test.dart';

import 'run_git_canaries.dart';

void main() {
  test('stable upgrade runs only for the distributed 1.0.0 cohort', () {
    expect(gitCanaryRunsLegacyStableUpgrade('1.0.0'), isTrue);
    expect(gitCanaryRunsLegacyStableUpgrade('1.1.0-rc.1'), isFalse);
    expect(gitCanaryRunsLegacyStableUpgrade('1.1.0'), isFalse);
  });
}
