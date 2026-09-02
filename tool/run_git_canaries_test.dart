import 'package:test/test.dart';

import 'run_git_canaries.dart';

void main() {
  test('stable upgrade runs only for the distributed 1.0.0 cohort', () {
    expect(gitCanaryRunsLegacyStableUpgrade('1.0.0'), isTrue);
    expect(gitCanaryRunsLegacyStableUpgrade('1.1.0-rc.2'), isFalse);
    expect(gitCanaryRunsLegacyStableUpgrade('1.1.0'), isFalse);
  });

  test('local canary redirects canonical transitive Git dependencies', () {
    final environment = gitCanaryRepositoryRedirectEnvironment(
      canonicalRepository: 'https://example.test/dartitect.git',
      candidateRepository: 'file:///tmp/dartitect',
      inheritedEnvironment: const <String, String>{'GIT_CONFIG_COUNT': '2'},
    );

    expect(environment, <String, String>{
      'GIT_CONFIG_COUNT': '3',
      'GIT_CONFIG_KEY_2': 'url.file:///tmp/dartitect.insteadOf',
      'GIT_CONFIG_VALUE_2': 'https://example.test/dartitect.git',
    });
  });

  test('canonical canary repository needs no Git redirect', () {
    expect(
      gitCanaryRepositoryRedirectEnvironment(
        canonicalRepository: 'https://example.test/dartitect.git',
        candidateRepository: 'https://example.test/dartitect.git',
      ),
      isEmpty,
    );
  });
}
