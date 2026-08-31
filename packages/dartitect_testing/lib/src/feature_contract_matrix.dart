import 'dart:async';

import 'package:dartitect/dartitect.dart';

import 'deterministic_id_generator.dart';
import 'manual_clock.dart';
import 'manual_scheduler.dart';
import 'resource_census.dart';

/// Stable behavioral cases required by one or more feature profiles.
enum FeatureContract {
  /// Successful typed remote read.
  onlineRead,

  /// Expected remote failure remains distinct from a crash.
  expectedFailure,

  /// Unexpected crashes retain their identity and stack.
  unexpectedCrash,

  /// Cooperative cancellation stops publication.
  cancellation,

  /// Two admitted operations complete without hidden global serialization.
  concurrency,

  /// A fresh graph reopens durable state.
  restart,

  /// Teardown leaves no owned resources.
  zeroResiduals,

  /// Local persistence is the query authority.
  localAuthority,

  /// Remote refresh completes only after local observation.
  refreshObservation,

  /// Checkpoint advances only after durable application.
  durableCheckpoint,

  /// Stale fencing generations cannot commit.
  fencing,

  /// Headless execution deduplicates and drains its graph.
  headlessExecution,

  /// Local mutation and outbox enqueue are atomic.
  atomicOutbox,

  /// Uncertain delivery is never retried blindly.
  uncertainDelivery,

  /// Conflict policy is explicit and durable.
  conflictRecovery,
}

/// Closed facts derived by the matrix from observed runtime evidence.
enum FeatureContractFact {
  /// A typed success event was observed.
  typedSuccess,

  /// The declared authority published a value.
  valuePublished,

  /// A typed expected failure event was observed.
  typedFailure,

  /// Expected failure/crash identity remained distinct.
  crashPreserved,

  /// Cooperative cancellation reached the operation.
  cancellationObserved,

  /// Cancelled work did not publish.
  stalePublicationRejected,

  /// Both concurrent admissions completed and drained.
  concurrentExecutionsCompleted,

  /// Presentation read the local snapshot.
  localSnapshotObserved,

  /// Remote input committed locally.
  remoteCommittedLocally,

  /// The exact committed revision was observed.
  exactRevisionObserved,

  /// Restart created another application graph.
  freshGraphCreated,

  /// The new graph read prior durable state.
  durableStateRecovered,

  /// Dataset coverage committed before checkpointing.
  dataCommittedBeforeCheckpoint,

  /// Checkpoint matches applied coverage.
  checkpointPersisted,

  /// A stale fencing token was rejected.
  staleFencingRejected,

  /// A current fencing token committed.
  currentFencingCommitted,

  /// Headless execution opened its own graph.
  freshHeadlessGraph,

  /// Duplicate input shared bounded headless work.
  duplicateHeadlessRequestHandled,

  /// Headless acknowledgement preceded graph drain.
  headlessGraphDrained,

  /// Domain and outbox share one revision.
  domainAndOutboxAtomic,

  /// A failed atomic transaction changed neither side.
  atomicRollback,

  /// Uncertain delivery state persisted.
  uncertaintyPersisted,

  /// No second automatic delivery attempt occurred.
  uncertainRetryStopped,

  /// Conflict state persisted.
  conflictPersisted,

  /// Explicit consumer policy resolved the conflict.
  explicitConflictPolicy,
}

/// Runtime events produced only by concrete observed harness operations.
enum FeatureRuntimeEventKind {
  /// An application graph opened.
  graphOpened,

  /// An application graph closed.
  graphClosed,

  /// A remote operation returned typed success.
  remoteSucceeded,

  /// A typed expected failure occurred.
  expectedFailure,

  /// The matrix caught an unexpected crash.
  crashObserved,

  /// The matrix caught cooperative cancellation.
  cancellationObserved,

  /// The authority published a revision.
  publication,

  /// One concurrent operation began.
  operationStarted,

  /// One concurrent operation completed.
  operationCompleted,

  /// The local authority was read.
  localSnapshotRead,

  /// Remote input committed locally.
  remoteCommitted,

  /// A local revision was observed.
  revisionObserved,

  /// Durable restart state was written.
  durableWritten,

  /// Durable restart state was read.
  durableRead,

  /// Dataset coverage was applied.
  datasetApplied,

  /// A checkpoint was persisted.
  checkpointWritten,

  /// A stale fence was rejected.
  staleFenceRejected,

  /// A current fence committed.
  currentFenceCommitted,

  /// A headless graph opened.
  headlessGraphOpened,

  /// A headless graph closed.
  headlessGraphClosed,

  /// Domain and outbox committed atomically.
  domainOutboxCommitted,

  /// Domain and outbox rolled back atomically.
  domainOutboxRolledBack,

  /// Delivery was attempted.
  deliveryAttempted,

  /// Uncertainty was persisted.
  uncertaintyPersisted,

  /// A conflict was persisted.
  conflictPersisted,

  /// Explicit policy resolved a conflict.
  conflictResolved,
}

/// One payload-bounded observed event.
final class FeatureRuntimeEvent {
  /// Creates one observed event.
  const FeatureRuntimeEvent({
    required this.kind,
    required this.sequence,
    this.revision,
    this.identifier,
    this.graphId,
  });

  /// Event category.
  final FeatureRuntimeEventKind kind;

  /// Monotonic row-local sequence.
  final int sequence;

  /// Optional store revision or fencing token.
  final int? revision;

  /// Optional bounded operation/request identifier.
  final String? identifier;

  /// Optional matrix-owned graph identifier.
  final int? graphId;
}

