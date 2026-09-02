part of '../flutter_quality_performance_test.dart';

final class _FlutterQualityProbe {
  final Stopwatch _clock = Stopwatch()..start();
  final List<FrameTiming> _frames = <FrameTiming>[];
  final int _rssAtStart = ProcessInfo.currentRss;

  WidgetsBinding? _binding;
  TimingsCallback? _timingsCallback;
  FlutterExceptionHandler? _previousFlutterError;
  FlutterExceptionHandler? _flutterErrorHandler;
  int? _firstFrameMicros;
  int? _usefulStateMicros;
  int? _firstSearchResultMicros;
  var _rebuilds = 0;
  var _materializedRows = 0;
  var _totalRows = 0;
  var _maxQueuedCommands = 0;
  var _cancellations = 0;
  var _disposals = 0;
  var _frameworkErrors = 0;
  var _overflows = 0;
  var _latePublications = 0;
  var _subscriptions = 0;
  var _watchers = 0;
  var _timers = 0;
  var _workers = 0;
  bool? _statePreserved;

  void attach(WidgetsBinding binding) {
    if (_binding != null) throw StateError('Probe is already attached.');
    _binding = binding;
    _timingsCallback = _frames.addAll;
    binding.addTimingsCallback(_timingsCallback!);
    _previousFlutterError = FlutterError.onError;
    _flutterErrorHandler = (details) {
      _frameworkErrors += 1;
      if (details.exceptionAsString().contains('overflowed')) {
        _overflows += 1;
      }
      _previousFlutterError?.call(details);
    };
    FlutterError.onError = _flutterErrorHandler;
    binding.addPostFrameCallback((_) {
      _firstFrameMicros ??= _clock.elapsedMicroseconds;
    });
  }

  void detach() {
    final binding = _binding;
    final callback = _timingsCallback;
    if (binding != null && callback != null) {
      binding.removeTimingsCallback(callback);
    }
    if (identical(FlutterError.onError, _flutterErrorHandler)) {
      FlutterError.onError = _previousFlutterError;
    }
    _binding = null;
    _timingsCallback = null;
    _flutterErrorHandler = null;
    _previousFlutterError = null;
  }

  void markUsefulState() {
    _usefulStateMicros ??= _clock.elapsedMicroseconds;
  }

  void markFirstSearchResult() {
    _firstSearchResultMicros ??= _clock.elapsedMicroseconds;
  }

  void recordRebuild() {
    _rebuilds += 1;
  }

  void recordMaterializedRows({required int rows, required int totalRows}) {
    _materializedRows = rows;
    _totalRows = totalRows;
  }

  void recordQueueDepth(int value) {
    if (value > _maxQueuedCommands) _maxQueuedCommands = value;
  }

  void recordCancellation() {
    _cancellations += 1;
  }

  void recordDisposal() {
    _disposals += 1;
  }

  void recordLatePublication() {
    _latePublications += 1;
  }

  void recordResourceCensus({
    required int subscriptions,
    required int watchers,
    required int timers,
    required int workers,
  }) {
    _subscriptions = subscriptions;
    _watchers = watchers;
    _timers = timers;
    _workers = workers;
  }

  void recordStatePreserved(bool value) {
    _statePreserved = value;
  }

  _FlutterQualityEvidence finish() {
    detach();
    _clock.stop();
    final buildMicros = _frames
        .map((frame) => frame.buildDuration.inMicroseconds)
        .toList(growable: false);
    final rasterMicros = _frames
        .map((frame) => frame.rasterDuration.inMicroseconds)
        .toList(growable: false);
    return _FlutterQualityEvidence(
      firstFrameMicros: _firstFrameMicros,
      usefulStateMicros: _usefulStateMicros,
      firstSearchResultMicros: _firstSearchResultMicros,
      buildP50Micros: _percentile(buildMicros, 0.50),
      buildP95Micros: _percentile(buildMicros, 0.95),
      rasterP50Micros: _percentile(rasterMicros, 0.50),
      rasterP95Micros: _percentile(rasterMicros, 0.95),
      framesAboveBudget: _frames
          .where(
            (frame) =>
                frame.buildDuration + frame.rasterDuration >
                const Duration(microseconds: 16667),
          )
          .length,
      rebuilds: _rebuilds,
      materializedRows: _materializedRows,
      totalRows: _totalRows,
      maxQueuedCommands: _maxQueuedCommands,
      cancellations: _cancellations,
      disposals: _disposals,
      frameworkErrors: _frameworkErrors,
      overflows: _overflows,
      latePublications: _latePublications,
      subscriptions: _subscriptions,
      watchers: _watchers,
      timers: _timers,
      workers: _workers,
      statePreserved: _statePreserved ?? false,
      rssDeltaBytes: ProcessInfo.currentRss - _rssAtStart,
    );
  }

