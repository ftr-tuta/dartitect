import 'dart:async';

/// One named, framework-neutral repository contract case.
final class RepositoryContractCase<R extends Object> {
  /// Creates a contract case.
  const RepositoryContractCase(this.name, this.verify);

  /// Stable case name.
  final String name;

  /// Consumer-provided assertions. Throw to report failure.
  final FutureOr<void> Function(R repository) verify;
}

/// Result of one repository contract case.
final class RepositoryContractCaseResult {
  /// Creates a successful result.
  const RepositoryContractCaseResult.success(this.name)
    : error = null,
      stackTrace = null;

  /// Creates a failed result.
  const RepositoryContractCaseResult.failure(
    this.name,
    this.error,
    this.stackTrace,
  );

  /// Contract case name.
  final String name;

  /// Assertion/factory/disposal failure.
  final Object? error;

  /// Original failure stack trace.
  final StackTrace? stackTrace;

  /// Whether the case passed.
  bool get succeeded => error == null;
}

/// Runs the same behavior contract against fresh repository instances.
///
/// No matcher or test-runner type is exported. Consumers translate returned
/// results into their preferred assertion API.
final class RepositoryContractHarness<R extends Object> {
  /// Creates a contract harness.
  const RepositoryContractHarness({
    required this.create,
    this.dispose,
    required this.cases,
  });

  /// Creates a fresh repository for each case.
  final FutureOr<R> Function() create;

  /// Optionally releases the fresh repository after each case.
  final FutureOr<void> Function(R repository)? dispose;

  /// Cases executed in declaration order.
  final List<RepositoryContractCase<R>> cases;

  /// Executes every case and captures failures without stopping the suite.
  Future<List<RepositoryContractCaseResult>> run() async {
    final results = <RepositoryContractCaseResult>[];
    for (final contractCase in cases) {
      R? repository;
      Object? failure;
      StackTrace? failureStack;
      try {
        repository = await create();
        await contractCase.verify(repository);
      } catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
      } finally {
        final release = dispose;
        if (repository != null && release != null) {
          try {
            await release(repository);
          } catch (error, stackTrace) {
            failure ??= error;
            failureStack ??= stackTrace;
          }
        }
      }
      results.add(
        failure == null
            ? RepositoryContractCaseResult.success(contractCase.name)
            : RepositoryContractCaseResult.failure(
                contractCase.name,
                failure,
                failureStack,
              ),
      );
    }
    return results;
  }
}