/// Headless acknowledgement kinds observed by the matrix.
enum FeatureHeadlessAckKind {
  /// A new request was admitted.
  accepted,

  /// A duplicate was routed to retained work.
  duplicate,

  /// Admitted work reached a terminal acknowledgement.
  terminal,
}

/// One bounded headless acknowledgement.
final class FeatureHeadlessAcknowledgement {
  /// Creates one observed acknowledgement.
  const FeatureHeadlessAcknowledgement({
    required this.kind,
    required this.requestId,
    required this.graphId,
  });

  /// Acknowledgement category.
  final FeatureHeadlessAckKind kind;

  /// Bounded consumer request identifier.
  final String requestId;

  /// Matrix-owned graph identifier.
  final int graphId;
}

/// Typed injected crash used to prove identity preservation.
final class FeatureInjectedCrash implements Exception {
  FeatureInjectedCrash._(this.generation);

  /// Fault-controller generation that created this exact crash.
  final int generation;
}

/// Matrix-owned deterministic fault controller supplied to the driver.
final class FeatureFaultController {
  bool _expectedFailure = false;
  FeatureInjectedCrash? _crash;
  int _generation = 0;

  /// Whether the current row requested an expected failure.
  bool get expectedFailureArmed => _expectedFailure;

  /// Exact crash instance armed for the row, when present.
  FeatureInjectedCrash? get armedCrash => _crash;

  void _armExpectedFailure() => _expectedFailure = true;

  void _armCrash() {
    _generation += 1;
    _crash = FeatureInjectedCrash._(_generation);
  }

  /// Consumes the expected-failure request once.
  bool takeExpectedFailure() {
    final armed = _expectedFailure;
    _expectedFailure = false;
    return armed;
  }

  /// Throws the exact matrix-owned crash when armed.
  void throwIfCrashArmed() {
    final crash = _crash;
    _crash = null;
    if (crash != null) throw crash;
  }
}

/// Deterministic instance-owned pseudo-random source for feature fixtures.
final class FeatureDeterministicRandom {
  /// Creates a reproducible source with a non-negative [seed].
  FeatureDeterministicRandom({int seed = 1}) : _state = seed {
    if (seed < 0) {
      throw ArgumentError.value(seed, 'seed', 'Must not be negative.');
    }
  }

  int _state;

  /// Produces the next value without consulting global randomness.
  int nextInt(int maximum) {
    if (maximum <= 0) {
      throw ArgumentError.value(maximum, 'maximum', 'Must be positive.');
    }
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state % maximum;
  }
}

/// Mutable, deterministic connectivity generation for contract fixtures.
final class FeatureConnectivityHarness {
  bool _online = true;
  int _generation = 0;

  /// Current connectivity state.
  bool get isOnline => _online;

  /// Monotonic generation incremented only when state changes.
  int get generation => _generation;

  /// Publishes a deterministic connectivity transition.
  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _generation += 1;
  }
}

/// Transport-attempt harness backed by the matrix-owned resource census.
final class FeatureTransportHarness {
  /// Creates a transport harness registered in [resources].
  FeatureTransportHarness(ResourceCensus resources) : _resources = resources;

  final ResourceCensus _resources;

  var _attempts = 0;

  /// Number of attempts admitted through this harness.
  int get attempts => _attempts;

  /// Runs one cancellable attempt and proves its transport lease drains.
  Future<T> execute<T>(
    CancellationSignal cancellation,
    FutureOr<T> Function() action,
  ) async {
    cancellation.throwIfCancelled();
    final lease = _resources.acquire('transportRequests');
    _attempts += 1;
    try {
      final value = await action();
      cancellation.throwIfCancelled();
      return value;
    } finally {
      lease.dispose();
    }
  }
}

/// Exact store counters captured before and after a stimulus.
final class FeatureObservedStoreSnapshot {
  /// Creates one immutable store snapshot.
  const FeatureObservedStoreSnapshot({
    required this.revision,
    required this.publications,
    required this.durableWrites,
    required this.durableReads,
    required this.dataRevision,
    required this.checkpointRevision,
    required this.staleFenceRejections,
    required this.currentFenceCommits,
    required this.domainRevision,
    required this.outboxRevision,
    required this.atomicRollbacks,
    required this.deliveryAttempts,
    required this.uncertainOperations,
    required this.persistedConflicts,
    required this.resolvedConflicts,
    required this.operationsStarted,
    required this.operationsCompleted,
    required this.activeOperations,
  });

  /// Current local revision.
  final int revision;

  /// Authority publication count.
  final int publications;

  /// Durable write count.
  final int durableWrites;

  /// Durable read count.
  final int durableReads;

  /// Latest locally applied dataset revision.
  final int dataRevision;

  /// Latest persisted checkpoint revision.
  final int checkpointRevision;

  /// Atomically rejected stale fence count.
  final int staleFenceRejections;

  /// Current fence commit count.
  final int currentFenceCommits;

  /// Domain transaction revision.
  final int domainRevision;

  /// Outbox transaction revision.
  final int outboxRevision;

  /// Atomic rollback count.
  final int atomicRollbacks;

  /// Actual delivery attempt count.
  final int deliveryAttempts;

  /// Persisted uncertain-operation count.
  final int uncertainOperations;

  /// Persisted conflict count.
  final int persistedConflicts;

  /// Explicitly resolved conflict count.
  final int resolvedConflicts;

  /// Admitted operation count.
  final int operationsStarted;

  /// Completed operation count.
  final int operationsCompleted;

  /// Currently active operation count.
  final int activeOperations;
}