  static int? _percentile(List<int> values, double quantile) {
    if (values.isEmpty) return null;
    final sorted = <int>[...values]..sort();
    final index = ((sorted.length - 1) * quantile).ceil();
    return sorted[index];
  }
}

final class _FlutterQualityEvidence {
  const _FlutterQualityEvidence({
    required this.firstFrameMicros,
    required this.usefulStateMicros,
    required this.firstSearchResultMicros,
    required this.buildP50Micros,
    required this.buildP95Micros,
    required this.rasterP50Micros,
    required this.rasterP95Micros,
    required this.framesAboveBudget,
    required this.rebuilds,
    required this.materializedRows,
    required this.totalRows,
    required this.maxQueuedCommands,
    required this.cancellations,
    required this.disposals,
    required this.frameworkErrors,
    required this.overflows,
    required this.latePublications,
    required this.subscriptions,
    required this.watchers,
    required this.timers,
    required this.workers,
    required this.statePreserved,
    required this.rssDeltaBytes,
  });

  final int? firstFrameMicros;
  final int? usefulStateMicros;
  final int? firstSearchResultMicros;
  final int? buildP50Micros;
  final int? buildP95Micros;
  final int? rasterP50Micros;
  final int? rasterP95Micros;
  final int framesAboveBudget;
  final int rebuilds;
  final int materializedRows;
  final int totalRows;
  final int maxQueuedCommands;
  final int cancellations;
  final int disposals;
  final int frameworkErrors;
  final int overflows;
  final int latePublications;
  final int subscriptions;
  final int watchers;
  final int timers;
  final int workers;
  final bool statePreserved;
  final int rssDeltaBytes;

  List<String> get structuralFailures => <String>[
    if (overflows != 0) 'overflow:$overflows',
    if (frameworkErrors != 0) 'framework-error:$frameworkErrors',
    if (latePublications != 0) 'late-publication:$latePublications',
    if (subscriptions != 0) 'subscriptions:$subscriptions',
    if (watchers != 0) 'watchers:$watchers',
    if (timers != 0) 'timers:$timers',
    if (workers != 0) 'workers:$workers',
    if (totalRows >= 10000 && materializedRows >= 100)
      'materialized-rows:$materializedRows/$totalRows',
    if (!statePreserved) 'state-not-preserved',
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    'blocking': <String, Object?>{
      'overflows': overflows,
      'frameworkErrors': frameworkErrors,
      'latePublications': latePublications,
      'residualResources': <String, int>{
        'subscriptions': subscriptions,
        'watchers': watchers,
        'timers': timers,
        'workers': workers,
      },
      'materializedRows': materializedRows,
      'totalRows': totalRows,
      'statePreserved': statePreserved,
    },
    'informative': <String, Object?>{
      'firstFrameMicros': firstFrameMicros,
      'usefulStateMicros': usefulStateMicros,
      'firstSearchResultMicros': firstSearchResultMicros,
      'buildP50Micros': buildP50Micros,
      'buildP95Micros': buildP95Micros,
      'rasterP50Micros': rasterP50Micros,
      'rasterP95Micros': rasterP95Micros,
      'framesAboveBudget': framesAboveBudget,
      'rebuilds': rebuilds,
      'maxQueuedCommands': maxQueuedCommands,
      'cancellations': cancellations,
      'disposals': disposals,
      'rssDeltaBytes': rssDeltaBytes,
    },
  };
}
