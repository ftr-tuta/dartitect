# Receitas de implementação Dartitect

[English](implementation-recipes.md)

## Antes de copiar uma receita

Estas receitas são esboços de composição derivados das APIs públicas e exemplos
testados no repositório. Substitua contratos, falhas, entidades, repositories e
providers pertencentes ao consumidor; preserve os limites de ownership e
causalidade do Dartitect. Escolha primeiro o stack com o
[guia de seleção do ecossistema](ecosystem-selection.pt-BR.md).

## Feature simples

Em Dart puro, comece com falha esperada tipada e um owner explícito:

```dart
final owner = ResourceOwner(label: 'FeatureRuntime')
  ..own(StreamController<void>(), (controller) => controller.close());

final Result<int, StateError> result = const Ok<int>(42);
switch (result) {
  case Ok(:final value): print(value);
  case Err(:final failure): print('Esperada: $failure');
}

await owner.disposeAsync();
```

No limite Flutter básico, mantenha o ViewModel owned pelo host e não coloque
`BuildContext` nele:

```dart
ViewModelHost<CounterViewModel>.create(
  create: CounterViewModel.new,
  builder: (context, counter) => ListenableBuilder(
    listenable: counter,
    builder: (context, child) => Text('${counter.value}'),
  ),
);
```

Use `ViewModelHost.value` quando a rota/composition root possuir o ViewModel. Os
exemplos completos são
[`dartitect_example.dart`](../../packages/dartitect/example/dartitect_example.dart)
e
[`dartitect_flutter_example.dart`](../../packages/dartitect_flutter/example/dartitect_flutter_example.dart).

## Runtime reativo

Crie o resource no limite de composição da rota/sessão. A factory da source
possui cada sessão local de ativação e toma emprestado qualquer provider injetado:

```dart
final local = LiveResource<PagedLocalSnapshot<int, Task>, TaskFailure>(
  source: TaskStoreSource(store),
  policy: const ActivationPolicy.whileObserved(),
);
```

Escolha política hot/warm/cold e backpressure como contratos da feature. No
Flutter, o widget toma o resource emprestado:

```dart
LiveResourceBuilder<PagedLocalSnapshot<int, Task>, TaskFailure>(
  resource: local,
  builder: (context, state, temperature, isStale, child) =>
      Text(state.hasData ? '${state.lastData}' : 'Carregando'),
);
```

Descarte consumidores antes da source: `await paged.dispose();` e depois
`await local.dispose();`. Mantenha rendering na presentation consumidora. Veja o
[exemplo reativo headless](../../packages/dartitect_flutter/example/reactive_offline_first_example.dart)
e a composição Material nos workloads de referência.

## Paginação local-first

`PagedLiveResource` escreve toda página remota pelo repository e espera a revisão
local exata antes de avançar o cursor:

```dart
final paged = PagedLiveResource<Cursor, int, Task, TaskFailure>(
  local: local,
  initialCursor: const Cursor(),
  requestPage: remote.requestPage,
  writePage: repository.writePage,
  keyOf: (task) => task.id,
  versionOf: (task) => task.version,
  collectionPolicy: CollectionUpdatePolicy.versionedByKey,
  observationTimeout: const Duration(seconds: 3),
  mapObservationTimeout: (_) => const TaskObservationTimeoutFailure(),
);
```

A transação do repository retorna `PageWriteReceipt.localRevision`; somente o
`LiveResource<PagedLocalSnapshot<...>>` borrowed publica dados de presentation.
Refresh junta-se ao refresh ativo, load-more descarta reentrada e search usa
restart-latest. Verifique cancelamento antes da escrita local. O exemplo em
memória contém uma implementação completa de
[`ReactiveSource` e `PagedLiveResource`](../../packages/dartitect_flutter/example/reactive_offline_first_example.dart);
o app de referência fornece a versão com provider.

## Mutation e outbox

O store do consumidor altera estado de domínio e persiste a outbox atomicamente
em `MutationOutboxStore.applyLocalAndEnqueue`. Componha delivery por key assim:

```dart
var sequence = 0;
final mutations = MutationCommand<TaskMutation, int, void, TaskFailure>(
  store: store,
  synchronize: remote.synchronize,
  createIdempotencyKey: (key, argument) {
    sequence += 1;
    return 'task-$key-$sequence';
  },
  classifyFailure: classifyTaskFailure,
  reporter: crashReporter,
);
```

A idempotency key é não vazia e reutilizada no retry. Persista o acknowledgement
remoto antes de declarar synced. Mapeie falhas esperadas para queued, rejected,
conflicted ou uncertain. Compense somente rejeição definitiva. Após possível
commit remoto ou crash, audite estado durável antes de marcar pending e chamar
`resume(key)`. Uma nova sessão chama `recoverPending()`, mas não entrega registros
uncertain automaticamente.

Use a
[`OfflineFirstTaskSession`](../../examples/reference_app/lib/features/tasks/application/offline_first_task_session.dart)
testada e seus stores em memória/ObjectBox como receita completa.

## Observabilidade

Comece local e provider-neutral:

```dart
final telemetry = ObservabilityRuntime();
try {
  telemetry.logger.info('Aplicação iniciada.');
  // Injete telemetry.reporter e telemetry.tracing nos consumidores.
} finally {
  await telemetry.disposeAsync();
}
```

Antes de adicionar um destino, defina allowlist e política de redaction. Nunca
registre credenciais, authorization, cookies, bodies, headers, queries, DSNs,
identidade ou paths identificadores. `Err` esperado permanece estado do command;
crashes inesperados podem ser reportados uma vez e são relançados. Instale um
`FlutterErrorBinding`, encadeie/restaure handlers anteriores e transfira somente
contexto W3C válido entre isolates.

Para diagnóstico reativo, injete um `ReactiveJournal` limitado localmente ou um
`ReactiveObserverLoggerAdapter`; eventos nunca carregam payloads, keys, texto de
erro ou identidade. Consulte o
[exemplo de observabilidade](../../packages/dartitect_observability/example/dartitect_observability_example.dart)
e o [guia de observabilidade](observability.pt-BR.md).

## Composição de adapters

Crie somente adapters selecionados pela aplicação, na composição de
infraestrutura:

```dart
final dioOwner = DioOwner.create();
final objectBoxOwner = await ObjectBoxStoreOwner.create(openStore: openStore);
final telemetry = ObservabilityRuntime(
  logSinks: <LogSinkRegistration>[
    LogSinkRegistration.borrowed(SentryLogSink(hub: consumerOwnedHub)),
  ],
);

try {
  final dio = dioOwner.dio;
  final store = objectBoxOwner.store;
  // Injete interfaces da aplicação implementadas com dio/store.
} finally {
  dioOwner.dispose();
  await objectBoxOwner.disposeAsync();
  await telemetry.disposeAsync();
  // O consumidor fecha consumerOwnedHub depois.
}
```

A maioria das aplicações precisa de apenas um ou dois adapters. Dio expõe
falhas tipadas de cancelamento/transporte/HTTP/config e telemetria mínima.
Entidades/model/codegen ObjectBox pertencem ao consumidor e não há suporte web.
Sentry toma um Hub já inicializado emprestado. Rejeite instrumentação duplicada.
Siga os exemplos de
[Dio](../../packages/dartitect_dio/example/dartitect_dio_example.dart),
[ObjectBox](../../packages/dartitect_objectbox/example/dartitect_objectbox_example.dart)
e [Sentry](../../packages/dartitect_sentry/example/dartitect_sentry_example.dart).

## Grafo owned e troca atômica

Construa recursos relacionados transacionalmente e publique apenas uma raiz
completa:

```dart
final slot = OwnedRuntimeSlot<Api>(label: 'session');
await slot.replace((transaction) async {
  final client = transaction.own(Api(), (value) => value.close());
  return client;
});
await slot.use((api) => api.refresh());
await slot.disposeAsync();
```

Registre valores owned logo após a aquisição e valores borrowed com
`transaction.borrow`. Uma troca que falha faz rollback em ordem reversa e
mantém a geração anterior atual. O descarte rejeita novas operações, drena o
trabalho admitido e só então fecha recursos.

## Apresentação de snapshot local

Repositories publicam `ResourceSnapshot<T, M>` somente depois que a transação
local é autoridade. Flutter mapeia o estado reativo externo com
`toPresentation(isEmpty: ...)`; o resultado é waiting, content, empty ou
failure. O mapeamento não busca nem grava e preserva falhas esperadas separadas
de crashes e suas stacks originais.

## Sync foreground e headless

Modele datasets e pré-requisitos com `SyncDependencyGraph`. Um `SyncEngine` lê
checkpoints confirmados, executa a ordem estável do plano, persiste um novo
checkpoint com o fencing token ativo e deixa branches independentes continuarem
quando outro branch falha. Com lease configurado, o dataset recebe
`SyncAuthority`; valide-a imediatamente antes da transação local e compare/
commite atomicamente o fencing token em um Store capaz. O engine não promete
fencing do dataset quando o storage não aplica essa transação. Falha terminal
inesperada carrega report de `SyncRunTerminalException` com receipts separados
de application, checkpoint, journal, release do lease e cleanup; inspecione-o
antes de retry. Agendamento, retry, conflitos, transações de provider
e autenticação continuam políticas da aplicação. Para entrega em background,
valide um `SyncCommandEnvelope` versionado, crie um `OwnedGraph` novo dentro de
`HeadlessSyncEndpoint`, confirme a aceitação, deduplique request IDs e aguarde o
ACK terminal.

O workload completo sem provider está em
[`dartitect_sync_example.dart`](../../packages/dartitect_sync/example/dartitect_sync_example.dart).

## Validação

Para cada receita, teste sucesso, falha tipada, rethrow inesperado, cancelamento
ou concorrência, ordem de descarte e zero subscriptions/timers/queries/isolates
residuais. Use fakes determinísticos para policy e fixture provider/gerado real
para compatibilidade do SDK. Rode analyzer, testes focados, `dartitect scan
--no-baseline` e `dartitect doctor`; use baseline revisada somente para dívida
existente.