/// Matrix-owned observable store used by real fixture drivers.
final class FeatureObservedStore {
  FeatureObservedStore._(this._record);

  final void Function(
    FeatureRuntimeEventKind kind, {
    int? revision,
    String? identifier,
    int? graphId,
  })
  _record;

  int _revision = 0;
  int _publications = 0;
  int _durableWrites = 0;
  int _durableReads = 0;
  int _dataRevision = 0;
  int _checkpointRevision = 0;
  int _staleFenceRejections = 0;
  int _currentFenceCommits = 0;
  int _fencingToken = 0;
  int _domainRevision = 0;
  int _outboxRevision = 0;
  int _atomicRollbacks = 0;
  int _deliveryAttempts = 0;
  int _uncertainOperations = 0;
  int _persistedConflicts = 0;
  int _resolvedConflicts = 0;
  int _operationsStarted = 0;
  int _operationsCompleted = 0;
  int _activeOperations = 0;

  /// Whether a restart seed currently exists.
  bool get hasDurableState => _durableWrites > 0;

  /// Current local revision.
  int get revision => _revision;

  /// Current immutable counters.
  FeatureObservedStoreSnapshot snapshot() => FeatureObservedStoreSnapshot(
    revision: _revision,
    publications: _publications,
    durableWrites: _durableWrites,
    durableReads: _durableReads,
    dataRevision: _dataRevision,
    checkpointRevision: _checkpointRevision,
    staleFenceRejections: _staleFenceRejections,
    currentFenceCommits: _currentFenceCommits,
    domainRevision: _domainRevision,
    outboxRevision: _outboxRevision,
    atomicRollbacks: _atomicRollbacks,
    deliveryAttempts: _deliveryAttempts,
    uncertainOperations: _uncertainOperations,
    persistedConflicts: _persistedConflicts,
    resolvedConflicts: _resolvedConflicts,
    operationsStarted: _operationsStarted,
    operationsCompleted: _operationsCompleted,
    activeOperations: _activeOperations,
  );

  /// Records a typed remote success without publishing it implicitly.
  void remoteSucceeded() => _record(FeatureRuntimeEventKind.remoteSucceeded);

  /// Records one expected, typed boundary failure.
  void expectedFailure() => _record(FeatureRuntimeEventKind.expectedFailure);

  /// Publishes one value through the declared authority.
  void publish() {
    _publications += 1;
    _record(FeatureRuntimeEventKind.publication, revision: _revision);
  }

  /// Begins one observed admitted operation.
  FeatureOperationLease beginOperation() {
    _operationsStarted += 1;
    _activeOperations += 1;
    _record(FeatureRuntimeEventKind.operationStarted);
    return FeatureOperationLease._(this);
  }

  void _completeOperation() {
    if (_activeOperations <= 0) throw StateError('Operation underflow.');
    _activeOperations -= 1;
    _operationsCompleted += 1;
    _record(FeatureRuntimeEventKind.operationCompleted);
  }

  /// Reads the local snapshot used by presentation.
  void readLocalSnapshot() =>
      _record(FeatureRuntimeEventKind.localSnapshotRead, revision: _revision);

  /// Commits remote input locally and returns its new revision.
  int commitRemoteLocally() {
    _revision += 1;
    _record(FeatureRuntimeEventKind.remoteCommitted, revision: _revision);
    return _revision;
  }

  /// Observes an exact local revision.
  void observeRevision(int revision) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'Must not be negative.');
    }
    _record(FeatureRuntimeEventKind.revisionObserved, revision: revision);
  }

  /// Writes durable state used by a later fresh graph.
  void writeDurableState() {
    _durableWrites += 1;
    _revision += 1;
    _record(FeatureRuntimeEventKind.durableWritten, revision: _revision);
  }

  /// Reads a previously written durable value.
  void readDurableState() {
    if (!hasDurableState) throw StateError('No durable state exists.');
    _durableReads += 1;
    _record(FeatureRuntimeEventKind.durableRead, revision: _revision);
  }

  /// Applies one dataset revision locally.
  int applyDataset() {
    _dataRevision += 1;
    _record(FeatureRuntimeEventKind.datasetApplied, revision: _dataRevision);
    return _dataRevision;
  }

  /// Persists a checkpoint only for already-applied coverage.
  void writeCheckpoint(int revision) {
    if (revision <= _checkpointRevision || revision > _dataRevision) {
      throw StateError('Checkpoint does not match applied local coverage.');
    }
    _checkpointRevision = revision;
    _record(FeatureRuntimeEventKind.checkpointWritten, revision: revision);
  }

  /// Observes an atomically rejected stale fencing token.
  void rejectStaleFence(int token) {
    if (token >= _fencingToken) throw StateError('Fence is not stale.');
    _staleFenceRejections += 1;
    _record(FeatureRuntimeEventKind.staleFenceRejected, revision: token);
  }

  /// Commits a current monotonic fencing token.
  void commitCurrentFence(int token) {
    if (token <= _fencingToken) throw StateError('Fence is not current.');
    _fencingToken = token;
    _currentFenceCommits += 1;
    _record(FeatureRuntimeEventKind.currentFenceCommitted, revision: token);
  }

  /// Commits domain and outbox revisions in one observed transaction.
  void commitDomainAndOutbox(String operationId) {
    _validateIdentifier(operationId, 'operationId');
    final revision = _domainRevision + 1;
    _domainRevision = revision;
    _outboxRevision = revision;
    _record(
      FeatureRuntimeEventKind.domainOutboxCommitted,
      revision: revision,
      identifier: operationId,
    );
  }

  /// Proves the failed transaction changed neither side.
  void rollbackDomainAndOutbox() {
    _atomicRollbacks += 1;
    _record(FeatureRuntimeEventKind.domainOutboxRolledBack);
  }

  /// Records one actual delivery attempt for an operation.
  void attemptDelivery(String operationId) {
    _validateIdentifier(operationId, 'operationId');
    _deliveryAttempts += 1;
    _record(FeatureRuntimeEventKind.deliveryAttempted, identifier: operationId);
  }

  /// Persists uncertainty for the exact attempted operation.
  void persistUncertainty(String operationId) {
    _validateIdentifier(operationId, 'operationId');
    _uncertainOperations += 1;
    _record(
      FeatureRuntimeEventKind.uncertaintyPersisted,
      identifier: operationId,
    );
  }

  /// Persists a conflict awaiting explicit policy.
  void persistConflict(String operationId) {
    _validateIdentifier(operationId, 'operationId');
    _persistedConflicts += 1;
    _record(FeatureRuntimeEventKind.conflictPersisted, identifier: operationId);
  }

  /// Applies explicit consumer conflict policy.
  void resolveConflict(String operationId) {
    _validateIdentifier(operationId, 'operationId');
    if (_persistedConflicts <= _resolvedConflicts) {
      throw StateError('No persisted conflict is awaiting resolution.');
    }
    _resolvedConflicts += 1;
    _record(FeatureRuntimeEventKind.conflictResolved, identifier: operationId);
  }

  static void _validateIdentifier(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be blank.');
    }
  }
}

/// Exact-once observed operation completion.
final class FeatureOperationLease implements Disposable {
  FeatureOperationLease._(this._store);

  FeatureObservedStore? _store;

  @override
  void dispose() {
    final store = _store;
    _store = null;
    store?._completeOperation();
  }
}

/// Matrix-owned observed runtime, store, fault, acknowledgement, and census.
final class FeatureContractHarness {
  /// Creates an empty row harness.
  FeatureContractHarness()
    : resources = ResourceCensus(),
      faults = FeatureFaultController(),
      clock = ManualClock(DateTime.utc(2026)),
      ids = DeterministicIdGenerator(prefix: 'feature'),
      randomness = FeatureDeterministicRandom(),
      connectivity = FeatureConnectivityHarness(),
      scheduler = ManualScheduler() {
    store = FeatureObservedStore._(_record);
    transport = FeatureTransportHarness(resources);
  }

  /// Real resource census owned by the matrix, never supplied by a fixture.
  final ResourceCensus resources;

  /// Deterministic matrix-owned fault controller.
  final FeatureFaultController faults;

  /// Manually advanced UTC clock.
  final ManualClock clock;

  /// Deterministic IDs for operations, graphs, and fixtures.
  final DeterministicIdGenerator ids;

  /// Deterministic instance-owned randomness.
  final FeatureDeterministicRandom randomness;

  /// Controllable connectivity generation.
  final FeatureConnectivityHarness connectivity;

  /// Manually advanced delay scheduler.
  final ManualScheduler scheduler;

  /// Cancellable transport attempts registered in [resources].
  late final FeatureTransportHarness transport;

  /// Observed store whose writes are inspected after the stimulus.
  late final FeatureObservedStore store;

  final List<FeatureRuntimeEvent> _events = <FeatureRuntimeEvent>[];
  final List<FeatureHeadlessAcknowledgement> _acknowledgements =
      <FeatureHeadlessAcknowledgement>[];
  int _sequence = 0;
  int _nextGraphId = 0;

  /// Immutable ordered observed events.
  List<FeatureRuntimeEvent> get events =>
      List<FeatureRuntimeEvent>.unmodifiable(_events);

  /// Immutable headless acknowledgements.
  List<FeatureHeadlessAcknowledgement> get acknowledgements =>
      List<FeatureHeadlessAcknowledgement>.unmodifiable(_acknowledgements);

  /// Opens a matrix-owned application graph registration.
  FeatureGraphLease openGraph() => _openGraph(headless: false);

  /// Opens a matrix-owned headless graph registration.
  FeatureGraphLease openHeadlessGraph() => _openGraph(headless: true);

  FeatureGraphLease _openGraph({required bool headless}) {
    _nextGraphId += 1;
    final graphId = _nextGraphId;
    final kind = headless ? 'headlessGraphs' : 'graphs';
    final lease = resources.acquire(kind);
    _record(
      headless
          ? FeatureRuntimeEventKind.headlessGraphOpened
          : FeatureRuntimeEventKind.graphOpened,
      graphId: graphId,
    );
    return FeatureGraphLease._(this, graphId, headless, lease);
  }

  /// Records an accepted headless request against an open graph.
  void acceptHeadless(String requestId, int graphId) {
    _validateAck(requestId, graphId);
    _acknowledgements.add(
      FeatureHeadlessAcknowledgement(
        kind: FeatureHeadlessAckKind.accepted,
        requestId: requestId,
        graphId: graphId,
      ),
    );
  }

  /// Records a duplicate request routed to the retained execution.
  void duplicateHeadless(String requestId, int graphId) {
    _validateAck(requestId, graphId);
    _acknowledgements.add(
      FeatureHeadlessAcknowledgement(
        kind: FeatureHeadlessAckKind.duplicate,
        requestId: requestId,
        graphId: graphId,
      ),
    );
  }

  /// Records terminal acknowledgement before graph drain.
  void completeHeadless(String requestId, int graphId) {
    _validateAck(requestId, graphId);
    _acknowledgements.add(
      FeatureHeadlessAcknowledgement(
        kind: FeatureHeadlessAckKind.terminal,
        requestId: requestId,
        graphId: graphId,
      ),
    );
  }

  void _validateAck(String requestId, int graphId) {
    if (requestId.trim().isEmpty || graphId <= 0) {
      throw ArgumentError('Headless acknowledgement is invalid.');
    }
  }

  void _record(
    FeatureRuntimeEventKind kind, {
    int? revision,
    String? identifier,
    int? graphId,
  }) {
    _sequence += 1;
    _events.add(
      FeatureRuntimeEvent(
        kind: kind,
        sequence: _sequence,
        revision: revision,
        identifier: identifier,
        graphId: graphId,
      ),
    );
  }

  void _recordCrash() => _record(FeatureRuntimeEventKind.crashObserved);

  void _recordCancellation() =>
      _record(FeatureRuntimeEventKind.cancellationObserved);

  void _closeGraph(int graphId, bool headless) => _record(
    headless
        ? FeatureRuntimeEventKind.headlessGraphClosed
        : FeatureRuntimeEventKind.graphClosed,
    graphId: graphId,
  );
}

/// Exact-once graph registration around one fixture runtime.
final class FeatureGraphLease implements Disposable {
  FeatureGraphLease._(this._owner, this.graphId, this.headless, this._lease);

  FeatureContractHarness? _owner;
  CensusLease? _lease;

  /// Matrix-assigned graph identifier.
  final int graphId;

  /// Whether this represents an inner headless graph.
  final bool headless;

  @override
  void dispose() {
    final owner = _owner;
    _owner = null;
    if (owner == null) return;
    _lease?.dispose();
    _lease = null;
    owner._closeGraph(graphId, headless);
  }
}

/// Driver receives stimuli and acts on real matrix-owned harness primitives.
/// It cannot return facts, observations, or a residual-resource map.
abstract interface class OnlineFeatureContractDriver
    implements AsyncDisposable {
  /// Executes [contract] using [cancellation] and the injected row harness.
  FutureOr<void> stimulate(
    FeatureContract contract,
    CancellationSignal cancellation,
  );
}

/// Marker for cache-profile drivers.
abstract interface class CacheFeatureContractDriver
    implements OnlineFeatureContractDriver {}

/// Marker for replica-profile drivers.
abstract interface class ReplicaFeatureContractDriver
    implements CacheFeatureContractDriver {}

/// Marker for offline-full-profile drivers.
abstract interface class OfflineFullFeatureContractDriver
    implements ReplicaFeatureContractDriver {}

/// Factory that receives matrix-owned instruments and creates a fresh runtime.
final class FeatureContractFixtures<T extends OnlineFeatureContractDriver> {
  /// Creates a driver factory.
  const FeatureContractFixtures({required this.create});

  /// Creates one fresh runtime graph driver.
  final FutureOr<T> Function(FeatureContractHarness harness) create;
}

/// Evidence derived by the matrix after observed stimulus and teardown.
final class FeatureContractObservation {
  FeatureContractObservation._({
    required this.contract,
    required Set<FeatureContractFact> facts,
    required List<FeatureRuntimeEvent> events,
    required this.store,
    required List<FeatureHeadlessAcknowledgement> acknowledgements,
  }) : facts = Set<FeatureContractFact>.unmodifiable(facts),
       events = List<FeatureRuntimeEvent>.unmodifiable(events),
       acknowledgements = List<FeatureHeadlessAcknowledgement>.unmodifiable(
         acknowledgements,
       );

  /// Contract exercised by this row.
  final FeatureContract contract;

  /// Facts derived by the matrix, never supplied by the fixture.
  final Set<FeatureContractFact> facts;

  /// Ordered observed events.
  final List<FeatureRuntimeEvent> events;

  /// Terminal observed store counters.
  final FeatureObservedStoreSnapshot store;

  /// Observed headless acknowledgements.
  final List<FeatureHeadlessAcknowledgement> acknowledgements;
}

/// Framework-neutral result of one independently observed matrix row.
final class FeatureContractResult {
  /// Creates one immutable matrix result.
  const FeatureContractResult({
    required this.profile,
    required this.contract,
    required this.fixtureCreated,
    required this.disposeAttempted,
    required this.censusChecked,
    this.observation,
    this.error,
    this.stackTrace,
  });

  /// Profile that selected the row.
  final FeatureProfile profile;

  /// Executed contract.
  final FeatureContract contract;

  /// Whether at least one runtime factory completed.
  final bool fixtureCreated;

  /// Whether driver cleanup was attempted.
  final bool disposeAttempted;

  /// Whether the matrix-owned census was checked.
  final bool censusChecked;

  /// Derived observation when stimulus evidence was available.
  final FeatureContractObservation? observation;

  /// First evidence, stimulus, cleanup, or census error.
  final Object? error;

  /// Original stack for [error].
  final StackTrace? stackTrace;

  /// Whether observed evidence, cleanup, and the real census all passed.
  bool get succeeded => error == null;
}

/// Required behavioral matrix for one paved-road feature profile.
final class FeatureContractMatrix<T extends OnlineFeatureContractDriver> {
  /// Creates the local-profile matrix.
  FeatureContractMatrix.local({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureProfile.local, fixtures);

  /// Creates the online-profile matrix.
  FeatureContractMatrix.online({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureProfile.online, fixtures);

  /// Creates the cache-profile matrix.
  FeatureContractMatrix.cache({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureProfile.cache, fixtures);

  /// Creates the replica-profile matrix.
  FeatureContractMatrix.replica({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureProfile.replica, fixtures);

  /// Creates the offline-full-profile matrix.
  FeatureContractMatrix.offlineFull({
    required FeatureContractFixtures<T> fixtures,
  }) : this._(FeatureProfile.offlineFull, fixtures);

  FeatureContractMatrix._(this.profile, this.fixtures);

  /// Selected feature profile.
  final FeatureProfile profile;

  /// Fresh runtime factory.
  final FeatureContractFixtures<T> fixtures;

  /// Stable required rows in execution order.
  List<FeatureContract> get requiredContracts =>
      _requirements[profile]!.keys.toList(growable: false);

  /// Executes every row with matrix-owned evidence and a new graph.
  Future<List<FeatureContractResult>> run() async {
    final results = <FeatureContractResult>[];
    for (final contract in requiredContracts) {
      results.add(await _runRow(contract));
    }
    return List<FeatureContractResult>.unmodifiable(results);
  }

  Future<FeatureContractResult> _runRow(FeatureContract contract) async {
    final harness = FeatureContractHarness();
    final before = harness.store.snapshot();
    var fixtureCreated = false;
    var disposeAttempted = false;
    var censusChecked = false;
    Object? failure;
    StackTrace? failureStack;
    Object? expectedCrash;
    Object? observedCrash;
    var cancellationObserved = false;
    FeatureContractObservation? observation;

    Future<void> useFreshDriver({required bool restartPass}) async {
      final graph = harness.openGraph();
      T? driver;
      try {
        driver = await fixtures.create(harness);
        fixtureCreated = true;
        final outcome = await _stimulate(
          driver,
          harness,
          contract,
          restartPass: restartPass,
        );
        expectedCrash ??= outcome.expectedCrash;
        observedCrash ??= outcome.observedCrash;
        cancellationObserved =
            cancellationObserved || outcome.cancellationObserved;
      } finally {
        if (driver != null) {
          disposeAttempted = true;
          await driver.disposeAsync();
        }
        graph.dispose();
      }
    }

    try {
      await useFreshDriver(restartPass: false);
      if (contract == FeatureContract.restart) {
        harness.resources.verifyZero();
        await useFreshDriver(restartPass: true);
      }
      final facts = _deriveFacts(
        contract,
        harness,
        before,
        expectedCrash: expectedCrash,
        observedCrash: observedCrash,
        cancellationObserved: cancellationObserved,
      );
      observation = FeatureContractObservation._(
        contract: contract,
        facts: facts,
        events: harness.events,
        store: harness.store.snapshot(),
        acknowledgements: harness.acknowledgements,
      );
      final required = _requirements[profile]![contract]!;
      if (!facts.containsAll(required)) {
        throw StateError('Observed feature evidence is incomplete.');
      }
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      try {
        censusChecked = true;
        harness.resources.verifyZero();
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    return FeatureContractResult(
      profile: profile,
      contract: contract,
      fixtureCreated: fixtureCreated,
      disposeAttempted: disposeAttempted,
      censusChecked: censusChecked,
      observation: observation,
      error: failure,
      stackTrace: failureStack,
    );
  }

  static Future<_StimulusOutcome> _stimulate(
    OnlineFeatureContractDriver driver,
    FeatureContractHarness harness,
    FeatureContract contract, {
    required bool restartPass,
  }) async {
    final cancellation = CancellationSource();
    Object? expectedCrash;
    Object? observedCrash;
    var cancellationObserved = false;
    try {
      switch (contract) {
        case FeatureContract.expectedFailure:
          harness.faults._armExpectedFailure();
          await driver.stimulate(contract, cancellation.signal);
        case FeatureContract.unexpectedCrash:
          harness.faults._armCrash();
          expectedCrash = harness.faults.armedCrash;
          try {
            await driver.stimulate(contract, cancellation.signal);
          } on Object catch (error) {
            observedCrash = error;
            harness._recordCrash();
          }
        case FeatureContract.cancellation:
          final operation = Future<void>.sync(
            () => driver.stimulate(contract, cancellation.signal),
          );
          scheduleMicrotask(
            () => cancellation.cancel('feature-contract-cancellation'),
          );
          try {
            await operation;
          } on CancellationException {
            cancellationObserved = true;
            harness._recordCancellation();
          }
        case FeatureContract.concurrency:
          await Future.wait<void>(<Future<void>>[
            Future<void>.sync(
              () => driver.stimulate(contract, cancellation.signal),
            ),
            Future<void>.sync(
              () => driver.stimulate(contract, cancellation.signal),
            ),
          ]);
        case FeatureContract.restart:
          await driver.stimulate(contract, cancellation.signal);
          if (restartPass && !harness.store.hasDurableState) {
            throw StateError('Restart pass did not recover durable state.');
          }
        case FeatureContract.onlineRead ||
            FeatureContract.zeroResiduals ||
            FeatureContract.localAuthority ||
            FeatureContract.refreshObservation ||
            FeatureContract.durableCheckpoint ||
            FeatureContract.fencing ||
            FeatureContract.headlessExecution ||
            FeatureContract.atomicOutbox ||
            FeatureContract.uncertainDelivery ||
            FeatureContract.conflictRecovery:
          await driver.stimulate(contract, cancellation.signal);
      }
    } finally {
      cancellation.dispose();
    }
    return _StimulusOutcome(
      expectedCrash: expectedCrash,
      observedCrash: observedCrash,
      cancellationObserved: cancellationObserved,
    );
  }

  static Set<FeatureContractFact> _deriveFacts(
    FeatureContract contract,
    FeatureContractHarness harness,
    FeatureObservedStoreSnapshot before, {
    required Object? expectedCrash,
    required Object? observedCrash,
    required bool cancellationObserved,
  }) {
    final after = harness.store.snapshot();
    final events = harness.events;
    bool has(FeatureRuntimeEventKind kind) =>
        events.any((event) => event.kind == kind);
    int first(FeatureRuntimeEventKind kind) =>
        events.firstWhere((event) => event.kind == kind).sequence;
    final facts = <FeatureContractFact>{};

    if (has(FeatureRuntimeEventKind.remoteSucceeded)) {
      facts.add(FeatureContractFact.typedSuccess);
    }
    if (after.publications > before.publications) {
      facts.add(FeatureContractFact.valuePublished);
    }
    if (has(FeatureRuntimeEventKind.expectedFailure)) {
      facts.add(FeatureContractFact.typedFailure);
    }
    if (contract == FeatureContract.expectedFailure &&
        has(FeatureRuntimeEventKind.expectedFailure) &&
        !has(FeatureRuntimeEventKind.crashObserved)) {
      facts.add(FeatureContractFact.crashPreserved);
    }
    if (contract == FeatureContract.unexpectedCrash &&
        expectedCrash != null &&
        identical(expectedCrash, observedCrash)) {
      facts.add(FeatureContractFact.crashPreserved);
    }
    if (cancellationObserved) {
      facts.add(FeatureContractFact.cancellationObserved);
      if (after.publications == before.publications) {
        facts.add(FeatureContractFact.stalePublicationRejected);
      }
    }
    if (after.operationsStarted - before.operationsStarted >= 2 &&
        after.operationsCompleted - before.operationsCompleted >= 2 &&
        after.activeOperations == 0) {
      facts.add(FeatureContractFact.concurrentExecutionsCompleted);
    }
    if (has(FeatureRuntimeEventKind.localSnapshotRead)) {
      facts.add(FeatureContractFact.localSnapshotObserved);
    }
    if (has(FeatureRuntimeEventKind.remoteCommitted)) {
      facts.add(FeatureContractFact.remoteCommittedLocally);
    }
    final observedRevisions = events
        .where(
          (event) => event.kind == FeatureRuntimeEventKind.revisionObserved,
        )
        .map((event) => event.revision);
    if (observedRevisions.contains(after.revision)) {
      facts.add(FeatureContractFact.exactRevisionObserved);
    }
    if (events
            .where((event) => event.kind == FeatureRuntimeEventKind.graphOpened)
            .length >=
        2) {
      facts.add(FeatureContractFact.freshGraphCreated);
    }
    if (after.durableWrites > before.durableWrites &&
        after.durableReads > before.durableReads) {
      facts.add(FeatureContractFact.durableStateRecovered);
    }
    if (has(FeatureRuntimeEventKind.datasetApplied) &&
        has(FeatureRuntimeEventKind.checkpointWritten) &&
        first(FeatureRuntimeEventKind.datasetApplied) <
            first(FeatureRuntimeEventKind.checkpointWritten)) {
      facts.add(FeatureContractFact.dataCommittedBeforeCheckpoint);
      if (after.checkpointRevision == after.dataRevision) {
        facts.add(FeatureContractFact.checkpointPersisted);
      }
    }
    if (after.staleFenceRejections > before.staleFenceRejections) {
      facts.add(FeatureContractFact.staleFencingRejected);
    }
    if (after.currentFenceCommits > before.currentFenceCommits) {
      facts.add(FeatureContractFact.currentFencingCommitted);
    }
    if (has(FeatureRuntimeEventKind.headlessGraphOpened)) {
      facts.add(FeatureContractFact.freshHeadlessGraph);
    }
    if (harness.acknowledgements.any(
      (ack) => ack.kind == FeatureHeadlessAckKind.duplicate,
    )) {
      facts.add(FeatureContractFact.duplicateHeadlessRequestHandled);
    }
    if (has(FeatureRuntimeEventKind.headlessGraphClosed) &&
        harness.acknowledgements.any(
          (ack) => ack.kind == FeatureHeadlessAckKind.terminal,
        )) {
      facts.add(FeatureContractFact.headlessGraphDrained);
    }
    if (after.domainRevision > before.domainRevision &&
        after.domainRevision == after.outboxRevision) {
      facts.add(FeatureContractFact.domainAndOutboxAtomic);
    }
    if (after.atomicRollbacks > before.atomicRollbacks) {
      facts.add(FeatureContractFact.atomicRollback);
    }
    if (after.uncertainOperations > before.uncertainOperations) {
      facts.add(FeatureContractFact.uncertaintyPersisted);
      if (after.deliveryAttempts - before.deliveryAttempts == 1) {
        facts.add(FeatureContractFact.uncertainRetryStopped);
      }
    }
    if (after.persistedConflicts > before.persistedConflicts) {
      facts.add(FeatureContractFact.conflictPersisted);
    }
    if (after.resolvedConflicts > before.resolvedConflicts) {
      facts.add(FeatureContractFact.explicitConflictPolicy);
    }
    return facts;
  }
}

final class _StimulusOutcome {
  const _StimulusOutcome({
    required this.expectedCrash,
    required this.observedCrash,
    required this.cancellationObserved,
  });

  final Object? expectedCrash;
  final Object? observedCrash;
  final bool cancellationObserved;
}

const Map<FeatureProfile, Map<FeatureContract, Set<FeatureContractFact>>>
_requirements =
    <FeatureProfile, Map<FeatureContract, Set<FeatureContractFact>>>{
      FeatureProfile.local: _onlineRequirements,
      FeatureProfile.online: <FeatureContract, Set<FeatureContractFact>>{
        FeatureContract.onlineRead: <FeatureContractFact>{
          FeatureContractFact.typedSuccess,
          FeatureContractFact.valuePublished,
        },
        FeatureContract.expectedFailure: <FeatureContractFact>{
          FeatureContractFact.typedFailure,
          FeatureContractFact.crashPreserved,
        },
        FeatureContract.unexpectedCrash: <FeatureContractFact>{
          FeatureContractFact.crashPreserved,
        },
        FeatureContract.cancellation: <FeatureContractFact>{
          FeatureContractFact.cancellationObserved,
          FeatureContractFact.stalePublicationRejected,
        },
        FeatureContract.concurrency: <FeatureContractFact>{
          FeatureContractFact.concurrentExecutionsCompleted,
        },
        FeatureContract.restart: <FeatureContractFact>{
          FeatureContractFact.freshGraphCreated,
          FeatureContractFact.durableStateRecovered,
        },
        FeatureContract.zeroResiduals: <FeatureContractFact>{},
      },
      FeatureProfile.cache: <FeatureContract, Set<FeatureContractFact>>{
        ..._onlineRequirements,
        FeatureContract.localAuthority: <FeatureContractFact>{
          FeatureContractFact.localSnapshotObserved,
          FeatureContractFact.remoteCommittedLocally,
        },
        FeatureContract.refreshObservation: <FeatureContractFact>{
          FeatureContractFact.exactRevisionObserved,
        },
      },
      FeatureProfile.replica: <FeatureContract, Set<FeatureContractFact>>{
        ..._cacheRequirements,
        FeatureContract.durableCheckpoint: <FeatureContractFact>{
          FeatureContractFact.dataCommittedBeforeCheckpoint,
          FeatureContractFact.checkpointPersisted,
        },
        FeatureContract.fencing: <FeatureContractFact>{
          FeatureContractFact.staleFencingRejected,
          FeatureContractFact.currentFencingCommitted,
        },
        FeatureContract.headlessExecution: <FeatureContractFact>{
          FeatureContractFact.freshHeadlessGraph,
          FeatureContractFact.duplicateHeadlessRequestHandled,
          FeatureContractFact.headlessGraphDrained,
        },
      },
      FeatureProfile.offlineFull: <FeatureContract, Set<FeatureContractFact>>{
        ..._replicaRequirements,
        FeatureContract.atomicOutbox: <FeatureContractFact>{
          FeatureContractFact.domainAndOutboxAtomic,
          FeatureContractFact.atomicRollback,
        },
        FeatureContract.uncertainDelivery: <FeatureContractFact>{
          FeatureContractFact.uncertaintyPersisted,
          FeatureContractFact.uncertainRetryStopped,
        },
        FeatureContract.conflictRecovery: <FeatureContractFact>{
          FeatureContractFact.conflictPersisted,
          FeatureContractFact.explicitConflictPolicy,
        },
      },
    };

const Map<FeatureContract, Set<FeatureContractFact>> _onlineRequirements =
    <FeatureContract, Set<FeatureContractFact>>{
      FeatureContract.onlineRead: <FeatureContractFact>{
        FeatureContractFact.typedSuccess,
        FeatureContractFact.valuePublished,
      },
      FeatureContract.expectedFailure: <FeatureContractFact>{
        FeatureContractFact.typedFailure,
        FeatureContractFact.crashPreserved,
      },
      FeatureContract.unexpectedCrash: <FeatureContractFact>{
        FeatureContractFact.crashPreserved,
      },
      FeatureContract.cancellation: <FeatureContractFact>{
        FeatureContractFact.cancellationObserved,
        FeatureContractFact.stalePublicationRejected,
      },
      FeatureContract.concurrency: <FeatureContractFact>{
        FeatureContractFact.concurrentExecutionsCompleted,
      },
      FeatureContract.restart: <FeatureContractFact>{
        FeatureContractFact.freshGraphCreated,
        FeatureContractFact.durableStateRecovered,
      },
      FeatureContract.zeroResiduals: <FeatureContractFact>{},
    };

const Map<FeatureContract, Set<FeatureContractFact>> _cacheRequirements =
    <FeatureContract, Set<FeatureContractFact>>{
      ..._onlineRequirements,
      FeatureContract.localAuthority: <FeatureContractFact>{
        FeatureContractFact.localSnapshotObserved,
        FeatureContractFact.remoteCommittedLocally,
      },
      FeatureContract.refreshObservation: <FeatureContractFact>{
        FeatureContractFact.exactRevisionObserved,
      },
    };

const Map<FeatureContract, Set<FeatureContractFact>> _replicaRequirements =
    <FeatureContract, Set<FeatureContractFact>>{
      ..._cacheRequirements,
      FeatureContract.durableCheckpoint: <FeatureContractFact>{
        FeatureContractFact.dataCommittedBeforeCheckpoint,
        FeatureContractFact.checkpointPersisted,
      },
      FeatureContract.fencing: <FeatureContractFact>{
        FeatureContractFact.staleFencingRejected,
        FeatureContractFact.currentFencingCommitted,
      },
      FeatureContract.headlessExecution: <FeatureContractFact>{
        FeatureContractFact.freshHeadlessGraph,
        FeatureContractFact.duplicateHeadlessRequestHandled,
        FeatureContractFact.headlessGraphDrained,
      },
    };
